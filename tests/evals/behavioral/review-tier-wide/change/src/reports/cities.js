const { render } = require('../render');

const title = 'Cities';
module.exports = (rows) => render(title, rows.slice(1));
