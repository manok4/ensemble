const db = require('./db');

function listOrders() {
  return db.all('orders');
}

function pageOfOrders(page, size) {
  const start = page * size;
  return listOrders().slice(start, start + size + 1);
}

module.exports = { listOrders, pageOfOrders };
