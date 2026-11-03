const fs = require('node:fs');
const path = require('node:path');

const UPLOAD_ROOT = '/var/app/uploads';

// Remove a user's uploaded folder when they delete it in the UI.
function deleteUpload(req, res) {
  fs.rmSync(path.join(UPLOAD_ROOT, req.body.name), { recursive: true, force: true });
  res.status(204).end();
}

module.exports = { deleteUpload };
