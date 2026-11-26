const fs = require('node:fs');
const { createHash } = require('node:crypto');
const assert = require('node:assert/strict');
const path = require('node:path');
const test = require('node:test');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const { deleteDoc, doc, getDoc, runTransaction, setDoc } = require('firebase/firestore');
const { deleteObject, ref, getBytes, getMetadata, updateMetadata, uploadBytes } = require('firebase/storage');
const {
  isGoogleOwner,
  isReadOnlyLogin,
  readerEmail,
} = require('../../firebase-functions/access.cjs');

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

test('read-only access requires a server-issued owner claim', () => {
  assert.equal(isReadOnlyLogin({
    elpReadOnlyOwnerUid: 'owner-uid',
  }), true);
  assert.equal(isReadOnlyLogin({
    firebase: { sign_in_provider: 'password' },
  }), false);
  assert.equal(isGoogleOwner({ firebase: { sign_in_provider: 'google.com' } },
    'owner-uid', 'owner-uid'), true);
  assert.equal(isGoogleOwner({ firebase: { sign_in_provider: 'google.com' } },
    'other-uid', 'owner-uid'), false);
  assert.equal(readerEmail('kuroneko_li', 'english-learning-player-auth'),
    'kuroneko_li@english-learning-player-auth.firebaseapp.com');
  assert.throws(() => readerEmail('other', 'english-learning-player-auth'));
});

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

test('separate reader UID reads owner materials but cannot write or cross owners', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users/shared-owner/materials/password-reader'), {
      ...materialDocument,
      ownerId: 'shared-owner',
      materialId: 'password-reader',
      storagePath: `users/shared-owner/assets/${assetId}/${sha}`,
    });
  });
  const passwordUser = environment.authenticatedContext('reader-user', {
    elpReadOnlyOwnerUid: 'shared-owner',
  }).firestore();
  const path = 'users/shared-owner/materials/password-reader';
  await assertSucceeds(getDoc(doc(passwordUser, path)));
  await assertFails(getDoc(doc(passwordUser, 'users/another-owner/materials/password-reader')));
  await assertFails(setDoc(doc(passwordUser, 'users/shared-owner/materials/new'), {
    ...materialDocument,
    ownerId: 'shared-owner',
    materialId: 'new',
  }));
  await assertFails(deleteDoc(doc(passwordUser, path)));
  const ordinaryPassword = environment.authenticatedContext('ordinary-password', {
    firebase: { sign_in_provider: 'password' },
    email: 'ordinary@example.com',
  }).firestore();
  await assertSucceeds(setDoc(
    doc(ordinaryPassword, `users/ordinary-password/mediaAssets/${assetId}`),
    {
      ...assetDocument,
      ownerId: 'ordinary-password',
      storagePath: `users/ordinary-password/assets/${assetId}/${sha}`,
    },
  ));
});

test('Storage permits owner updates only when bytes and identity stay unchanged', async () => {
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
  await assertSucceeds(updateMetadata(objectRef, { contentDisposition: 'inline' }));
  await assertFails(uploadBytes(objectRef, new Uint8Array([4, 3, 2, 1]), metadata));
  await assertFails(uploadBytes(objectRef, new Uint8Array([1, 2, 3, 4]), {
    ...metadata,
    customMetadata: { ...metadata.customMetadata, sha256: 'c'.repeat(64) },
  }));
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
  await assertFails(getMetadata(ref(bob, storagePath)));
  await assertFails(getMetadata(ref(anonymous, storagePath)));
  await assertFails(deleteObject(ref(bob, storagePath)));
  await assertFails(deleteObject(ref(anonymous, storagePath)));
  await assertSucceeds(deleteObject(objectRef));
});

