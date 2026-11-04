const canRead = (user, doc) => user.id === doc.ownerId;

module.exports = { canRead };
