const fs = require('node:fs');
const assert = require('node:assert/strict');
const path = require('node:path');
const test = require('node:test');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc } = require('firebase/firestore');
const { ref, getMetadata, uploadBytes } = require('firebase/storage');

const projectId = 'demo-english-learning-player';
let environment;

const sha = 'a'.repeat(64);
const payloadHash = 'b'.repeat(64);
const assetId = 'asset-001';
const materialId = 'material-001';
const storagePath = `users/alice/assets/${assetId}/${sha}`;
const assetDocument = {
  schemaVersion: 1,
  ownerId: 'alice',
  assetId,
  sha256: sha,
  byteLength: 4,
  mediaType: 'audio/mpeg',
  storagePath,
  opId: 'op-001',
  payloadHash,
};
const materialDocument = {
  schemaVersion: 1,
  ownerId: 'alice',
  materialId,
  title: 'Synthetic lesson',
  audioAssetId: assetId,
  assetSha256: sha,
  byteLength: 4,
  mediaType: 'audio/mpeg',
  storagePath,
  opId: 'op-001',
  payloadHash,
  status: 'cloudReady',
};

test.before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8'),
    },
    storage: {
      host: '127.0.0.1',
      port: 9199,
      rules: fs.readFileSync(path.join(__dirname, '../../storage.rules'), 'utf8'),
    },
  });
});

test.after(async () => {
  await environment?.cleanup();
});

test('Firestore owner can publish valid asset and material idempotently', async () => {
  const db = environment.authenticatedContext('alice').firestore();
  const assetRef = doc(db, `users/alice/mediaAssets/${assetId}`);
  const materialRef = doc(db, `users/alice/materials/${materialId}`);
  await assertSucceeds(setDoc(assetRef, assetDocument));
  await assertSucceeds(setDoc(materialRef, materialDocument));
  await assertSucceeds(setDoc(materialRef, materialDocument));
  await assertFails(setDoc(materialRef, { ...materialDocument, title: 'Changed title' }));
  assert.equal((await getDoc(materialRef)).data().status, 'cloudReady');
});

test('Firestore denies anonymous, cross UID, mismatched owner and invalid fields', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `users/alice/mediaAssets/${assetId}`), assetDocument);
  });
  const anonymous = environment.unauthenticatedContext().firestore();
  const alice = environment.authenticatedContext('alice').firestore();
  const bob = environment.authenticatedContext('bob').firestore();
  await assertFails(getDoc(doc(anonymous, `users/alice/materials/${materialId}`)));
  await assertFails(getDoc(doc(bob, `users/alice/mediaAssets/${assetId}`)));
  await assertFails(setDoc(doc(bob, `users/alice/materials/${materialId}`), materialDocument));
  await assertFails(setDoc(
    doc(alice, 'users/alice/materials/forged'),
    { ...materialDocument, ownerId: 'bob', materialId: 'forged' },
  ));
  await assertFails(setDoc(
    doc(alice, 'users/alice/materials/extra'),
    { ...materialDocument, materialId: 'extra', localPath: '/private/file' },
  ));
});

test('Storage allows owner read and immutable valid audio only', async () => {
  const alice = environment.authenticatedContext('alice').storage();
  const bob = environment.authenticatedContext('bob').storage();
  const anonymous = environment.unauthenticatedContext().storage();
  const metadata = {
    contentType: 'audio/mpeg',
    customMetadata: {
      ownerId: 'alice',
      assetId,
      sha256: sha,
      opId: 'op-001',
      payloadHash,
    },
  };
  const objectRef = ref(alice, storagePath);
  await assertSucceeds(uploadBytes(objectRef, new Uint8Array([1, 2, 3, 4]), metadata));
  const storedMetadata = await getMetadata(objectRef);
  assert.equal(storedMetadata.contentType, 'audio/mpeg');
  assert.equal(Number(storedMetadata.size), 4);
  await assertFails(uploadBytes(objectRef, new Uint8Array([1, 2, 3, 4]), metadata));
  await assertFails(uploadBytes(objectRef, new Uint8Array([4, 3, 2, 1]), metadata));
  await assertFails(getMetadata(ref(bob, storagePath)));
  await assertFails(getMetadata(ref(anonymous, storagePath)));
  await assertFails(uploadBytes(
    ref(bob, 'users/alice/assets/forged/hash'),
    new Uint8Array([1]),
    { contentType: 'audio/mpeg', customMetadata: { ...metadata.customMetadata, ownerId: 'bob' } },
  ));
  await assertFails(uploadBytes(
    ref(alice, 'users/alice/assets/invalid/hash'),
    new Uint8Array([1]),
    { contentType: 'text/plain', customMetadata: metadata.customMetadata },
  ));
});
