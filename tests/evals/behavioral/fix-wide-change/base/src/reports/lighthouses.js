const { render } = require('../render');

module.exports = (rows) => render('Lighthouses', rows.slice(1));
