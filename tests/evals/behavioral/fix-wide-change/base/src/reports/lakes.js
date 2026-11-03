const { render } = require('../render');

module.exports = (rows) => render('Lakes', rows.slice(1));
