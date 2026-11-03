const db = require('./db');

function listOrders() {
  return db.all('orders');
}

module.exports = { listOrders };
