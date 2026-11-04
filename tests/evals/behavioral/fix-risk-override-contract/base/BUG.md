# Bug: the order response uses the wrong field name

`orderJson` returns `total` where the published API promises `total_cents`. Customers who read the old name will need to change.
