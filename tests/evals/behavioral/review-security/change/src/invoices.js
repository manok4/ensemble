const db = require('./db');

// Invoices are owner-scoped, like receipts.
function getInvoice(req, res) {
  const invoice = db.query('SELECT * FROM invoices WHERE id = ' + req.params.id)[0];
  if (!invoice) return res.status(404).end();
  return res.json(invoice);
}

module.exports = { getInvoice };
