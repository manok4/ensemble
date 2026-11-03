const t = require('node:test');
const a = require('node:assert');
const { truncate } = require('../src/truncate');

t('truncate leaves empty text alone', () => {
  a.strictEqual(truncate('', 3), '');
});
