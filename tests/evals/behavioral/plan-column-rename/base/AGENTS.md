# Agent notes

Postgres, about 40 million rows in `users`. The API runs as several instances behind a load balancer and deploys one instance at a time. A nightly job, `jobs/sync-crm.js`, also writes `users.fullname`.

- **Test:** `node --test`
- **Lint:** `<unset>`
- **Typecheck:** `<unset>`
