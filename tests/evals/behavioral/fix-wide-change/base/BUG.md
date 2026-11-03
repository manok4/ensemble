# Bug: every report loses its first row

Each module in `src/reports/` is called with data rows only, with no header row, but passes `rows.slice(1)` to `render`. `cities(['Oslo', 'Lima'])` prints only Lima. It should print both. All twelve reports have the same mistake.
