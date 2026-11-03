// Stand-in for the payments provider and our ledger table.
const charges = [];
async function charge(customerId, cents) {
  const id = 'ch_' + (charges.length + 1);
  charges.push({ id, customerId, cents });
  return { id };
}
module.exports = { charge, charges };
