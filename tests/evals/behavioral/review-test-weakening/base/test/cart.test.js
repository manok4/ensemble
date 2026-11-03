const test = require('node:test');
const assert = require('node:assert');
const { total, discount } = require('../src/cart');

test('totals quantities', () => {
  assert.strictEqual(total([{ cents: 250, qty: 2 }]), 500);
  assert.strictEqual(total([]), 0);
});

test('rounds a discount to the nearest cent', () => {
  assert.strictEqual(discount(999, 15), 849);
});
