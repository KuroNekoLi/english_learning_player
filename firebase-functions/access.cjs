const readOnlyAlias = 'kuroneko_li@english-learning-player-auth.firebaseapp.com';

function isReadOnlyLogin(token) {
  return token?.firebase?.sign_in_provider === 'password' &&
    token.email === readOnlyAlias;
}

module.exports = { isReadOnlyLogin };
