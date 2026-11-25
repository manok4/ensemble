function summarize(sales) {
  const totals = {};
  for (const s of sales) totals[s.region] = (totals[s.region] || 0) + s.amount;
  return Object.keys(totals).sort().map((region) => ({ region, total: totals[region] }));
}

function formatDate(d) {
  return d.toISOString().slice(0, 10);
}

function startOfMonth(d) {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1));
}

module.exports = { summarize, formatDate, startOfMonth };
