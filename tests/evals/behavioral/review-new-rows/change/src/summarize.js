const Anthropic = require('@anthropic-ai/sdk');
const db = require('./db');

const client = new Anthropic();

// Store a one-line summary of a note, written by the model.
async function summarizeNote(noteId, body) {
  const msg = await client.messages.create({
    model: 'claude-haiku-5-5',
    max_tokens: 100,
    messages: [{ role: 'user', content: 'Summarize in one line: ' + body }],
  });
  const summary = msg.content[0].text;
  return db.exec("UPDATE notes SET summary = '" + summary + "' WHERE id = " + noteId);
}

module.exports = { summarizeNote };
