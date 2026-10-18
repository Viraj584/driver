import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/core/risk/risk_engine.dart';
import 'package:rider_app/features/driver/risk_demo_screen.dart';

void main() {
  const engine = RiskEngine();

  test('normal telemetry remains active with no reasons', () {
    final result = engine.evaluate(
      event: RiskEventType.normal,
      currentStatus: RiderRiskStatus.active,
    );
    expect(result.score, 0);
    expect(result.status, RiderRiskStatus.active);
    expect(result.reasons, isEmpty);
  });

  test('device change alone does not freeze or request verification', () {
    final result = engine.evaluate(
      event: RiskEventType.deviceChange,
      currentStatus: RiderRiskStatus.active,
    );
    expect(result.score, 0.3);
    expect(result.status, RiderRiskStatus.active);
    expect(result.reviewRequired, isFalse);
  });

  test('poor GPS accuracy lowers the signal', () {
    final result = engine.evaluate(
      event: RiskEventType.gpsJump,
      currentStatus: RiderRiskStatus.active,
      poorLocationAccuracy: true,
    );
    expect(result.score, 0.05);
    expect(result.reasons, contains('GPS_UNCERTAIN'));
  });

  test('correlated handoff requests step-up but not automatic restriction', () {
    final result = engine.evaluate(
      event: RiskEventType.possibleHandoff,
      currentStatus: RiderRiskStatus.active,
    );
    expect(result.score, 0.65);
    expect(result.status, RiderRiskStatus.verificationPending);
    expect(result.reviewRequired, isFalse);
  });

  test(
    'verification reduces score and restricted state remains server policy',
    () {
      final passed = engine.evaluate(
        event: RiskEventType.possibleHandoff,
        currentStatus: RiderRiskStatus.verificationPending,
        verified: true,
      );
      expect(passed.score, 0.4);
      final restricted = engine.evaluate(
        event: RiskEventType.normal,
        currentStatus: RiderRiskStatus.restricted,
      );
      expect(restricted.status, RiderRiskStatus.restricted);
      expect(restricted.reviewRequired, isTrue);
    },
  );

  testWidgets('simulator exposes a visible step-up flow', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RiskDemoScreen()));
    expect(find.text('DEMO DATA · LOCAL RISK ENGINE'), findsOneWidget);
    await tester.ensureVisible(find.text('Possible handoff'));
    await tester.tap(find.text('Possible handoff'));
    await tester.pumpAndSettle();
    expect(find.text('STEP-UP CHECK · SIMULATED'), findsOneWidget);
    await tester.ensureVisible(find.text('Complete demo check'));
    await tester.tap(find.text('Complete demo check'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Demonstration check passed'), findsOneWidget);
  });
}
