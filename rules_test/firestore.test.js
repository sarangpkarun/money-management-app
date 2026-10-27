const { test, before, after, beforeEach } = require('node:test');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { readFileSync } = require('node:fs');
const { setDoc, getDoc, doc, deleteDoc, collection, addDoc } = require('firebase/firestore');

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'rules-test',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
});
after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const verified = (uid) =>
  env.authenticatedContext(uid, { email: `${uid}@x.com`, email_verified: true }).firestore();
const unverified = (uid) =>
  env.authenticatedContext(uid, { email: `${uid}@x.com`, email_verified: false }).firestore();
const anon = () => env.unauthenticatedContext().firestore();

test('signed-out users cannot read or write', async () => {
  await assertFails(getDoc(doc(anon(), 'users/alice')));
  await assertFails(setDoc(doc(anon(), 'users/alice'), { name: 'x' }));
});

test('verified owner can read and write own profile', async () => {
  const db = verified('alice');
  await assertSucceeds(setDoc(doc(db, 'users/alice'), { name: 'Alice' }));
  await assertSucceeds(getDoc(doc(db, 'users/alice')));
});

test('verified owner can use nested collections (people, transactions, payments)', async () => {
  const db = verified('alice');
  await assertSucceeds(setDoc(doc(db, 'users/alice/people/p1'), { name: 'Asha' }));
  await assertSucceeds(setDoc(doc(db, 'users/alice/transactions/t1'), { title: 'Loan' }));
  await assertSucceeds(
    addDoc(collection(db, 'users/alice/transactions/t1/payments'), { amount: 100 })
  );
  await assertSucceeds(deleteDoc(doc(db, 'users/alice/people/p1')));
});

test('owner with an unverified email is denied', async () => {
  const db = unverified('alice');
  await assertFails(setDoc(doc(db, 'users/alice'), { name: 'Alice' }));
  await assertFails(getDoc(doc(db, 'users/alice')));
  await assertFails(setDoc(doc(db, 'users/alice/people/p1'), { name: 'Asha' }));
});

test('a user cannot read or write another user’s data', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users/bob/people/p1'), { name: 'Secret' });
  });
  const alice = verified('alice');
  await assertFails(getDoc(doc(alice, 'users/bob/people/p1')));
  await assertFails(setDoc(doc(alice, 'users/bob/people/p2'), { name: 'x' }));
  await assertFails(deleteDoc(doc(alice, 'users/bob/people/p1')));
  await assertFails(setDoc(doc(alice, 'users/bob'), { name: 'x' }));
});

test('unknown top-level collections are denied even for verified users', async () => {
  const db = verified('alice');
  await assertFails(setDoc(doc(db, 'public/x'), { a: 1 }));
  await assertFails(getDoc(doc(db, 'admin/config')));
});

// ---- Trips ----

const { updateDoc, getDocs, query, where } = require('firebase/firestore');

// alice owns a trip; bob is an editor, carol a viewer (both accepted); dave is
// invited as an editor but has not logged in yet; erin is a stranger.
const seedTrip = () =>
  env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'trips/t1'), {
      name: 'Goa',
      ownerUid: 'alice',
      memberUids: ['alice', 'bob', 'carol'],
      editorUids: ['alice', 'bob'],
      memberEmails: ['alice@x.com', 'bob@x.com', 'carol@x.com', 'dave@x.com'],
      members: {
        'alice@x,com': { email: 'alice@x.com', role: 'owner', uid: 'alice' },
        'bob@x,com': { email: 'bob@x.com', role: 'editor', uid: 'bob' },
        'carol@x,com': { email: 'carol@x.com', role: 'viewer', uid: 'carol' },
        'dave@x,com': { email: 'dave@x.com', role: 'editor', uid: null },
      },
    });
    await setDoc(doc(db, 'trips/t1/expenses/e1'), { title: 'Hotel', amount: 100 });
  });

test('trips: any signed-in verified user can create their own trip', async () => {
  const db = verified('alice');
  await assertSucceeds(
    setDoc(doc(db, 'trips/new'), {
      name: 'Trip',
      ownerUid: 'alice',
      memberUids: ['alice'],
      editorUids: ['alice'],
      memberEmails: ['alice@x.com'],
      members: {},
    })
  );
  await assertFails(
    setDoc(doc(db, 'trips/other'), {
      name: 'Trip',
      ownerUid: 'bob',
      memberUids: ['bob'],
      editorUids: ['bob'],
      memberEmails: ['bob@x.com'],
      members: {},
    })
  );
});

test('trips: members and invitees can read, strangers cannot', async () => {
  await seedTrip();
  await assertSucceeds(getDoc(doc(verified('carol'), 'trips/t1')));
  await assertSucceeds(getDoc(doc(verified('dave'), 'trips/t1')));
  await assertFails(getDoc(doc(verified('erin'), 'trips/t1')));
  await assertFails(getDoc(doc(unverified('bob'), 'trips/t1')));
  await assertFails(getDoc(doc(anon(), 'trips/t1')));
});

