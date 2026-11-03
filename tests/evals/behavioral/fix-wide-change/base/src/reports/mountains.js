const { render } = require('../render');

module.exports = (rows) => render('Mountains', rows.slice(1));
