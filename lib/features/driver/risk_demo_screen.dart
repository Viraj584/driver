import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../core/risk/risk_engine.dart';
import '../../core/risk/risk_gateway.dart';

class RiskDemoScreen extends StatefulWidget {
  const RiskDemoScreen({
    this.firebaseConfigured = false,
    this.backend,
    super.key,
  });

  final bool firebaseConfigured;
  final RiskEventGateway? backend;

  @override
  State<RiskDemoScreen> createState() => _RiskDemoScreenState();
}

class _RiskDemoScreenState extends State<RiskDemoScreen> {
  final _engine = const RiskEngine();
  RiderRiskStatus _status = RiderRiskStatus.active;
  RiskEvaluation _evaluation = const RiskEvaluation(
    score: 0,
    reasons: [],
    status: RiderRiskStatus.active,
    reviewRequired: false,
  );
  final List<String> _events = ['Shift started · demo session'];
  List<RiskEventRecord> _serverEvents = const [];
  List<RiskAuditRecord> _auditEvents = const [];
  bool _challengePassed = false;
  bool _busy = false;
  bool _isAdmin = false;
  String? _pendingRequestId;
  String? _serverMessage;
  int _requestCounter = 0;

  bool get _serverMode => widget.firebaseConfigured;
  bool get _serverReady => widget.backend?.isSignedIn ?? false;
  bool get _actionsEnabled => (!_serverMode || _serverReady) && !_busy;

  @override
  void initState() {
    super.initState();
    if (_serverMode && _serverReady) _refreshHistory();
  }

