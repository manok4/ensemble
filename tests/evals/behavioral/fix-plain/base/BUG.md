# Bug: combined durations lose their larger units

`parseDuration('1h30m')` returns `1800`. It should return `5400`. `parseDuration('2h5m10s')` returns `10`; it should return `7510`. Single units are fine.
