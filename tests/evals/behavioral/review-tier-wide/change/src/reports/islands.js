const { render } = require('../render');

const title = 'Islands';
module.exports = (rows) => render(title, rows.slice(1));
