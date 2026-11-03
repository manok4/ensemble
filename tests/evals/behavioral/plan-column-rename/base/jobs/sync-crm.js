// Nightly: copies names from the CRM into users.fullname.
const db = require('../src/db');

async function run(crmRows) {
  for (const r of crmRows) {
    await db.query('UPDATE users SET fullname = $1, updated_at = now() WHERE email = $2', [r.name, r.email]);
  }
}

module.exports = { run };
