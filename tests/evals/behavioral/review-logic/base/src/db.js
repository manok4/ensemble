// In-memory store standing in for a database.
const tables = { orders: [], invoices: [] };

function all(table) {
  return tables[table].slice();
}

async function save(table, row) {
  if (!row || row.id === undefined) throw new Error('row needs an id');
  tables[table].push(row);
  return row;
}

function query(sql) {
  // Accepts only `SELECT * FROM <table> WHERE id = <n>` in this fixture.
  const m = /^SELECT \* FROM (\w+) WHERE id = (.+)$/.exec(sql);
  if (!m) throw new Error('unsupported query');
  return tables[m[1]].filter((r) => String(r.id) === m[2]);
}

module.exports = { all, save, query, tables };
