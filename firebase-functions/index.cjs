const { createHash } = require('node:crypto');
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineString } = require('firebase-functions/params');
const { isReadOnlyLogin, isGoogleOwner, readerEmail } = require('./access.cjs');

initializeApp();

const id = (value) => typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);
const count = (value, min) => Number.isSafeInteger(value) && value >= min;
const hash = (value) => createHash('sha256').update(value).digest('hex');
const states = new Set(['playing', 'paused', 'stopped', 'completed']);
const readOnlyOwnerUid = defineString('ELP_READONLY_OWNER_UID', { default: '' });

function parse(uid, data) {
  if (!id(uid) || !id(data?.opId) || !data?.payload ||
      typeof data.payload !== 'object' || Array.isArray(data.payload)) {
    throw new HttpsError('invalid-argument', 'Invalid progress operation.');
  }
  const value = data.payload;
  if (value.ownerId !== uid) {
    throw new HttpsError('permission-denied', 'The operation belongs to another account.');
  }
  if (value.schemaVersion !== 1 || !id(value.materialId) ||
      !id(value.deviceId) || !id(value.sessionId) ||
      !count(value.positionMs, 0) || !states.has(value.state) ||
      !count(value.sequence, 1) || !count(value.baseRevision, 0)) {
    throw new HttpsError('invalid-argument', 'Invalid checkpoint.');
  }
  const checkpoint = {
    schemaVersion: 1,
    ownerId: uid,
    materialId: value.materialId,
    deviceId: value.deviceId,
    sessionId: value.sessionId,
    positionMs: value.positionMs,
    state: value.state,
    sequence: value.sequence,
    baseRevision: value.baseRevision,
  };
  let resolution;
  if ('resolveCandidateId' in value) {
    if (!id(value.resolveCandidateId) ||
        !count(value.observedCanonicalRevision, 1) ||
        value.observedCanonicalRevision !== value.baseRevision ||
        typeof value.useCandidatePosition !== 'boolean') {
      throw new HttpsError('invalid-argument', 'Invalid conflict resolution.');
    }
    resolution = {
      resolveCandidateId: value.resolveCandidateId,
      observedCanonicalRevision: value.observedCanonicalRevision,
      useCandidatePosition: value.useCandidatePosition,
    };
  }
  const payload = { ...checkpoint, ...resolution };
  if (Object.keys(value).length !== Object.keys(payload).length ||
      hash(JSON.stringify(payload)) !== data.payloadHash) {
    throw new HttpsError('invalid-argument', 'Invalid payload hash.');
  }
  return { checkpoint, resolution };
}

