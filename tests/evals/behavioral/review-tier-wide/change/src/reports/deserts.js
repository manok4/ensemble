const { render } = require('../render');

const title = 'Deserts';
module.exports = (rows) => render(title, rows.slice(1));
