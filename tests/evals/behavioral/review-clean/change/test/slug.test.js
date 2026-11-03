const test = require('node:test');
const assert = require('node:assert');
const { slugify } = require('../src/slug');

test('lowercases and hyphenates words', () => {
  assert.strictEqual(slugify('Hello World'), 'hello-world');
});

test('drops accents and punctuation', () => {
  assert.strictEqual(slugify('Crème brûlée, again!'), 'creme-brulee-again');
});

test('trims separators at both ends', () => {
  assert.strictEqual(slugify('  --Ready?--  '), 'ready');
});

test('returns an empty slug for symbols only', () => {
  assert.strictEqual(slugify('!!!'), '');
});
