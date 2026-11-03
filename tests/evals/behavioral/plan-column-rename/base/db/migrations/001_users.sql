CREATE TABLE users (
  id bigserial PRIMARY KEY,
  email text NOT NULL UNIQUE,
  fullname text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
