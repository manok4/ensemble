const { render } = require('../render');

module.exports = (rows) => render('Deserts', rows.slice(1));
