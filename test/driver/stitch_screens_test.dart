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
    expect(find.text('Admin Command'), findsOneWidget);
    await tester.tap(find.text('ACCESS DRIVER PORTAL'));
    await tester.ensureVisible(find.text('Onboarding').first);
    await tester.tap(find.text('Onboarding').first);
    await tester.ensureVisible(find.text('ENTER FLEET COMMAND'));
    await tester.tap(find.text('ENTER FLEET COMMAND'));
    await tester.ensureVisible(find.text('Risk Engine').first);
    await tester.tap(find.text('Risk Engine').first);
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
    await tester.ensureVisible(find.text('ENTER FLEET COMMAND'));
    expect(tester.takeException(), isNull);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('bottom destinations open portal, onboarding, and risk actions', (
    tester,
  ) async {
    var portal = 0;
    var onboarding = 0;
    var risk = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TrustJugglerRoleSelector(
          onDriverAuth: () {},
          onOnboarding: () => onboarding++,
          onFleetAccess: () {},
          onRiskEngine: () => risk++,
          onPortal: () => portal++,
        ),
      ),
    );
    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
    navigation.onDestinationSelected!(0);
    navigation.onDestinationSelected!(1);
    navigation.onDestinationSelected!(2);
    expect(portal, 1);
    expect(onboarding, 1);
    expect(risk, 1);
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
    await tester.tap(find.text('High Payout'));
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

  testWidgets(
    'delivery pool uses authenticated identity and labels confirmation demo',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DriverDeliveryPoolPage(
            driverIdentity: 'driver@example.test',
            onSignOut: () async {},
            onSessionExpired: () {},
            onOpenBiometricQuickUnlock: () {},
            watchFirebaseSession: false,
          ),
        ),
      );
      expect(find.text('driver@example.test'), findsOneWidget);
      expect(
        find.textContaining('not live dispatch inventory'),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('preview-dispatch-verification')),
      );
      await tester.tap(find.byKey(const Key('preview-dispatch-verification')));
      await tester.pumpAndSettle();
      expect(find.text('Sample order preview'), findsOneWidget);
      expect(
        find.textContaining('No acceptance or dispatch was submitted.'),
        findsOneWidget,
      );
    },
  );
}