  Future<void> _simulate(
    RiskEventType event,
    String label, {
    bool poorAccuracy = false,
  }) async {
    if (_busy) return;
    if (!_serverReady && _serverMode) {
      setState(
        () => _serverMessage = 'Sign in from the rider account screen to submit server risk events.',
      );
      return;
    }
    if (!_serverMode) {
      setState(() {
        _evaluation = _engine.evaluate(
          event: event,
          currentStatus: _status,
          poorLocationAccuracy: poorAccuracy,
        );
        _status = _evaluation.status;
        _events.insert(
          0,
          '$label · score ${_evaluation.score.toStringAsFixed(2)}',
        );
      });
      return;
    }

    final backend = widget.backend!;
    final requestId =
        'risk_${DateTime.now().microsecondsSinceEpoch}_${_requestCounter++}';
    setState(() {
      _busy = true;
      _serverMessage = null;
    });
    try {
      final result = await backend.submitEvent(
        requestId: requestId,
        event: event,
        poorLocationAccuracy: poorAccuracy,
      );
      if (!mounted) return;
      setState(() {
        if (result.verificationRequired) {
          _pendingRequestId = result.requestId;
        }
        _evaluation = RiskEvaluation(
          score: result.score,
          reasons: result.reasons,
          status: result.status,
          reviewRequired: result.reviewRequired,
        );
        _status = result.status;
        _events.insert(
          0,
          '$label · server score ${result.score.toStringAsFixed(2)}',
        );
      });
      await _refreshHistory();
    } catch (error) {
      if (mounted) setState(() => _serverMessage = _safeBackendError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshHistory() async {
    final backend = widget.backend;
    if (backend == null || !backend.isSignedIn) return;
    try {
      final admin = await backend.isAdministrator();
      final events = await backend.getHistory(fleet: admin);
      final audit = admin
          ? await backend.getAuditHistory()
          : const <RiskAuditRecord>[];
      if (mounted) {
        setState(() {
          _isAdmin = admin;
          _serverEvents = events;
          _auditEvents = audit;
          _pendingRequestId = events
              .where(
                (event) =>
                    event.verificationRequired &&
                    event.currentStatus == 'LIVENESS_PENDING',
              )
              .firstOrNull
              ?.requestId;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _serverMessage = _safeBackendError(error));
    }
  }

  String _safeBackendError(Object error) {
    if (error is FirebaseFunctionsException) {
      return switch (error.code) {
        'unauthenticated' => 'Sign in is required for server risk events.',
        'permission-denied' =>
          'This account is not authorized for that risk view.',
        'unavailable' || 'deadline-exceeded' =>
          'Risk service unavailable. Check Firebase Functions setup.',
        _ =>
          'Risk request failed (${error.code}). Check Firebase Functions setup.',
      };
    }
    return 'Risk service is not reachable. Check Firebase Functions setup and network.';
  }

  Future<void> _resolve(bool passed) async {
    if (_busy) return;
    if (_serverMode) {
      final backend = widget.backend;
      final requestId = _pendingRequestId;
      if (backend == null || requestId == null || !backend.isSignedIn) return;
      setState(() {
        _busy = true;
        _serverMessage = null;
      });
      try {
        final recorded = await backend.submitDemoChallengeResult(
          requestId: requestId,
          passed: passed,
        );
        if (!mounted) return;
        setState(() {
          _challengePassed = recorded && passed;
          _serverMessage = recorded
              ? 'Simulated result recorded. Server status remains pending policy review.'
              : 'The challenge expired. The session remains pending review.';
        });
        await _refreshHistory();
      } catch (error) {
        if (mounted) setState(() => _serverMessage = _safeBackendError(error));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    setState(() {
      _challengePassed = passed;
      _evaluation = _engine.evaluate(
        event: RiskEventType.possibleHandoff,
        currentStatus: _status,
        verified: passed,
      );
      _status = passed ? RiderRiskStatus.active : RiderRiskStatus.restricted;
      _events.insert(
        0,
        passed
            ? 'Demonstration check passed · review state cleared'
            : 'Demonstration check failed · review required',
      );
    });
  }

  Future<void> _reviewEvent(RiskEventRecord event, String action) async {
    final backend = widget.backend;
    if (backend == null || !_isAdmin || _busy) return;
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          action == 'RESTRICT_ACCOUNT'
              ? 'Restrict rider account?'
              : 'Approve session?',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              action == 'RESTRICT_ACCOUNT'
                  ? 'This changes server-authoritative rider status and writes an audit record.'
                  : 'This clears the pending session state and writes an audit record.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Review reason (at least 8 characters)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = reasonController.text.trim();
              if (value.length >= 8) Navigator.pop(dialogContext, value);
            },
            child: Text(
              action == 'RESTRICT_ACCOUNT' ? 'Confirm restriction' : 'Approve',
            ),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (reason == null || !mounted) return;
    setState(() {
      _busy = true;
      _serverMessage = null;
    });
    try {
      await backend.adminReviewRider(
        riderId: event.riderId,
        requestId:
            'review_${DateTime.now().microsecondsSinceEpoch}_${_requestCounter++}',
        action: action,
        reason: reason,
      );
      await _refreshHistory();
      if (mounted) {
        setState(
          () => _serverMessage =
              'Administrative decision saved to server audit history.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _serverMessage = _safeBackendError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final restricted = _status == RiderRiskStatus.restricted;
    final displayedEvents = _serverMode
        ? _serverEvents
        : const <RiskEventRecord>[];
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Trust Juggler · Rider'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF191C1D),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(32),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              _serverMode
                  ? 'SERVER RISK FLOW · FIREBASE'
                  : 'LOCAL DEMO — NOT SYNCED TO FIREBASE',
              style: const TextStyle(fontSize: 11, letterSpacing: 1.2),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _panel(
            'SHIFT OVERVIEW',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _serverMode
                      ? 'Authenticated rider session'
                      : 'Rider Demo · Shift active',
                ),
                const SizedBox(height: 8),
                Text(
                  'Account state: ${_status.name.replaceAll('verificationPending', 'verification pending').toUpperCase()}',
                ),
                Text(
                  'Risk score: ${_evaluation.score.toStringAsFixed(2)} · demonstration signal, not a probability',
                ),
                if (_evaluation.reasons.isNotEmpty)
                  Text('Reasons: ${_evaluation.reasons.join(', ')}'),
                if (_evaluation.reviewRequired)
                  const Text(
                    'Administrator review required for a restrictive action.',
                  ),
                if (_serverMode && !_serverReady)
                  const Text(
                    'Sign in from the rider account screen to use server evaluation.',
                  ),
                if (_serverMessage != null) Text(_serverMessage!),
                if (_busy) const LinearProgressIndicator(),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _panel(
            _serverMode
                ? 'SIMULATOR · AUTHENTICATED SERVER EVALUATION'
                : 'SIMULATOR · ALL EVENTS USE THE SAME LOCAL ENGINE',
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _action(
                  'Normal telemetry',
                  () => _simulate(RiskEventType.normal, 'Normal telemetry'),
                ),
                _action(
                  'Device change',
                  () => _simulate(RiskEventType.deviceChange, 'Device change'),
                ),
                _action(
                  'GPS jump · poor accuracy',
                  () => _simulate(
                    RiskEventType.gpsJump,
                    'Uncertain GPS jump',
                    poorAccuracy: true,
                  ),
                ),
                _action(
                  'Unusual speed',
                  () => _simulate(
                    RiskEventType.unusualSpeed,
                    'Unusual speed delta',
                  ),
                ),
                _action(
                  'Possible handoff',
                  () => _simulate(
                    RiskEventType.possibleHandoff,
                    'Possible account handoff',
                  ),
                ),
                _action(
                  'Request verification',
                  () => _simulate(
                    RiskEventType.possibleHandoff,
                    'Step-up requested',
                  ),
                ),
              ],
            ),
          ),
          if (_status == RiderRiskStatus.verificationPending) ...[
            const SizedBox(height: 12),
            _panel(
              _serverMode
                  ? 'STEP-UP CHECK · SIMULATED'
                  : 'STEP-UP CHECK · SIMULATED',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'A combined session anomaly needs an additional check. Face movement is simulated and does not verify identity or prove liveness.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      _action('Complete demo check', () => _resolve(true)),
                      _action('Fail demo check', () => _resolve(false)),
                    ],
                  ),
                  if (_challengePassed)
                    const Text(
                      'Simulated result recorded; policy review remains required.',
                    ),
                ],
              ),
            ),
          ],
          if (restricted)
            _panel(
              'RESTRICTED · REVIEW REQUIRED',
              const Text(
                'The local demonstration challenge failed. Real account restrictions require an authorized server policy decision; contact fleet support for review.',
              ),
            ),
          const SizedBox(height: 12),
          _panel(
            _serverMode
                ? (_isAdmin
                      ? 'FLEET RISK EVENTS · SERVER DATA'
                      : 'RECENT RISK EVENTS · SERVER DATA')
                : 'RECENT RISK EVENTS · SYNTHETIC',
            _serverMode
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _serverReady ? _refreshHistory : null,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh'),
                        ),
                      ),
                      if (_serverReady && displayedEvents.isEmpty)
                        const Text('No persisted risk events found.'),
                      if (!_serverReady)
                        const Text('Sign in to load authorized server events.'),
                      ...displayedEvents
                          .take(20)
                          .map(
                            (event) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${event.receivedAt?.toLocal() ?? 'Time pending'} · ${event.riderId} · ${event.eventType} · ${event.score.toStringAsFixed(2)} · ${event.reasons.join(', ')} · ${event.status} → ${event.currentStatus}${event.reviewRequired ? ' · REVIEW' : ''}',
                                  ),
                                  if (_isAdmin &&
                                      event.currentStatus == 'LIVENESS_PENDING')
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        TextButton(
                                          onPressed: _busy
                                              ? null
                                              : () => _reviewEvent(
                                                  event,
                                                  'APPROVE_SESSION',
                                                ),
                                          child: const Text('APPROVE SESSION'),
                                        ),
                                        TextButton(
                                          onPressed: _busy
                                              ? null
                                              : () => _reviewEvent(
                                                  event,
                                                  'RESTRICT_ACCOUNT',
                                                ),
                                          child: const Text('RESTRICT ACCOUNT'),
                                        ),
                                      ],
                                    ),
                                  const Divider(height: 12),
                                ],
                              ),
                            ),
                          ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _events
                        .take(8)
                        .map(
                          (event) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Text(event),
                          ),
                        )
                        .toList(),
                  ),
          ),
          if (_serverMode && _isAdmin) ...[
            const SizedBox(height: 12),
            _panel(
              'ADMIN AUDIT HISTORY · APPEND ONLY',
              _auditEvents.isEmpty
                  ? const Text('No audit actions recorded.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _auditEvents
                          .take(20)
                          .map(
                            (audit) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                '${audit.createdAt?.toLocal() ?? 'Time pending'} · ${audit.action} · rider ${audit.riderId} · ${audit.previousStatus} → ${audit.newStatus} · ${audit.reason} · actor ${audit.actorUid}',
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
          ],
          const SizedBox(height: 12),
          _panel(
            'SESSION & PRIVACY',
            Text(
              _serverMode
                  ? 'Submitted simulator event labels are stored with server received time. Event labels are demonstration inputs, not verified location or device facts. Raw location and device identifiers are not collected.'
                  : 'Demo session · Device identifiers and location are not collected. Normal travel, connectivity loss, and a device replacement alone do not freeze an account.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(String title, Widget child) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFE5E7EB)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );

  Widget _action(String label, VoidCallback action) => OutlinedButton(
    onPressed: _actionsEnabled ? action : null,
    child: Text(label),
  );
}
