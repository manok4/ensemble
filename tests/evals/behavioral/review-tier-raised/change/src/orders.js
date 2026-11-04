const db = require('./db');

function listOrders() {
  return db.all('orders');
}

function openOrders() {
  return db.table('orders').where({ open: true }).findMany();
}

module.exports = { listOrders, openOrders };
