const { render } = require('../render');

module.exports = (rows) => render('Museums', rows.slice(1));
