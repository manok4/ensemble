const t = require('node:test');
const a = require('node:assert');
const { render } = require('../src/render');

t('render lists every row it is given', () => {
  a.strictEqual(render('T', ['x', 'y']), 'T\n- x\n- y');
});
