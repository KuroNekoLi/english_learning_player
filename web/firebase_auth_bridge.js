import { getApp, getApps, initializeApp } from 'https://www.gstatic.com/firebasejs/13.4.0/firebase-app.js';
import {
  browserLocalPersistence,
  getAuth,
  GoogleAuthProvider,
  EmailAuthProvider,
  linkWithCredential,
  signInWithEmailAndPassword,
  setPersistence,
  signInWithPopup,
  signOut,
} from 'https://www.gstatic.com/firebasejs/13.4.0/firebase-auth.js';

let auth;
let readOnly = false;
let readOnlyEmail;

function result(value) {
  return JSON.stringify(value);
}

function authCode(error) {
  return typeof error?.code === 'string' ? error.code : 'auth/unknown';
}

globalThis.elpFirebaseAuthInitialize = async (optionsJson) => {
  try {
    const options = JSON.parse(optionsJson);
    readOnlyEmail = `kuroneko_li@${options.project}.firebaseapp.com`;
    const app = getApps().some((candidate) => candidate.name === 'elp-web-auth')
      ? getApp('elp-web-auth')
      : initializeApp(options, 'elp-web-auth');
    auth = getAuth(app);
    await setPersistence(auth, browserLocalPersistence);
    await auth.authStateReady();
    await refreshReadOnly();
    globalThis.elpFirebaseAuthBridgeResolve(true);
    return result({ uid: auth.currentUser?.uid ?? null });
  } catch (error) {
    globalThis.elpFirebaseAuthBridgeResolve(false);
    return result({ error: authCode(error) });
  }
};

globalThis.elpFirebaseAuthSignInWithGoogle = async () => {
  if (!auth) return result({ error: 'auth/not-initialized' });
  try {
    const credential = await signInWithPopup(auth, new GoogleAuthProvider());
    await refreshReadOnly();
    return result({ uid: credential.user.uid });
  } catch (error) {
    // Do not return provider tokens, email addresses or raw SDK error messages.
    return result({ error: authCode(error) });
  }
};

globalThis.elpFirebaseAuthSignInWithUsername = async (email, password) => {
  if (!auth) return result({ error: 'auth/not-initialized' });
  try {
    const credential = await signInWithEmailAndPassword(auth, email, password);
    await refreshReadOnly();
    return result({ uid: credential.user.uid });
  } catch (error) {
    return result({ error: authCode(error) });
  }
};

globalThis.elpFirebaseAuthLinkReadOnlyUsername = async (email, password) => {
  const user = auth?.currentUser;
  if (!user) return result({ error: 'auth/user-mismatch' });
  try {
    await linkWithCredential(user, EmailAuthProvider.credential(email, password));
    return result({ uid: user.uid });
  } catch (error) {
    return result({ error: authCode(error) });
  }
};

globalThis.elpFirebaseAuthSignOut = async () => {
  if (!auth) return result({ error: 'auth/not-initialized' });
  try {
    await signOut(auth);
    return result({ ok: true });
  } catch (error) {
    return result({ error: authCode(error) });
  }
};

globalThis.elpFirebaseAuthCurrentUid = () => auth?.currentUser?.uid ?? null;
globalThis.elpFirebaseAuthIsReadOnly = () => readOnly;

globalThis.elpFirebaseAuthGetIdToken = async (expectedUid) => {
  const user = auth?.currentUser;
  if (!user || user.uid !== expectedUid) {
    return result({ error: 'auth/user-mismatch' });
  }
  try {
    const token = await user.getIdToken();
    if (auth.currentUser !== user) return result({ error: 'auth/user-mismatch' });
    return result({ uid: user.uid, token });
  } catch (error) {
    return result({ error: authCode(error) });
  }
};

async function refreshReadOnly() {
  const user = auth?.currentUser;
  if (!user) {
    readOnly = false;
    return;
  }
  const token = await user.getIdTokenResult();
  readOnly = token.claims.firebase?.sign_in_provider === 'password'
    && user.email === readOnlyEmail;
}
