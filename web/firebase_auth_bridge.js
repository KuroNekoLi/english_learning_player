import { getApp, getApps, initializeApp } from 'https://www.gstatic.com/firebasejs/13.4.0/firebase-app.js';
import {
  browserLocalPersistence,
  getAuth,
  GoogleAuthProvider,
  setPersistence,
  signInWithPopup,
  signOut,
} from 'https://www.gstatic.com/firebasejs/13.4.0/firebase-auth.js';

let auth;

function result(value) {
  return JSON.stringify(value);
}

function authCode(error) {
  return typeof error?.code === 'string' ? error.code : 'auth/unknown';
}

globalThis.elpFirebaseAuthInitialize = async (optionsJson) => {
  try {
    const options = JSON.parse(optionsJson);
    const app = getApps().some((candidate) => candidate.name === 'elp-web-auth')
      ? getApp('elp-web-auth')
      : initializeApp(options, 'elp-web-auth');
    auth = getAuth(app);
    await setPersistence(auth, browserLocalPersistence);
    await auth.authStateReady();
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
    return result({ uid: credential.user.uid });
  } catch (error) {
    // Do not return provider tokens, email addresses or raw SDK error messages.
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
