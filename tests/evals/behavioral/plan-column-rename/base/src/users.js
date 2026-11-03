// Reads and writes user profiles. db.query(sql, params) runs against Postgres.
const db = require('./db');

async function getUser(id) {
  const [row] = await db.query('SELECT id, email, fullname FROM users WHERE id = $1', [id]);
  return row && { id: row.id, email: row.email, name: row.fullname };
}

async function renameUser(id, name) {
  await db.query('UPDATE users SET fullname = $1, updated_at = now() WHERE id = $2', [name, id]);
}

module.exports = { getUser, renameUser };
