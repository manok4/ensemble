const test = require('node:test');
const assert = require('node:assert');
const { timeoutMs } = require('../src/config');

test('reads a timeout in seconds', () => {
  assert.strictEqual(timeoutMs({ timeout: '30s' }), 30000);
});
