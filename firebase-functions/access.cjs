function isReadOnlyLogin(token) {
  const ownerUid = token?.elpReadOnlyOwnerUid;
  return typeof ownerUid === 'string' &&
    ownerUid.length > 0;
}

function isGoogleOwner(token, authenticatedUid, allowedOwnerUid) {
  return typeof authenticatedUid === 'string' &&
    authenticatedUid.length > 0 &&
    authenticatedUid === allowedOwnerUid &&
    token?.firebase?.sign_in_provider === 'google.com' &&
    !isReadOnlyLogin(token);
}

function readerEmail(username, project) {
  if (username !== 'kuroneko_li' || project !== 'english-learning-player-auth') {
    throw new Error('invalid-readonly-username');
  }
  return `${username}@${project}.firebaseapp.com`;
}

module.exports = { isReadOnlyLogin, isGoogleOwner, readerEmail };
