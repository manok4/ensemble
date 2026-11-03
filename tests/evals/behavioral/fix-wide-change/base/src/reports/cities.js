const { render } = require('../render');

module.exports = (rows) => render('Cities', rows.slice(1));