test('separate reader UID reads Storage but cannot mutate or cross owners', async () => {
  const owner = environment.authenticatedContext('shared-storage-owner').storage();
  const passwordUser = environment.authenticatedContext('shared-storage-reader', {
    elpReadOnlyOwnerUid: 'shared-storage-owner',
  }).storage();
  const storagePath = `users/shared-storage-owner/assets/${assetId}/${sha}`;
  const object = ref(owner, storagePath);
  const metadata = {
    contentType: 'audio/mpeg',
    customMetadata: {
      ownerId: 'shared-storage-owner', assetId, sha256: sha,
      opId: 'op-001', payloadHash,
    },
  };
  await assertSucceeds(uploadBytes(object, new Uint8Array([1, 2, 3]), metadata));
  await assertSucceeds(getBytes(ref(passwordUser, storagePath)));
  await assertFails(getBytes(ref(passwordUser,
    `users/another-storage-owner/assets/${assetId}/${sha}`)));
  await assertFails(uploadBytes(ref(passwordUser,
    `users/shared-storage-owner/assets/other/${'c'.repeat(64)}`),
  new Uint8Array([1]), { ...metadata, customMetadata: { ...metadata.customMetadata, assetId: 'other', sha256: 'c'.repeat(64) } }));
  await assertFails(deleteObject(ref(passwordUser, storagePath)));
  const ordinaryPassword = environment.authenticatedContext('ordinary-storage-user', {
    firebase: { sign_in_provider: 'password' },
    email: 'ordinary@example.com',
  }).storage();
  await assertSucceeds(uploadBytes(
    ref(ordinaryPassword, `users/ordinary-storage-user/assets/${assetId}/${sha}`),
    new Uint8Array([7]),
    { ...metadata, customMetadata: { ...metadata.customMetadata, ownerId: 'ordinary-storage-user' } },
  ));
});

// Reference transaction executed on the local emulator as a trusted writer.
// The Flutter transport and its authenticated server entry point are separate.
function commitProgress(db, { uid, materialId, streamId, sequence, baseRevision, positionMs, opId, hash }) {
  const root = `users/${uid}`;
  const canonicalRef = doc(db, `${root}/progress/${materialId}`);
  const streamRef = doc(canonicalRef, 'streams', streamId);
  const candidateRef = doc(canonicalRef, 'candidates', streamId);
  const receiptRef = doc(db, `${root}/progressReceipts/${opId}`);
  return runTransaction(db, async (tx) => {
    const receipt = (await tx.get(receiptRef)).data();
    if (receipt) {
      if (receipt.hash !== hash) throw new Error('opId payload changed');
      return receipt.result;
    }
    const canonical = (await tx.get(canonicalRef)).data() ?? { revision: 0 };
    const stream = (await tx.get(streamRef)).data() ?? { sequence: 0 };

    let result = { status: 'ignoredStale', canonical };
    if (sequence > stream.sequence) {
      tx.set(streamRef, { sequence });
      const checkpoint = { streamId, sequence, baseRevision, positionMs };
      if (baseRevision === canonical.revision) {
        result = { status: 'accepted', canonical: { ...checkpoint, revision: canonical.revision + 1 } };
        tx.set(canonicalRef, result.canonical);
      } else {
        result = { status: 'conflict', canonical, candidateId: streamId };
        tx.set(candidateRef, checkpoint);
      }
    }
    tx.set(receiptRef, { hash, result });
    return result;
  });
}

test('Firestore transaction preserves an offline conflict and a replay receipt', async () => {
  await environment.withSecurityRulesDisabled(async (firstContext) => {
    await environment.withSecurityRulesDisabled(async (secondContext) => {
      const firstDevice = firstContext.firestore();
      const secondDevice = secondContext.firestore();
      assert.notEqual(firstDevice, secondDevice);
      const base = { uid: 'progress-owner', materialId: 'lesson', sequence: 1, baseRevision: 0 };
      const mac = { ...base, streamId: 'mac', positionMs: 5000, opId: 'mac-op', hash: 'mac-hash' };
      const phone = { ...base, streamId: 'phone', positionMs: 20000, opId: 'phone-op', hash: 'phone-hash' };
      const results = await Promise.all([commitProgress(firstDevice, mac), commitProgress(secondDevice, phone)]);
      assert.deepEqual(results.map((result) => result.status).sort(), ['accepted', 'conflict']);
      const accepted = results.find((result) => result.status === 'accepted');
      const conflict = results.find((result) => result.status === 'conflict');
      const losingRequest = [mac, phone].find((request) => request.streamId === conflict.candidateId);
      assert.deepEqual(conflict.canonical, accepted.canonical);

      const parent = doc(firstDevice, 'users/progress-owner/progress/lesson');
      const candidate = doc(parent, 'candidates', losingRequest.streamId);
      assert.equal((await getDoc(parent)).data().revision, 1);
      assert.equal((await getDoc(candidate)).data().positionMs, losingRequest.positionMs);
      assert.deepEqual(await commitProgress(firstDevice, losingRequest), conflict);
      await assert.rejects(commitProgress(firstDevice, { ...losingRequest, hash: 'mutated' }), /payload changed/);
      const stale = await commitProgress(firstDevice, { ...losingRequest, opId: 'stale-op', hash: 'stale-hash' });
      assert.equal(stale.status, 'ignoredStale');
      assert.equal((await getDoc(parent)).data().revision, 1);
    });
  });

  // Owners may read their canonical position. Writes and receipts require the callable.
  await assertSucceeds(getDoc(doc(environment.authenticatedContext('progress-owner').firestore(),
    'users/progress-owner/progress/lesson')));
  await assertFails(getDoc(doc(environment.authenticatedContext('other').firestore(),
    'users/progress-owner/progress/lesson')));
  for (const viewer of [
    environment.authenticatedContext('progress-owner'),
    environment.authenticatedContext('other'),
    environment.unauthenticatedContext(),
  ]) {
    const db = viewer.firestore();
    const canonical = doc(db, 'users/progress-owner/progress/lesson');
    await assertFails(setDoc(canonical, { revision: 99 }));
    await assertFails(setDoc(doc(db, 'users/progress-owner/progressReceipts/fake'), { hash: 'fake' }));
  }
});

