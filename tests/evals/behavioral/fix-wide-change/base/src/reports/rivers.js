const { render } = require('../render');

module.exports = (rows) => render('Rivers', rows.slice(1));
