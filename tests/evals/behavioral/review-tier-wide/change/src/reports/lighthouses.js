const { render } = require('../render');

const title = 'Lighthouses';
module.exports = (rows) => render(title, rows.slice(1));
