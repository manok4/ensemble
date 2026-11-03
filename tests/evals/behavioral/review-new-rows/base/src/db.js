// Stand-in for a SQL client: records the statements it is given.
const statements = [];
function exec(sql, params = []) {
  statements.push({ sql, params });
  return [];
}
module.exports = { exec, statements };
