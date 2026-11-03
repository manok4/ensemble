const { render } = require('../render');

module.exports = (rows) => render('Forests', rows.slice(1));
