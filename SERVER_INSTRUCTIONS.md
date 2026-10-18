# Trust Juggler Backend: Installation & Server Guide

This guide provides end-to-end instructions for installing dependencies, configuring environment variables, running database migrations and seeds, starting the local Node.js/TypeScript backend server, and connecting the Flutter client.

---

## 1. Prerequisites

Ensure your development environment meets the following minimum requirements:

| Tool / Runtime | Minimum Version | Recommended | Notes |
| :--- | :--- | :--- | :--- |
| **Node.js** | `>= 18.0.0` | `v20.x` or `v22.x` | Native `node:sqlite` or SQLite3 driver included. |
| **npm** | `>= 9.0.0` | `10.x+` | Shipped with Node.js. |
| **Flutter SDK** | `>= 3.24.0` | Current stable | For compiling & running the rider app. |
| **curl** / **Postman** | Any | Latest | For inspecting HTTP/JSON endpoints. |

---

## 2. Quick Start (TL;DR)

```bash
# 1. Navigate to the backend directory
cd backend

# 2. Install dependencies
npm install

# 3. Create your local .env from the template
cp .env.example .env

# 4. Compile TypeScript
npm run build

# 5. Bootstrap an initial administrator account
npm run bootstrap-admin -- admin@trustjuggler.internal SuperAdminPass123!

# 6. Start the development server (with live reload)
npm run dev
```

The server will initialize on **`http://localhost:3000`** (or your configured `PORT`).

---

## 3. Environment Configuration (`.env`)

A default template is available at `backend/.env.example`. Create your local environment file:

```bash
cp backend/.env.example backend/.env
```

### Configuration Parameters

```env
# Server listen port
PORT=3000

# Runtime environment ('development' | 'production' | 'test')
NODE_ENV=development

# Relative or absolute path to SQLite database file
DATABASE_PATH=./trust_juggler.db

# JWT secret key for signing short-lived access tokens (minimum 32 characters)
JWT_SECRET=trust-juggler-dev-jwt-super-secret-key-32-chars-minimum

# Access token lifespan (e.g. '15m', '1h')
JWT_EXPIRES_IN=15m

# Rotating refresh session lifespan in days
REFRESH_TOKEN_EXPIRES_DAYS=7

# Secret token required to trigger admin bootstrapping
ADMIN_BOOTSTRAP_SECRET=trust-juggler-admin-bootstrap-secret-change-in-prod

# Allowed CORS origins ('*' for development or specific origin)
CORS_ORIGIN=*
```

> **Security Note:** The SQLite database file (`trust_juggler.db`) and `.env` contain local credentials and sessions and are automatically ignored in `.gitignore`. Never commit them to version control.

---

## 4. Database Setup & Seeding

Trust Juggler uses SQLite with **Write-Ahead Logging (WAL mode)**, enforced **Foreign Keys**, and **ACID transactions**.

### Automatic Migration
The database engine automatically loads and executes `src/db/schema.sql` on server startup. There is no need to run manual SQL scripts.

Tables created:
1. `users` — Authentication accounts (passwords hashed with `bcrypt`).
2. `rider_profiles` — Driver profile state, risk status (`ACTIVE`, `LIVENESS_PENDING`, `RESTRICTED`), KYC details.
3. `devices` — Device fingerprinting and approval state (`PENDING`, `APPROVED`, `REVOKED`).
4. `refresh_sessions` — SHA-256 hashed rotating refresh sessions.
5. `risk_events` — Idempotent telemetry events, scores, and policy evaluation history.
6. `verification_challenges` — Step-up challenges generated on policy triggers.
7. `deliveries` — Available delivery pool orders with payout, distance, and priority.
8. `delivery_assignments` — Atomic rider assignments gated on `ACTIVE` risk status.
9. `audit_logs` — Tamper-evident admin & system actions.

### Auto-Seeded Delivery Pool
On initial database boot, the system automatically inserts sample delivery orders (`TJ-DEMO-8492`, `TJ-DEMO-8493`, `TJ-DEMO-8494`) if the `deliveries` table is empty.

### Admin Account Bootstrapping
Run the bootstrap script to create or update an administrator account:

```bash
# Syntax: npm run bootstrap-admin -- <email> <password>
npm run bootstrap-admin -- admin@trustjuggler.internal SuperAdminPass123!
```

