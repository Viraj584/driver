import crypto from 'crypto';
import { getDatabase, AppDatabase } from '../../db/database.js';

export interface AuditLogEntry {
  actorUid: string;
  actorRole: string;
  riderId?: string | null;
  sessionId?: string | null;
  action: string;
  reason: string;
  previousStatus?: string | null;
  newStatus?: string | null;
  riskScore?: number | null;
  requestId?: string | null;
}

export class AuditService {
  static record(entry: AuditLogEntry, dbInstance?: AppDatabase): void {
    const db = dbInstance || getDatabase();
    const id = `audit_${crypto.randomUUID()}`;
    const now = Date.now();

    const insert = db.prepare(`
      INSERT INTO audit_logs (
        id, actor_uid, actor_role, rider_id, session_id,
        action, reason, previous_status, new_status,
        risk_score, request_id, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    insert.run(
      id,
      entry.actorUid,
      entry.actorRole,
      entry.riderId || null,
      entry.sessionId || null,
      entry.action,
      entry.reason,
      entry.previousStatus || null,
      entry.newStatus || null,
      entry.riskScore !== undefined && entry.riskScore !== null ? entry.riskScore : null,
      entry.requestId || null,
      now
    );
  }

  static getHistory(limit = 50): any[] {
    const db = getDatabase();
    const rows = db.prepare(`
      SELECT 
        id, actor_uid as actorUid, actor_role as actorRole,
        rider_id as riderId, session_id as sessionId,
        action, reason, previous_status as previousStatus,
        new_status as newStatus, risk_score as riskScore,
        request_id as requestId, created_at as createdAt
      FROM audit_logs
      ORDER BY created_at DESC
      LIMIT ?
    `).all(limit) as any[];

    return rows;
  }
}
