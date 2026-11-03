exports.render = (title, rows) => [title, ...rows.map((r) => `- ${r}`)].join('\n');
