const { render } = require('../render');

const title = 'Museums';
module.exports = (rows) => render(title, rows.slice(1));
