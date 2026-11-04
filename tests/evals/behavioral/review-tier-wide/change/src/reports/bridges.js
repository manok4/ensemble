const { render } = require('../render');

const title = 'Bridges';
module.exports = (rows) => render(title, rows.slice(1));
