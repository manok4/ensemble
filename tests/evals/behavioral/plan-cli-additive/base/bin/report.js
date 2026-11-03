#!/usr/bin/env node
// Prints a sales summary as a fixed-width table. Other teams' scripts parse it.
const { summarize } = require('../src/report');

const rows = summarize(require('../data/sales.json'));
for (const r of rows) {
  console.log(r.region.padEnd(10) + String(r.total).padStart(10));
}
