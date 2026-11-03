const analytics = require('./analytics');

function onSignup(user) {
  analytics.track('signup', { plan: user.plan, email: user.email, source: user.source });
  return { ok: true };
}

module.exports = { onSignup };
