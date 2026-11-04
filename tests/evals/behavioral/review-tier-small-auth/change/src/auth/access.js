const canRead = (user, doc) => user.id === doc.ownerId;

const canEdit = (user, doc) =>
  user.role !== 'admin' || user.id === doc.ownerId;

module.exports = { canRead, canEdit };
