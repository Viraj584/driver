# Trust Juggler Backend Service

Self-contained local Node.js + TypeScript + Express + SQLite backend for the Trust Juggler mobile delivery and biometric risk assessment platform.

---

## 1. Prerequisites

- **Node.js**: `>= 18.0.0` (`v20.x` or `v22.x` recommended)
- **npm**: `>= 9.0.0`
- **Flutter SDK**: `>= 3.24.0` (for mobile client)

---

## 2. Quick Start

```bash
# Install dependencies
npm install

# Setup environment variables
cp .env.example .env

# Build TypeScript
npm run build

# Seed an administrator account
npm run bootstrap-admin -- admin@trustjuggler.internal SuperAdminPass123!

# Start development server with hot-reload
npm run dev
```

The server listens on **`http://localhost:3000`** by default.

---

## 3. Environment Variables (`.env`)

| Variable | Default | Description |
| :--- | :--- | :--- |
| `PORT` | `3000` | HTTP listen port |
| `NODE_ENV` | `development` | App environment (`development` \| `production` \| `test`) |
| `DATABASE_PATH` | `./trust_juggler.db` | Path to SQLite database file |
| `JWT_SECRET` | `...` | HMAC-SHA256 secret key for signing access tokens (min 32 chars) |
| `JWT_EXPIRES_IN` | `15m` | Access token expiration duration |
| `REFRESH_TOKEN_EXPIRES_DAYS` | `7` | Rotating refresh session lifetime in days |
| `ADMIN_BOOTSTRAP_SECRET` | `...` | Secret token to authorize admin bootstrapping |
| `CORS_ORIGIN` | `*` | Allowed CORS origins |

---

## 4. Available Scripts

- **`npm run dev`**: Starts server using `tsx watch` for hot reloading.
- **`npm run build`**: Compiles TypeScript (`tsc`) and copies SQL schema to `dist/`.
- **`npm start`**: Runs compiled production server (`node dist/server.js`).
- **`npm test`**: Runs the 29-test Vitest test suite.
- **`npm run bootstrap-admin -- <email> <password>`**: Initializes or updates an administrator account.

---

## 5. API Overview

- **Health Check**: `GET /api/health`
- **Auth**:
  - `POST /api/auth/register` — Driver account registration
  - `POST /api/auth/login` — Email/password login with JWT & rotating refresh tokens
  - `POST /api/auth/refresh` — Refresh token rotation
  - `POST /api/auth/logout` — Session revocation
  - `GET /api/auth/me` — Current user profile & claims
  - `POST /api/auth/phone-code` & `/verify-phone-code` — Dev-simulated OTP verification
- **Riders**:
  - `GET /api/riders/me` & `POST /api/riders/ensure` — Driver KYC & risk profile
  - `POST /api/riders/devices` — Device enrollment
- **Risk Engine**:
  - `POST /api/risk/events` — Idempotent telemetry evaluation
  - `GET /api/risk/events` — Rider event history
  - `POST /api/challenges/:id/resolve` — Step-up challenge resolution
- **Deliveries**:
  - `GET /api/deliveries` — Available delivery pool
  - `POST /api/deliveries/:id/accept` — Transactional order acceptance (gated on `ACTIVE` risk status)
- **Fleet Admin**:
  - `GET /api/admin/riders` — Fleet driver overview
  - `GET /api/admin/risk-events` — Live fleet telemetry stream
  - `GET /api/admin/audit-logs` — Immutable audit log
  - `POST /api/admin/riders/:id/review` — Review driver risk status

---

## 6. Testing

```bash
# Run backend test suite
npm test
```

All 29 tests validate authentication, token security, rate limiting, idempotent telemetry, risk scoring transitions, challenges, delivery transactional locking, and admin controls.
