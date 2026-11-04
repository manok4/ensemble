const { render } = require('../render');

const title = 'Lakes';
module.exports = (rows) => render(title, rows.slice(1));
