-- Trust Juggler SQLite Schema
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT UNIQUE,
  phone TEXT UNIQUE,
  password_hash TEXT,
  role TEXT NOT NULL CHECK (role IN ('driver', 'admin')),
  account_status TEXT NOT NULL DEFAULT 'active' CHECK (account_status IN ('active', 'restricted', 'suspended')),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);

CREATE TABLE IF NOT EXISTS rider_profiles (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  registration_status TEXT NOT NULL DEFAULT 'registration_pending' CHECK (registration_status IN ('registration_pending', 'identity_pending', 'approved', 'rejected', 'suspended')),
  identity_verification_status TEXT NOT NULL DEFAULT 'identity_pending' CHECK (identity_verification_status IN ('identity_pending', 'verified', 'rejected')),
  device_enrollment_status TEXT NOT NULL DEFAULT 'none' CHECK (device_enrollment_status IN ('none', 'pending_review', 'enrolled')),
  risk_status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (risk_status IN ('ACTIVE', 'LIVENESS_PENDING', 'RESTRICTED')),
  risk_score REAL NOT NULL DEFAULT 0.0,
  risk_reasons TEXT NOT NULL DEFAULT '[]',
  review_required INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  rider_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform TEXT NOT NULL CHECK (platform IN ('android', 'ios')),
  status TEXT NOT NULL DEFAULT 'pending_review' CHECK (status IN ('pending_review', 'active', 'revoked', 'rejected')),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_devices_rider ON devices(rider_id);

CREATE TABLE IF NOT EXISTS refresh_sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT UNIQUE NOT NULL,
  expires_at INTEGER NOT NULL,
  revoked_at INTEGER,
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_refresh_token_hash ON refresh_sessions(token_hash);
CREATE INDEX IF NOT EXISTS idx_refresh_user ON refresh_sessions(user_id);

CREATE TABLE IF NOT EXISTS risk_events (
  id TEXT PRIMARY KEY,
  request_id TEXT NOT NULL,
  rider_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  source TEXT NOT NULL CHECK (source IN ('SIMULATOR', 'APP')),
  risk_score REAL NOT NULL,
  risk_reasons TEXT NOT NULL,
  resulting_status TEXT NOT NULL,
  verification_required INTEGER NOT NULL,
  review_required INTEGER NOT NULL,
  evaluation_version TEXT NOT NULL DEFAULT 'demo-v1',
  received_at INTEGER NOT NULL,
  UNIQUE(rider_id, request_id)
);

CREATE INDEX IF NOT EXISTS idx_risk_events_rider ON risk_events(rider_id, received_at DESC);

CREATE TABLE IF NOT EXISTS verification_challenges (
  id TEXT PRIMARY KEY,
  request_id TEXT NOT NULL,
  rider_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  challenge_type TEXT NOT NULL DEFAULT 'DEMO_STEP_UP',
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'DEMO_PASSED', 'DEMO_FAILED', 'EXPIRED')),
  result_source TEXT,
  review_required INTEGER NOT NULL DEFAULT 1,
  expires_at INTEGER NOT NULL,
  completed_at INTEGER,
  created_at INTEGER NOT NULL,
  UNIQUE(rider_id, request_id)
);

CREATE INDEX IF NOT EXISTS idx_challenges_rider ON verification_challenges(rider_id, status);

CREATE TABLE IF NOT EXISTS deliveries (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  pickup TEXT NOT NULL,
  dropoff TEXT NOT NULL,
  amount INTEGER NOT NULL,
  distance TEXT NOT NULL,
  eta TEXT NOT NULL,
  service_type TEXT NOT NULL,
  recipient_label TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'assigned', 'in_progress', 'completed', 'cancelled')),
  notes TEXT,
  tags TEXT,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS delivery_assignments (
  id TEXT PRIMARY KEY,
  delivery_id TEXT NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
  rider_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'assigned' CHECK (status IN ('assigned', 'in_progress', 'completed', 'cancelled')),
  assigned_at INTEGER NOT NULL,
  completed_at INTEGER
);

CREATE INDEX IF NOT EXISTS idx_assignments_delivery ON delivery_assignments(delivery_id);
CREATE INDEX IF NOT EXISTS idx_assignments_rider ON delivery_assignments(rider_id);

CREATE TABLE IF NOT EXISTS audit_logs (
  id TEXT PRIMARY KEY,
  actor_uid TEXT NOT NULL,
  actor_role TEXT NOT NULL,
  rider_id TEXT,
  session_id TEXT,
  action TEXT NOT NULL,
  reason TEXT NOT NULL,
  previous_status TEXT,
  new_status TEXT,
  risk_score REAL,
  request_id TEXT,
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_rider ON audit_logs(rider_id);
