const { render } = require('../render');

module.exports = (rows) => render('Islands', rows.slice(1));
