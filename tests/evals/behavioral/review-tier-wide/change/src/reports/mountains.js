const { render } = require('../render');

const title = 'Mountains';
module.exports = (rows) => render(title, rows.slice(1));
