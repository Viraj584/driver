import 'package:flutter/material.dart';

import '../../core/risk/risk_engine.dart';

class RiskDemoScreen extends StatefulWidget {
  const RiskDemoScreen({super.key});

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
  bool _challengePassed = false;

  void _simulate(
    RiskEventType event,
    String label, {
    bool poorAccuracy = false,
  }) {
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
  }

  void _resolve(bool passed) {
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

  @override
  Widget build(BuildContext context) {
    final restricted = _status == RiderRiskStatus.restricted;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Trust Juggler · Rider'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF191C1D),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(32),
          child: Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'DEMO DATA · LOCAL RISK ENGINE',
              style: TextStyle(fontSize: 11, letterSpacing: 1.2),
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
                const Text('Rider Demo · Shift active'),
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
              ],
            ),
          ),
          const SizedBox(height: 12),
          _panel(
            'SIMULATOR · ALL EVENTS USE THE SAME LOCAL ENGINE',
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
              'STEP-UP CHECK · SIMULATED',
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
                    const Text('Demonstration check passed.'),
                ],
              ),
            ),
          ],
          if (restricted)
            _panel(
              'RESTRICTED · REVIEW REQUIRED',
              const Text(
                'The demonstration challenge failed. Account status changes require an authorized server policy decision; contact fleet support for review.',
              ),
            ),
          const SizedBox(height: 12),
          _panel(
            'RECENT RISK EVENTS · SYNTHETIC',
            Column(
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
          const SizedBox(height: 12),
          _panel(
            'SESSION & PRIVACY',
            const Text(
              'Demo session · Device identifiers and location are not collected. Normal travel, connectivity loss, and a device replacement alone do not freeze an account.',
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

  Widget _action(String label, VoidCallback action) =>
      OutlinedButton(onPressed: action, child: Text(label));
}
