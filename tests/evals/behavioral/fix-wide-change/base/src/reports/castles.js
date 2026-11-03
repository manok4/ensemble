const { render } = require('../render');

module.exports = (rows) => render('Castles', rows.slice(1));
