import { createRequire } from 'module';
import fs from 'fs';
import path from 'path';
import { env } from '../config/env.js';

const nodeRequire = createRequire(path.resolve(process.cwd(), 'package.json'));
const { DatabaseSync } = nodeRequire('node:sqlite');

export type AppDatabase = any;

let dbInstance: AppDatabase | null = null;

export function getDatabase(customPath?: string): AppDatabase {
  if (dbInstance && !customPath) {
    return dbInstance;
  }

  const dbPath = customPath || (env.NODE_ENV === 'test' ? ':memory:' : env.DATABASE_PATH);
  
  if (dbPath !== ':memory:') {
    const dir = path.dirname(path.resolve(process.cwd(), dbPath));
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
  }

  const db = new DatabaseSync(dbPath) as AppDatabase;

  // Add transactional helper
  db.transaction = <T>(fn: (...args: any[]) => T) => {
    return (...args: any[]): T => {
      db.exec('BEGIN TRANSACTION');
      try {
        const result = fn(...args);
        db.exec('COMMIT');
        return result;
      } catch (error) {
        try {
          db.exec('ROLLBACK');
        } catch (_) {}
        throw error;
      }
    };
  };

  // Configure SQLite for high concurrency and relational integrity
  db.exec('PRAGMA foreign_keys = ON;');
  if (dbPath !== ':memory:') {
    db.exec('PRAGMA journal_mode = WAL;');
    db.exec('PRAGMA synchronous = NORMAL;');
  }

  // Find and execute schema
  const candidatePaths = [
    path.resolve(process.cwd(), 'src/db/schema.sql'),
    path.resolve(process.cwd(), 'dist/db/schema.sql'),
    path.resolve(process.cwd(), 'schema.sql'),
  ];

  let schemaSql = '';
  for (const p of candidatePaths) {
    if (fs.existsSync(p)) {
      schemaSql = fs.readFileSync(p, 'utf8');
      break;
    }
  }

  if (schemaSql) {
    db.exec(schemaSql);
  }

  // Seed initial deliveries if empty
  seedDeliveriesIfEmpty(db);

  if (!customPath) {
    dbInstance = db;
  }

  return db;
}

export function closeDatabase(): void {
  if (dbInstance) {
    dbInstance.close();
    dbInstance = null;
  }
}

function seedDeliveriesIfEmpty(db: AppDatabase): void {
  const count = db.prepare('SELECT COUNT(*) as count FROM deliveries').get() as { count: number } | undefined;
  if (!count || count.count === 0) {
    const now = Date.now();
    const insert = db.prepare(`
      INSERT INTO deliveries (id, title, pickup, dropoff, amount, distance, eta, service_type, recipient_label, status, notes, tags, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    const seedData = [
      [
        'TJ-DEMO-8492',
        'Express Cargo',
        'TechCorp Logistics Hub (Gate 3)',
        'Apex Towers, 8th Floor, Sector 4',
        380,
        '4.2 km',
        '18 min',
        'Express',
        'Sample recipient',
        'available',
        '12 kg · High priority dispatch',
        'High payout',
        now,
      ],
      [
        'TJ-DEMO-8493',
        'Cold-Chain Pharma',
        'Metro Cold Storage Unit B',
        'St. Jude Healthcare & Research',
        520,
        '7.8 km',
        '26 min',
        'Cold chain',
        'Sample recipient',
        'available',
        '2–8°C temperature regulated · Priority',
        'High payout Cold Chain',
        now + 1000,
      ],
      [
        'TJ-DEMO-8494',
        'Standard Parcel',
        'Greenfield Regional Depot (Bay 11)',
        'Phoenix Market City, Level 2',
        260,
        '3.1 km',
        '14 min',
        'Standard',
        'Sample recipient',
        'available',
        'Standard delivery parcel',
        'Nearby',
        now + 2000,
      ],
    ];

    const transaction = db.transaction((rows: any[][]) => {
      for (const row of rows) {
        insert.run(...row);
      }
    });

    transaction(seedData);
  }
}
