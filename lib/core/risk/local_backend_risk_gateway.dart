import '../network/api_client.dart';
import 'risk_engine.dart';
import 'risk_gateway.dart';

class LocalBackendRiskGateway implements RiskEventGateway {
  LocalBackendRiskGateway({
    required this.apiClient,
    this.adminCheck,
  });

  final ApiClient apiClient;
  final bool Function()? adminCheck;

  @override
  bool get isSignedIn => apiClient.accessToken != null;

  @override
  Future<bool> isAdministrator() async {
    final check = adminCheck;
    if (check != null) {
      return check();
    }
    try {
      final res = await apiClient.get('/api/auth/me');
      final data = res['data'] as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>;
      return user['role'] == 'admin';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<RiskEventResult> submitEvent({
    required String requestId,
    required RiskEventType event,
    required bool poorLocationAccuracy,
  }) async {
    final eventName = _eventName(event, poorLocationAccuracy);
    final response = await apiClient.post(
      '/api/risk/events',
      body: {
        'requestId': requestId,
        'eventType': eventName,
        'source': 'SIMULATOR',
      },
    );

    final data = response['data'] as Map<String, dynamic>;
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
    final path = fleet ? '/api/admin/risk-events' : '/api/risk/events';
    final response = await apiClient.get(path);
    final data = response['data'] as Map<String, dynamic>;
    final events = data['events'] as List<dynamic>? ?? const [];

    return events.map((v) {
      final item = Map<String, dynamic>.from(v as Map);
      final receivedAt = item['receivedAt'];
      return RiskEventRecord(
        id: item['id'] as String,
        requestId: item['requestId'] as String? ?? item['id'] as String,
        riderId: item['riderId'] as String? ?? '',
        eventType: item['eventType'] as String,
        score: (item['riskScore'] as num).toDouble(),
        reasons: (item['riskReasons'] as List<dynamic>).cast<String>(),
        status: item['resultingStatus'] as String,
        currentStatus:
            item['currentStatus'] as String? ??
            item['resultingStatus'] as String,
        receivedAt: receivedAt is num
            ? DateTime.fromMillisecondsSinceEpoch(receivedAt.toInt())
            : null,
        reviewRequired: item['reviewRequired'] as bool? ?? false,
        verificationRequired: item['verificationRequired'] as bool? ?? false,
      );
    }).toList(growable: false);
  }

  @override
  Future<List<RiskAuditRecord>> getAuditHistory() async {
    final response = await apiClient.get('/api/admin/audit-logs');
    final data = response['data'] as Map<String, dynamic>;
    final events = data['events'] as List<dynamic>? ?? const [];

    return events.map((v) {
      final item = Map<String, dynamic>.from(v as Map);
      final createdAt = item['createdAt'];
      return RiskAuditRecord(
        id: item['id'] as String,
        actorUid: item['actorUid'] as String? ?? '',
        riderId: item['riderId'] as String? ?? '',
        action: item['action'] as String? ?? '',
        reason: item['reason'] as String? ?? '',
        previousStatus: item['previousStatus'] as String? ?? '',
        newStatus: item['newStatus'] as String? ?? '',
        createdAt: createdAt is num
            ? DateTime.fromMillisecondsSinceEpoch(createdAt.toInt())
            : null,
      );
    }).toList(growable: false);
  }

  @override
  Future<bool> submitDemoChallengeResult({
    required String requestId,
    required bool passed,
  }) async {
    final response = await apiClient.post(
      '/api/challenges/$requestId/resolve',
      body: {'passed': passed},
    );
    final data = response['data'] as Map<String, dynamic>;
    return data['recorded'] == true;
  }

  @override
  Future<String> adminReviewRider({
    required String riderId,
    required String requestId,
    required String action,
    required String reason,
  }) async {
    final response = await apiClient.post(
      '/api/admin/riders/$riderId/review',
      body: {
        'action': action,
        'reason': reason,
        'requestId': requestId,
      },
    );
    final data = response['data'] as Map<String, dynamic>;
    return data['status'] as String;
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
