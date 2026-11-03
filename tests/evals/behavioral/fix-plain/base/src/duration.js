// Parses durations like "90s", "15m", "2h" or "1h30m" into seconds.
function parseDuration(text) {
  const m = /(\d+)([hms])$/.exec(text.trim());
  if (!m) throw new Error('bad duration: ' + text);
  const n = Number(m[1]);
  return m[2] === 'h' ? n * 3600 : m[2] === 'm' ? n * 60 : n;
}

module.exports = { parseDuration };
