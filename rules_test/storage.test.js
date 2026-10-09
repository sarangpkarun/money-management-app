const { test, before, after } = require('node:test');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { readFileSync } = require('node:fs');
const { ref, uploadBytes, getBytes, deleteObject } = require('firebase/storage');

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'rules-test',
    storage: { rules: readFileSync('../storage.rules', 'utf8') },
  });
});
after(() => env.cleanup());

const storageFor = (uid, verifiedEmail) =>
  env
    .authenticatedContext(uid, { email: `${uid}@x.com`, email_verified: verifiedEmail })
    .storage();

const png = (bytes = 10) => ({ contentType: 'image/png', size: bytes });
const data = (n) => new Uint8Array(n);

test('verified owner can upload, read and delete an image under their path', async () => {
  const s = storageFor('alice', true);
  const r = ref(s, 'users/alice/bills/a.png');
  await assertSucceeds(uploadBytes(r, data(10), png()));
  await assertSucceeds(getBytes(r));
  await assertSucceeds(deleteObject(r));
});

test('signed-out users are denied', async () => {
  const s = env.unauthenticatedContext().storage();
  await assertFails(uploadBytes(ref(s, 'users/alice/a.png'), data(10), png()));
});

test('unverified email is denied', async () => {
  const s = storageFor('alice', false);
  await assertFails(uploadBytes(ref(s, 'users/alice/a.png'), data(10), png()));
});

test('another user’s files are denied', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await uploadBytes(ref(ctx.storage(), 'users/bob/a.png'), data(10), png());
  });
  const s = storageFor('alice', true);
  await assertFails(getBytes(ref(s, 'users/bob/a.png')));
  await assertFails(uploadBytes(ref(s, 'users/bob/b.png'), data(10), png()));
  await assertFails(deleteObject(ref(s, 'users/bob/a.png')));
});

test('non-image uploads are rejected', async () => {
  const s = storageFor('alice', true);
  await assertFails(
    uploadBytes(ref(s, 'users/alice/a.pdf'), data(10), { contentType: 'application/pdf' })
  );
});

test('uploads of 10 MB or more are rejected', async () => {
  const s = storageFor('alice', true);
  await assertFails(
    uploadBytes(ref(s, 'users/alice/big.png'), data(10 * 1024 * 1024), {
      contentType: 'image/png',
    })
  );
});

test('paths outside users/{uid} are denied', async () => {
  const s = storageFor('alice', true);
  await assertFails(uploadBytes(ref(s, 'other/a.png'), data(10), png()));
});
