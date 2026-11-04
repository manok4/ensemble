const { render } = require('../render');

const title = 'Castles';
module.exports = (rows) => render(title, rows.slice(1));
