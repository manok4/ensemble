const test = require('node:test');
const assert = require('node:assert');
const { listOrders } = require('../src/orders');

test('lists no orders on an empty store', () => {
  assert.deepStrictEqual(listOrders(), []);
});