Output:
```text
[Admin Bootstrap] Initializing admin account: admin@trustjuggler.internal
[Admin Bootstrap] Success: {
  id: 'admin_...',
  email: 'admin@trustjuggler.internal',
  role: 'admin',
  message: 'Admin account created successfully'
}
```

---

## 5. Starting the Server

### Development Mode (Recommended)
Runs with `tsx` watch mode for automatic restart on source file edits:

```bash
cd backend
npm run dev
```

### Production / Compiled Mode
Compiles TypeScript into `dist/` and runs with standard Node.js:

```bash
cd backend
npm run build
npm start
```

Console Output:
```text
==================================================
  TRUST JUGGLER BACKEND SERVER
==================================================
  Environment : development
  Port        : 3000
  Database    : ./trust_juggler.db
  Health check: http://localhost:3000/api/health
==================================================
```

---

## 6. Verifying Server Health

Confirm the backend is operational using `curl`:

```bash
curl http://localhost:3000/api/health
```

Expected Response:
```json
{
  "success": true,
  "data": {
    "status": "UP",
    "timestamp": "2026-10-18T11:00:00.000Z",
    "version": "1.0.0",
    "environment": "development"
  }
}
```

### Quick Auth Check
Register a test driver account:
```bash
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"driver@test.com","password":"Password123!","role":"driver"}'
```

Log in:
```bash
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"driver@test.com","password":"Password123!"}'
```

---

## 7. Connecting the Flutter Client

The Flutter application automatically resolves the appropriate backend endpoint based on the target platform:

### A. Android Emulator
The Android emulator maps the host machine's `localhost` to **`http://10.0.2.2:3000`**. The Flutter app automatically routes to this address when running on an emulator:

```bash
# Launch Android emulator
flutter run -d emulator-5554
```

### B. Linux Desktop / macOS Desktop
Desktop builds automatically target **`http://127.0.0.1:3000`**:

```bash
flutter run -d linux
```

### C. Physical Mobile Device (Over Local Wi-Fi / LAN)
When debugging on a physical phone connected over Wi-Fi, provide your host machine's LAN IP address using `--dart-define`:

```bash
# Find your host IP (e.g., 192.168.1.150)
ip route get 1.1.1.1 | awk '{print $7}'

# Run Flutter app pointing to the host machine
flutter run --dart-define=TRUST_JUGGLER_API_BASE_URL=http://192.168.1.150:3000
```

> **Note on Cleartext Traffic:** Cleartext HTTP network traffic is pre-configured and enabled for Android debug builds in `android/app/src/debug/AndroidManifest.xml` (`android:usesCleartextTraffic="true"`).

---

## 8. Running Automated Test Suites

### Backend Unit & Integration Tests (Vitest)
Executes 29 comprehensive test cases covering authentication, token rotation, rate limiting, risk policy evaluation, idempotent telemetry, challenges, and admin reviews:

```bash
cd backend
npm test
```

### Flutter Unit & Widget Tests
Executes 106 tests across the application, including UI layout rectification, biometric verification, and backend gateway integration:

```bash
# From workspace root
flutter test
```

### Flutter Code Analyzer
Verifies code quality and ensures zero static analysis warnings or errors:

```bash
flutter analyze
```

---

## 9. Troubleshooting & FAQ

#### Q: Port 3000 is already in use (`EADDRINUSE`)
- **Fix:** Update `PORT=3001` in `backend/.env`, and run the Flutter app specifying the new port:
  ```bash
  flutter run --dart-define=TRUST_JUGGLER_API_BASE_URL=http://10.0.2.2:3001
  ```
  Or identify and terminate the process using port 3000:
  ```bash
  fuser -k 3000/tcp
  ```

#### Q: Android emulator displays "Network error. Check your connection and retry"
- Ensure the backend server is running (`npm run dev`).
- Verify `http://10.0.2.2:3000/api/health` is reachable from the emulator browser.
- Verify `android/app/src/debug/AndroidManifest.xml` contains `android:usesCleartextTraffic="true"`.

#### Q: Admin access verification fails on login
- Ensure you bootstrapped the admin account with the exact same credentials:
  ```bash
  npm run bootstrap-admin -- admin@trustjuggler.internal SuperAdminPass123!
  ```
- Log in with that email and password through the Fleet Command portal.