test('trips: a member can list the trips addressed to their email', async () => {
  await seedTrip();
  await assertSucceeds(
    getDocs(query(collection(verified('dave'), 'trips'), where('memberEmails', 'array-contains', 'dave@x.com')))
  );
  await assertFails(getDocs(collection(verified('dave'), 'trips')));
});

test('trips: editors write expenses, viewers and strangers do not', async () => {
  await seedTrip();
  await assertSucceeds(setDoc(doc(verified('bob'), 'trips/t1/expenses/e2'), { title: 'Fuel' }));
  await assertSucceeds(updateDoc(doc(verified('alice'), 'trips/t1/expenses/e1'), { title: 'Hotel 2' }));
  await assertFails(setDoc(doc(verified('carol'), 'trips/t1/expenses/e3'), { title: 'x' }));
  await assertFails(deleteDoc(doc(verified('carol'), 'trips/t1/expenses/e1')));
  await assertFails(setDoc(doc(verified('erin'), 'trips/t1/expenses/e4'), { title: 'x' }));
  // Not yet accepted: read-only.
  await assertFails(setDoc(doc(verified('dave'), 'trips/t1/expenses/e5'), { title: 'x' }));
});

test('trips: members read expenses and stops, strangers do not', async () => {
  await seedTrip();
  await assertSucceeds(getDoc(doc(verified('carol'), 'trips/t1/expenses/e1')));
  await assertFails(getDoc(doc(verified('erin'), 'trips/t1/expenses/e1')));
  await assertFails(getDoc(doc(verified('dave'), 'trips/t1/expenses/e1')));
});

test('trips: editors change details but not members or roles', async () => {
  await seedTrip();
  await assertSucceeds(updateDoc(doc(verified('bob'), 'trips/t1'), { name: 'Goa 2' }));
  await assertFails(updateDoc(doc(verified('bob'), 'trips/t1'), { editorUids: ['alice', 'bob', 'carol'] }));
  await assertFails(updateDoc(doc(verified('bob'), 'trips/t1'), { memberEmails: ['bob@x.com'] }));
  await assertFails(updateDoc(doc(verified('carol'), 'trips/t1'), { name: 'Nope' }));
});

test('trips: only the owner manages members and deletes', async () => {
  await seedTrip();
  await assertSucceeds(
    updateDoc(doc(verified('alice'), 'trips/t1'), {
      memberEmails: ['alice@x.com', 'bob@x.com'],
    })
  );
  await assertFails(updateDoc(doc(verified('alice'), 'trips/t1'), { ownerUid: 'bob' }));
  await assertFails(deleteDoc(doc(verified('bob'), 'trips/t1')));
  await assertSucceeds(deleteDoc(doc(verified('alice'), 'trips/t1')));
});

test('trips: an invitee can accept their own invite, and only that', async () => {
  await seedTrip();
  const db = verified('dave');
  await assertSucceeds(
    updateDoc(doc(db, 'trips/t1'), {
      'members.dave@x,com.uid': 'dave',
      memberUids: ['alice', 'bob', 'carol', 'dave'],
      editorUids: ['alice', 'bob', 'dave'],
    })
  );
  await assertSucceeds(setDoc(doc(db, 'trips/t1/expenses/e9'), { title: 'Now allowed' }));
});

test('trips: an invitee cannot upgrade a viewer invite or add someone else', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'trips/t2'), {
      name: 'Viewers',
      ownerUid: 'alice',
      memberUids: ['alice'],
      editorUids: ['alice'],
      memberEmails: ['alice@x.com', 'dave@x.com'],
      members: {
        'alice@x,com': { email: 'alice@x.com', role: 'owner', uid: 'alice' },
        'dave@x,com': { email: 'dave@x.com', role: 'viewer', uid: null },
      },
    });
  });
  const db = verified('dave');
  await assertFails(
    updateDoc(doc(db, 'trips/t2'), {
      memberUids: ['alice', 'dave'],
      editorUids: ['alice', 'dave'],
    })
  );
  await assertFails(
    updateDoc(doc(db, 'trips/t2'), { memberUids: ['alice', 'dave', 'erin'] })
  );
  await assertSucceeds(updateDoc(doc(db, 'trips/t2'), { memberUids: ['alice', 'dave'] }));
});

test('trips: a stranger cannot add themselves', async () => {
  await seedTrip();
  await assertFails(
    updateDoc(doc(verified('erin'), 'trips/t1'), {
      memberUids: ['alice', 'bob', 'carol', 'erin'],
      editorUids: ['alice', 'bob', 'erin'],
    })
  );
});