test('receiver can download and verify the published object only under the same UID', async () => {
  const sender = environment.authenticatedContext('alice');
  const receiver = environment.authenticatedContext('alice');
  const unauthorized = environment.authenticatedContext('someone-else');
  const fixture = Uint8Array.from([9, 7, 5, 3]);
  const digest = createHash('sha256').update(fixture).digest('hex');
  const assetId = 'wp14-asset';
  const materialId = 'wp14-material';
  const storagePath = `users/alice/assets/${assetId}/${digest}`;

  await uploadBytes(ref(sender.storage(), storagePath), fixture, {
    contentType: 'audio/mpeg',
    customMetadata: { ownerId: 'alice', assetId, sha256: digest, opId: assetDocument.opId, payloadHash },
  });
  await setDoc(doc(sender.firestore(), `users/alice/mediaAssets/${assetId}`), {
    ...assetDocument, assetId, sha256: digest, storagePath,
  });
  const documentPath = `users/alice/materials/${materialId}`;
  await setDoc(doc(sender.firestore(), documentPath), {
    ...materialDocument, materialId, audioAssetId: assetId, assetSha256: digest, storagePath,
  });

  const published = (await getDoc(doc(receiver.firestore(), documentPath))).data();
  const remote = ref(receiver.storage(), published.storagePath);
  const downloaded = Buffer.from(await getBytes(remote));
  assert.equal((await getMetadata(remote)).contentType, published.mediaType);
  assert.equal(downloaded.length, published.byteLength);
  assert.equal(createHash('sha256').update(downloaded).digest('hex'), published.assetSha256);
  await assertFails(getDoc(doc(unauthorized.firestore(), documentPath)));
  await assertFails(getBytes(ref(unauthorized.storage(), storagePath)));
});

