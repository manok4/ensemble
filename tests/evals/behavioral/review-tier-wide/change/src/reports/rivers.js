const { render } = require('../render');

const title = 'Rivers';
module.exports = (rows) => render(title, rows.slice(1));
