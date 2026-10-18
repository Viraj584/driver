import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'risk_engine.dart';

class RiskEventRecord {
  const RiskEventRecord({
    required this.id,
    required this.requestId,
    required this.riderId,
    required this.eventType,
    required this.score,
    required this.reasons,
    required this.status,
    required this.currentStatus,
    required this.receivedAt,
    required this.reviewRequired,
    required this.verificationRequired,
  });

  final String id;
  final String requestId;
  final String riderId;
  final String eventType;
  final double score;
  final List<String> reasons;
  final String status;
  final String currentStatus;
  final DateTime? receivedAt;
  final bool reviewRequired;
  final bool verificationRequired;
}

class RiskEventResult {
  const RiskEventResult({
    required this.requestId,
    required this.score,
    required this.reasons,
    required this.status,
    required this.verificationRequired,
    required this.reviewRequired,
  });

  final String requestId;
  final double score;
  final List<String> reasons;
  final RiderRiskStatus status;
  final bool verificationRequired;
  final bool reviewRequired;
}

class RiskAuditRecord {
  const RiskAuditRecord({
    required this.id,
    required this.actorUid,
    required this.riderId,
    required this.action,
    required this.reason,
    required this.previousStatus,
    required this.newStatus,
    required this.createdAt,
  });

  final String id;
  final String actorUid;
  final String riderId;
  final String action;
  final String reason;
  final String previousStatus;
  final String newStatus;
  final DateTime? createdAt;
}

abstract interface class RiskEventGateway {
  bool get isSignedIn;
  Future<bool> isAdministrator();
  Future<RiskEventResult> submitEvent({
    required String requestId,
    required RiskEventType event,
    required bool poorLocationAccuracy,
  });
  Future<List<RiskEventRecord>> getHistory({required bool fleet});
  Future<List<RiskAuditRecord>> getAuditHistory();
  Future<bool> submitDemoChallengeResult({
    required String requestId,
    required bool passed,
  });
  Future<String> adminReviewRider({
    required String riderId,
    required String requestId,
    required String action,
    required String reason,
  });
}

class FirebaseRiskEventGateway implements RiskEventGateway {
  FirebaseRiskEventGateway({
    required this.functions,
    FirebaseAuth? auth,
    this.callableInvoker,
  }) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFunctions functions;
  final FirebaseAuth _auth;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
  callableInvoker;

  @override
  bool get isSignedIn => _auth.currentUser != null;

  @override
  Future<bool> isAdministrator() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final token = await user.getIdTokenResult();
    return token.claims?['admin'] == true;
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final invoke = callableInvoker;
    if (invoke != null) return invoke(name, data);
    final result = await functions
        .httpsCallable(name)
        .call<Map<String, dynamic>>(data);
    return result.data;
  }

  @override
  Future<RiskEventResult> submitEvent({
    required String requestId,
    required RiskEventType event,
    required bool poorLocationAccuracy,
  }) async {
    final data = await _call('submitRiskEvent', {
      'requestId': requestId,
      'eventType': _eventName(event, poorLocationAccuracy),
      'source': 'SIMULATOR',
    });
    return RiskEventResult(
      requestId: data['requestId'] as String,
      score: (data['score'] as num).toDouble(),
      reasons: (data['reasons'] as List<dynamic>).cast<String>(),
      status: _status(data['status'] as String),
      verificationRequired: data['verificationRequired'] as bool,
      reviewRequired: data['reviewRequired'] as bool,
    );
  }

  @override
  Future<List<RiskEventRecord>> getHistory({required bool fleet}) async {
    final response = await _call(
      fleet ? 'getFleetRiskEventHistory' : 'getRiskEventHistory',
      const {},
    );
    final values = response['events'] as List<dynamic>? ?? const [];
    return values
        .map((value) {
          final data = Map<String, dynamic>.from(value as Map);
          final receivedAt = data['receivedAt'];
          return RiskEventRecord(
            id: data['id'] as String,
            requestId: data['requestId'] as String? ?? data['id'] as String,
            riderId: data['riderId'] as String? ?? _auth.currentUser?.uid ?? '',
            eventType: data['eventType'] as String,
            score: (data['riskScore'] as num).toDouble(),
            reasons: (data['riskReasons'] as List<dynamic>).cast<String>(),
            status: data['resultingStatus'] as String,
            currentStatus:
                data['currentStatus'] as String? ??
                data['resultingStatus'] as String,
            receivedAt: receivedAt is num
                ? DateTime.fromMillisecondsSinceEpoch(receivedAt.toInt())
                : null,
            reviewRequired: data['reviewRequired'] as bool? ?? false,
            verificationRequired:
                data['verificationRequired'] as bool? ?? false,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<List<RiskAuditRecord>> getAuditHistory() async {
    final response = await _call('getFleetAuditHistory', const {});
    final values = response['events'] as List<dynamic>? ?? const [];
    return values
        .map((value) {
          final data = Map<String, dynamic>.from(value as Map);
          final createdAt = data['createdAt'];
          return RiskAuditRecord(
            id: data['id'] as String,
            actorUid: data['actorUid'] as String? ?? '',
            riderId: data['riderId'] as String? ?? '',
            action: data['action'] as String? ?? '',
            reason: data['reason'] as String? ?? '',
            previousStatus: data['previousStatus'] as String? ?? '',
            newStatus: data['newStatus'] as String? ?? '',
            createdAt: createdAt is num
                ? DateTime.fromMillisecondsSinceEpoch(createdAt.toInt())
                : null,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<bool> submitDemoChallengeResult({
    required String requestId,
    required bool passed,
  }) async {
    final result = await _call('submitDemoChallengeResult', {
      'requestId': requestId,
      'passed': passed,
    });
    return result['recorded'] == true;
  }

  @override
  Future<String> adminReviewRider({
    required String riderId,
    required String requestId,
    required String action,
    required String reason,
  }) async {
    final result = await _call('adminReviewRider', {
      'riderId': riderId,
      'requestId': requestId,
      'action': action,
      'reason': reason,
    });
    return result['status'] as String;
  }

  String _eventName(RiskEventType event, bool poorAccuracy) => switch (event) {
    RiskEventType.normal => 'NORMAL_TELEMETRY',
    RiskEventType.deviceChange => 'DEVICE_CHANGE',
    RiskEventType.gpsJump =>
      poorAccuracy ? 'GPS_JUMP_POOR_ACCURACY' : 'GPS_JUMP',
    RiskEventType.unusualSpeed => 'UNUSUAL_SPEED',
    RiskEventType.possibleHandoff => 'POSSIBLE_HANDOFF',
  };

  RiderRiskStatus _status(String status) => switch (status) {
    'LIVENESS_PENDING' => RiderRiskStatus.verificationPending,
    'RESTRICTED' => RiderRiskStatus.restricted,
    _ => RiderRiskStatus.active,
  };
}
