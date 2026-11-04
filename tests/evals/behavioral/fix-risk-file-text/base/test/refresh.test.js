const t = require('node:test');
const a = require('node:assert');
const { canRefresh } = require('../src/auth/refresh');

t('canRefresh returns a boolean', () => {
  a.strictEqual(typeof canRefresh({ expiresAt: 1 }, 2), 'boolean');
});
