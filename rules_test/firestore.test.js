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
