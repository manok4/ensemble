const bullet = (r) => `- ${r}`;

const unique = (rows) => {
  const seen = new Set();
  return rows.filter((r) => {
    if (seen.has(r)) return false;
    seen.add(r);
    return true;
  });
};

exports.render = (title, rows) => [title, ...unique(rows).map(bullet)].join('\n');