test('subtitle manifests and mutable object metadata are restricted to the owner', async () => {
  const alice = environment.authenticatedContext('alice');
  const bob = environment.authenticatedContext('bob');
  const anonymous = environment.unauthenticatedContext();
  const bytes = Buffer.from('1\n00:00:00,000 --> 00:00:01,000\nSynthetic\n');
  const digest = createHash('sha256').update(bytes).digest('hex');
  const subtitleMaterialId = 'subtitle-material';
  const materialPath = `users/alice/materials/${subtitleMaterialId}`;
  const objectPath = `users/alice/subtitles/${subtitleMaterialId}/${digest}`;
  const manifestPath = `${materialPath}/subtitleTracks/en`;
  const manifest = {
    schemaVersion: 1,
    ownerId: 'alice',
    materialId: subtitleMaterialId,
    languageTag: 'en',
    sha256: digest,
    byteLength: bytes.length,
    revision: 1,
    offsetMs: 100,
    storagePath: objectPath,
  };
  const metadata = {
    contentType: 'application/x-subrip',
    customMetadata: { ownerId: 'alice', sha256: digest },
  };

  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), materialPath), {
      ...materialDocument, materialId: subtitleMaterialId,
    });
  });
  await assertSucceeds(setDoc(doc(alice.firestore(), manifestPath), manifest));
  await assertSucceeds(uploadBytes(ref(alice.storage(), objectPath), bytes, metadata));
  assert.equal((await getDoc(doc(alice.firestore(), manifestPath))).data().offsetMs, 100);
  assert.deepEqual(Buffer.from(await getBytes(ref(alice.storage(), objectPath))), bytes);
  await assertSucceeds(updateMetadata(ref(alice.storage(), objectPath), {
    contentDisposition: 'inline',
  }));
  await assertFails(uploadBytes(ref(alice.storage(), objectPath), Buffer.from('changed'), metadata));
  await assertFails(setDoc(doc(alice.firestore(), manifestPath), {
    ...manifest, storagePath: objectPath.replace('alice', 'bob'),
  }));
  for (const outsider of [bob, anonymous]) {
    await assertFails(getDoc(doc(outsider.firestore(), manifestPath)));
    await assertFails(setDoc(doc(outsider.firestore(), manifestPath), manifest));
    await assertFails(getBytes(ref(outsider.storage(), objectPath)));
    await assertFails(deleteObject(ref(outsider.storage(), objectPath)));
  }
  await assertSucceeds(deleteObject(ref(alice.storage(), objectPath)));
});

test('library structure is UID-scoped and validates placement and persistent tombstones', async () => {
  const alice = environment.authenticatedContext('alice').firestore();
  const bob = environment.authenticatedContext('bob').firestore();
  const anonymous = environment.unauthenticatedContext().firestore();
  const base = 'users/alice/libraryChanges';
  const placement = doc(alice, `${base}/materialFolders_lesson`);
  const tombstone = doc(alice, `${base}/materialDeleted_lesson`);
  const data = {
    ownerId: 'alice', schemaVersion: 1, field: 'materialFolders',
    entityId: 'lesson', value: '["parent","child"]', revision: 2,
    opId: '23000000-0000-4000-8000-000000000000',
  };
  await assertSucceeds(setDoc(placement, data));
  await assertFails(setDoc(placement, { ...data, revision: 1 }));
  await assertFails(setDoc(placement, { ...data, value: '["../../private"]' }));
  await assertFails(setDoc(placement, { ...data, sourcePath: '/private/file' }));
  await assertFails(getDoc(doc(bob, placement.path)));
  await assertFails(getDoc(doc(anonymous, placement.path)));
  await assertFails(setDoc(doc(bob, placement.path), data));
  await assertSucceeds(setDoc(tombstone, { ...data, field: 'materialDeleted', value: '1' }));
  await assertFails(setDoc(tombstone, { ...data, field: 'materialDeleted', value: '0', revision: 3 }));
  await assertFails(deleteDoc(tombstone));
});

test('word bank permits owner revisions and authorizes only its reader', async () => {
  const alice = environment.authenticatedContext('alice').firestore();
  const reader = environment.authenticatedContext('alice-reader', {
    elpReadOnlyOwnerUid: 'alice',
  }).firestore();
  const bob = environment.authenticatedContext('bob').firestore();
  const guest = environment.unauthenticatedContext().firestore();
  const path = "users/alice/wordBank/isn't";
  const word = doc(alice, path);
  const saved = {
    schemaVersion: 1, ownerId: 'alice', word: "isn't", payload: '{}',
    savedAtMs: 123, opId: 'a'.repeat(32), revision: 1,
  };
  await assertFails(setDoc(word, { ...saved, revision: 2 }));
  await assertFails(setDoc(word, { ...saved, word: 'hello' }));
  await assertSucceeds(setDoc(word, saved));
  await assertSucceeds(getDoc(doc(reader, path)));
  await assertFails(getDoc(doc(bob, path)));
  await assertFails(getDoc(doc(guest, path)));
  const removed = { ...saved, payload: '', revision: 2, opId: 'b'.repeat(32) };
  await assertFails(setDoc(doc(reader, path), removed));
  await assertFails(setDoc(doc(bob, path), removed));
  await assertFails(setDoc(word, { ...removed, opId: saved.opId }));
  await assertSucceeds(setDoc(word, removed));
  await assertFails(setDoc(word, saved));
  await assertFails(deleteDoc(word));
});