exports.syncProgress = onCall({
  region: process.env.ELP_PROGRESS_REGION || 'us-central1',
  timeoutSeconds: 30,
}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to sync progress.');
  if (isReadOnlyLogin(request.auth.token)) {
    throw new HttpsError('permission-denied', 'Password sign-in is read-only.');
  }
  const { checkpoint, resolution } = parse(uid, request.data);
  const { opId, payloadHash } = request.data;
  const db = getFirestore();
  const user = db.collection('users').doc(uid);
  const material = user.collection('materials').doc(checkpoint.materialId);
  const canonical = user.collection('progress').doc(checkpoint.materialId);
  const receipt = user.collection('progressReceipts').doc(opId);
  const streamId = hash(JSON.stringify([checkpoint.deviceId, checkpoint.sessionId]));
  const stream = canonical.collection('streams').doc(streamId);
  const candidateId = resolution?.resolveCandidateId ?? streamId;
  const candidate = canonical.collection('candidates').doc(candidateId);

  return db.runTransaction(async (tx) => {
    const previous = (await tx.get(receipt)).data();
    if (previous) {
      if (previous.payloadHash !== payloadHash) {
        throw new HttpsError('invalid-argument', 'Operation ID was already used.');
      }
      return previous.result;
    }
    if (!(await tx.get(material)).exists) {
      throw new HttpsError('failed-precondition', 'Publish the material first.');
    }
    const current = (await tx.get(canonical)).data();
    const highWater = (await tx.get(stream)).data()?.sequence ?? 0;
    const selected = resolution ? (await tx.get(candidate)).data() : null;
    const revision = current?.revision ?? 0;
    let result = {
      status: 'ignoredStale',
      canonicalRevision: revision,
      canonicalCheckpoint: current?.checkpoint ?? null,
    };

    if (checkpoint.sequence > highWater) {
      tx.set(stream, { sequence: checkpoint.sequence });
      if (resolution) {
        const choice = resolution.useCandidatePosition ? selected?.checkpoint : current?.checkpoint;
        if (selected && choice && revision === resolution.observedCanonicalRevision &&
            choice.positionMs === checkpoint.positionMs && choice.state === checkpoint.state) {
          tx.delete(candidate);
          result = accept();
        } else {
          result = { ...result, status: 'conflict', candidateId };
        }
      } else if (checkpoint.baseRevision === revision) {
        result = accept();
      } else {
        tx.set(candidate, { checkpoint, createdAt: FieldValue.serverTimestamp() });
        result = { ...result, status: 'conflict', candidateId };
      }
    }
    tx.set(receipt, { payloadHash, result, createdAt: FieldValue.serverTimestamp() });
    return result;

    function accept() {
      const canonicalRevision = revision + 1;
      tx.set(canonical, { revision: canonicalRevision, checkpoint, updatedAt: FieldValue.serverTimestamp() });
      return { status: 'accepted', canonicalRevision, canonicalCheckpoint: checkpoint };
    }
  });
});

exports.provisionReadOnlyLogin = onCall({
  region: process.env.ELP_PROGRESS_REGION || 'us-central1',
  timeoutSeconds: 30,
  // The handler still verifies the Firebase Google owner and configured UID.
  invoker: 'public',
}, async (request) => {
  const ownerUid = request.auth?.uid;
  const allowedOwnerUid = readOnlyOwnerUid.value().trim();
  if (!isGoogleOwner(request.auth?.token, ownerUid, allowedOwnerUid)) {
    throw new HttpsError('permission-denied', 'This account cannot provision the reader.');
  }

  const username = request.data?.username;
  const password = request.data?.password;
  if (username !== 'kuroneko_li' || typeof password !== 'string' ||
      password.length < 6 || password.length > 4096) {
    throw new HttpsError('invalid-argument', 'Invalid reader credentials.');
  }

  const firebaseConfig = JSON.parse(process.env.FIREBASE_CONFIG || '{}');
  const projectId = process.env.GCLOUD_PROJECT || firebaseConfig.projectId || '';
  const email = readerEmail(username, projectId);
  const auth = getAuth();
  let reader;
  let created = false;
  try {
    try {
      reader = await auth.getUserByEmail(email);
      if (reader.customClaims?.elpReadOnlyOwnerUid !== ownerUid) {
        throw new HttpsError('already-exists', 'The reader identity is already assigned.');
      }
      await auth.updateUser(reader.uid, { password, disabled: false });
      reader = await auth.getUser(reader.uid);
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      if (error.code !== 'auth/user-not-found') throw error;
      reader = await auth.createUser({ email, password, displayName: username });
      created = true;
    }
    await auth.setCustomUserClaims(reader.uid, {
      ...(reader.customClaims ?? {}),
      elpReadOnlyOwnerUid: ownerUid,
    });
    return { readerUid: reader.uid };
  } catch (error) {
    if (created && reader?.uid) {
      try {
        await auth.deleteUser(reader.uid);
      } catch (_) {
        // Keep the provisioning failure; no credential or token is logged.
      }
    }
    if (error instanceof HttpsError) throw error;
    if (error.code === 'auth/email-already-exists') {
      throw new HttpsError('already-exists', 'The reader identity is already assigned.');
    }
    throw new HttpsError('internal', 'Unable to provision the reader account.');
  }
});
