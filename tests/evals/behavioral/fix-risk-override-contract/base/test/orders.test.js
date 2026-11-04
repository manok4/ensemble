const t = require('node:test');
const a = require('node:assert');
const { orderJson } = require('../src/orders');

t('orderJson keeps the id', () => {
  a.strictEqual(orderJson({ id: 1, amount: 2 }).id, 1);
});
