// Totals are in integer cents.
function total(items) {
  return items.reduce((sum, it) => sum + it.cents * it.qty, 0);
}

function discount(cents, percent) {
  return Math.round((cents * (100 - percent)) / 100);
}

module.exports = { total, discount };
