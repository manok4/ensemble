const { render } = require('../render');

module.exports = (rows) => render('Bridges', rows.slice(1));
