import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/driver/stitch_screens.dart';

void main() {
  testWidgets('role selector keeps driver and fleet actions separate', (
    tester,
  ) async {
    var driverAuth = 0;
    var onboarding = 0;
    var fleetAccess = 0;
    var riskEngine = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TrustJugglerRoleSelector(
          onDriverAuth: () => driverAuth++,
          onOnboarding: () => onboarding++,
          onFleetAccess: () => fleetAccess++,
          onRiskEngine: () => riskEngine++,
        ),
      ),
    );

    expect(find.text('Driver Portal'), findsOneWidget);
    expect(find.text('Fleet Dispatch'), findsOneWidget);
    await tester.tap(find.text('CONTINUE AS DRIVER'));
    await tester.ensureVisible(find.text('Onboarding'));
    await tester.tap(find.text('Onboarding'));
    await tester.ensureVisible(find.text('FLEET ACCESS'));
    await tester.tap(find.text('FLEET ACCESS'));
    await tester.ensureVisible(find.text('Risk Engine'));
    await tester.tap(find.text('Risk Engine'));
    expect(driverAuth, 1);
    expect(onboarding, 1);
    expect(fleetAccess, 1);
    expect(riskEngine, 1);
  });

  testWidgets('role selector fits a compact mobile viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: TrustJugglerRoleSelector(
          onDriverAuth: () {},
          onOnboarding: () {},
          onFleetAccess: () {},
          onRiskEngine: () {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('FLEET ACCESS'));
    expect(tester.takeException(), isNull);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('fleet route communicates that role selection gives no access', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: FleetAccessUnavailableScreen()),
    );
    expect(find.text('Authorized fleet access required'), findsOneWidget);
    expect(find.textContaining('does not grant access'), findsOneWidget);
  });

  testWidgets('delivery examples are labelled and acceptance is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: DriverDeliveryPoolScreen()),
        ),
      ),
    );
    expect(find.textContaining('not live dispatch inventory'), findsOneWidget);
    expect(find.text('TechCorp Logistics Hub (Gate 3)'), findsOneWidget);
    expect(find.textContaining('UNAVAILABLE'), findsOneWidget);
    await tester.tap(find.text('High payout'));
    await tester.pump();
    expect(find.text('Greenfield Regional Depot (Bay 11)'), findsNothing);
    expect(find.text('TechCorp Logistics Hub (Gate 3)'), findsOneWidget);
    await tester.tap(find.text('Express Delivery'));
    await tester.pump();
    expect(find.text('Greenfield Regional Depot (Bay 11)'), findsNothing);
    expect(find.text('TechCorp Logistics Hub (Gate 3)'), findsOneWidget);
    expect(find.text('Metro Cold Storage Unit B'), findsNothing);
    await tester.tap(find.text('Cold Chain'));
    await tester.pump();
    expect(find.text('Metro Cold Storage Unit B'), findsOneWidget);
    expect(find.text('TechCorp Logistics Hub (Gate 3)'), findsNothing);
  });
}
