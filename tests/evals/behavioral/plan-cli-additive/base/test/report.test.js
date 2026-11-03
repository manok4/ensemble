const test = require('node:test');
const assert = require('node:assert');
const { summarize } = require('../src/report');

test('totals sales per region, sorted', () => {
  assert.deepStrictEqual(summarize([{ region: 'w', amount: 1 }, { region: 'e', amount: 2 }, { region: 'w', amount: 3 }]),
    [{ region: 'e', total: 2 }, { region: 'w', total: 4 }]);
});
