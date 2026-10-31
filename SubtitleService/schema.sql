CREATE TABLE IF NOT EXISTS captions (
  id TEXT PRIMARY KEY,
  text TEXT NOT NULL,
  expires INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS captions_expires ON captions(expires);
