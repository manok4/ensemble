const { render } = require('../render');

const title = 'Harbours';
module.exports = (rows) => render(title, rows.slice(1));
