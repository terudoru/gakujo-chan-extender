CREATE TABLE reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at INTEGER NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('bug', 'request')),
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  steps TEXT NOT NULL DEFAULT '',
  expected TEXT NOT NULL DEFAULT '',
  version TEXT NOT NULL DEFAULT '',
  platform TEXT NOT NULL DEFAULT '',
  diagnostic TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'issued', 'dismissed')),
  issue_number INTEGER
);
CREATE INDEX reports_status_created ON reports(status, id DESC);
CREATE INDEX reports_created ON reports(created_at);

-- No IP addresses, report text, or persistent link to a report in this table.
CREATE TABLE rate_events (
  id TEXT PRIMARY KEY,
  ip_hash TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX rate_events_hash_time ON rate_events(ip_hash, created_at);
CREATE INDEX rate_events_time ON rate_events(created_at);
