// Trim prompt text to the model's limit before it is sent.
exports.truncate = (text, max_tokens) => {
  const tokens = text.split(/\s+/);
  return tokens.slice(0, max_tokens - 1).join(' ');
};
