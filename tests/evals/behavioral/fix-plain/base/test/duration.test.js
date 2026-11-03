const test = require('node:test');
const assert = require('node:assert');
const { parseDuration } = require('../src/duration');

test('parses a single unit', () => {
  assert.strictEqual(parseDuration('90s'), 90);
  assert.strictEqual(parseDuration('15m'), 900);
  assert.strictEqual(parseDuration('2h'), 7200);
});

test('rejects text that is not a duration', () => {
  assert.throws(() => parseDuration('soon'));
});
