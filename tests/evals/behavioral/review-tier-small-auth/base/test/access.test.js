const test = require('node:test');
const assert = require('node:assert');
const { canRead } = require('../src/auth/access');

test('an owner can read', () => {
  assert.ok(canRead({ id: 1 }, { ownerId: 1 }));
});
