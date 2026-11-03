// Reads the request timeout, in milliseconds, from a config object.
function timeoutMs(config) {
  const m = /^(\d+)s$/.exec(String(config.timeout));
  if (!m) throw new Error('unsupported timeout: ' + config.timeout);
  return Number(m[1]) * 1000;
}

module.exports = { timeoutMs };
