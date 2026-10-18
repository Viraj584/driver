import crypto from 'crypto';
import { getDatabase } from '../../db/database.js';
import { AppError } from '../../middleware/errorHandler.js';
import { AuditService } from '../audit/audit.service.js';

export class DeliveriesService {
  static listDeliveries(riderId?: string): any[] {
    const db = getDatabase();
    const rows = db.prepare(`
      SELECT 
        d.id, d.title, d.pickup, d.dropoff, d.amount, d.distance, d.eta,
        d.service_type as serviceType, d.recipient_label as recipientLabel,
        d.status, d.notes, d.tags, d.created_at as createdAt,
        da.id as assignmentId, da.rider_id as assignedRiderId, da.status as assignmentStatus
      FROM deliveries d
      LEFT JOIN delivery_assignments da ON d.id = da.delivery_id AND da.status IN ('assigned', 'in_progress')
      ORDER BY d.created_at ASC
    `).all() as any[];

    return rows.map(r => ({
      id: r.id,
      title: r.title,
      pickup: r.pickup,
      dropoff: r.dropoff,
      amount: r.amount,
      amountLabel: `₹${r.amount}`,
      distance: r.distance,
      eta: r.eta,
      serviceType: r.serviceType,
      recipientLabel: r.recipientLabel,
      status: r.status,
      notes: r.notes || '',
      tags: r.tags || '',
      isAssignedToCurrentRider: Boolean(riderId && r.assignedRiderId === riderId),
    }));
  }

  static acceptDelivery(riderId: string, deliveryId: string): any {
    const db = getDatabase();

    // 1. Check user and rider profile
    const user = db.prepare('SELECT role, account_status FROM users WHERE id = ?').get(riderId) as any;
    if (!user || user.role !== 'driver') {
      throw new AppError('Only active drivers can accept deliveries', 403, 'FORBIDDEN');
    }

    if (user.account_status !== 'active') {
      throw new AppError(`Rider account is ${user.account_status}. Cannot accept orders.`, 403, 'ACCOUNT_INACTIVE');
    }

    const profile = db.prepare('SELECT risk_status, review_required FROM rider_profiles WHERE user_id = ?').get(riderId) as any;
    const riskStatus = profile?.risk_status || 'ACTIVE';

    if (riskStatus === 'LIVENESS_PENDING') {
      throw new AppError(
        'Liveness step-up verification is pending on your account. Complete verification before accepting orders.',
        403,
        'VERIFICATION_PENDING'
      );
    }

    if (riskStatus === 'RESTRICTED') {
      throw new AppError(
        'Rider account is restricted by risk engine policy. Delivery acceptance is prohibited.',
        403,
        'ACCOUNT_RESTRICTED'
      );
    }

    // 2. Transactional check and assignment
    const now = Date.now();
    const assignmentId = `asgn_${crypto.randomUUID()}`;

    const updateDelivery = db.prepare(`
      UPDATE deliveries SET status = 'assigned' WHERE id = ? AND status = 'available'
    `);

    const insertAssignment = db.prepare(`
      INSERT INTO delivery_assignments (id, delivery_id, rider_id, status, assigned_at)
      VALUES (?, ?, ?, 'assigned', ?)
    `);

    let updated = false;

    const tx = db.transaction(() => {
      const delivery = db.prepare('SELECT id, status FROM deliveries WHERE id = ?').get(deliveryId) as any;
      if (!delivery) {
        throw new AppError('Delivery not found', 404, 'NOT_FOUND');
      }

      if (delivery.status !== 'available') {
        throw new AppError('Delivery is no longer available for acceptance', 409, 'DELIVERY_UNAVAILABLE');
      }

      const res = updateDelivery.run(deliveryId);
      if (res.changes === 0) {
        throw new AppError('Delivery was already claimed by another driver', 409, 'DELIVERY_CLAIMED');
      }

      insertAssignment.run(assignmentId, deliveryId, riderId, now);
      updated = true;
    });

    tx();

    AuditService.record({
      actorUid: riderId,
      actorRole: 'driver',
      riderId,
      action: 'DELIVERY_ACCEPTED',
      reason: `Accepted delivery order ${deliveryId}`,
      newStatus: 'assigned',
      requestId: deliveryId,
    });

    return {
      assignmentId,
      deliveryId,
      status: 'assigned',
      assignedAt: now,
    };
  }

  static completeDelivery(riderId: string, deliveryId: string): any {
    const db = getDatabase();

    const assignment = db.prepare(`
      SELECT * FROM delivery_assignments WHERE delivery_id = ? AND rider_id = ? AND status IN ('assigned', 'in_progress')
    `).get(deliveryId, riderId) as any;

    if (!assignment) {
      throw new AppError('Active assignment not found for this delivery and rider', 404, 'NOT_FOUND');
    }

    const now = Date.now();

    const tx = db.transaction(() => {
      db.prepare("UPDATE deliveries SET status = 'completed' WHERE id = ?").run(deliveryId);
      db.prepare("UPDATE delivery_assignments SET status = 'completed', completed_at = ? WHERE id = ?").run(now, assignment.id);
    });

    tx();

    AuditService.record({
      actorUid: riderId,
      actorRole: 'driver',
      riderId,
      action: 'DELIVERY_COMPLETED',
      reason: `Completed delivery order ${deliveryId}`,
      newStatus: 'completed',
      requestId: deliveryId,
    });

    return {
      completed: true,
      deliveryId,
      completedAt: now,
    };
  }
}
