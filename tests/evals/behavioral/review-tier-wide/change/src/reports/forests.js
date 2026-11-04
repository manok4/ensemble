const { render } = require('../render');

const title = 'Forests';
module.exports = (rows) => render(title, rows.slice(1));
