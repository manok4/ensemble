const db = require('./db');

// Receipts are owner-scoped: a user may read only their own.
function getReceipt(req, res) {
  const receipt = db.all('invoices').find((r) => r.id === Number(req.params.id));
  if (!receipt || receipt.ownerId !== req.user.id) return res.status(404).end();
  return res.json(receipt);
}

module.exports = { getReceipt };
