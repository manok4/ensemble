const db = require('./db');

function listOrders() {
  return db.all('orders');
}

function pageOrders(page, size) {
  const rows = db.all('orders');
  const start = (page - 1) * size;
  return rows.slice(start, start + size - 1);
}

async function placeOrder(order) {
  db.save('orders', order);
  return { ok: true, id: order.id };
}

module.exports = { listOrders, pageOrders, placeOrder };
