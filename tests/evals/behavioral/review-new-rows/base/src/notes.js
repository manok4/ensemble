const db = require('./db');

function saveNote(userId, text) {
  return db.exec('INSERT INTO notes (user_id, body) VALUES (?, ?)', [userId, text]);
}

module.exports = { saveNote };
