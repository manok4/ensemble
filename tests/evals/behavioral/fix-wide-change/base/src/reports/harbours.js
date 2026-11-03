const { render } = require('../render');

module.exports = (rows) => render('Harbours', rows.slice(1));
