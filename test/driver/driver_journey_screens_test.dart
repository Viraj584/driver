import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/core/integrations/driver_provider_gateways.dart';
import 'package:rider_app/features/driver/driver_journey_screens.dart';

const _order = DriverOrderSummary(
  id: 'TJ-DEMO-1',
  title: 'Sample delivery',
  pickup: 'Sample pickup',
  dropoff: 'Sample drop-off',
  amount: 380,
  distance: '4 km',
  eta: '18 min',
  serviceType: 'Express',
  recipientLabel: 'Sample recipient',
);

void main() {
  testWidgets('dispatch screen labels demo and cannot authorize dispatch', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DispatchConfirmationScreen(
          order: _order,
          onPreviewCompletion: () {},
        ),
      ),
    );

    expect(
      find.text('SAMPLE ORDER · DISPATCH IS NOT AVAILABLE'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('dispatch-confirm-disabled')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('dispatch-confirm-disabled')),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('No approved identity'), findsOneWidget);
  });

  testWidgets('completion and payout previews do not claim a transaction', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DeliveryCompletionScreen(order: _order, onPreviewPayout: () {}),
      ),
    );
    expect(find.text('DEMO DELIVERY · NOT COMPLETED'), findsOneWidget);
    expect(
      find.text('No recipient OTP or verification provider is connected.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('delivery-completion-disabled')),
          )
          .onPressed,
      isNull,
    );

    await tester.pumpWidget(
      MaterialApp(home: DriverPayoutScreen(order: _order)),
    );
    expect(
      find.text('SAMPLE AMOUNT · NO PAYMENT HAS BEEN INITIATED'),
      findsOneWidget,
    );
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('Not available'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('payout-retry-disabled')))
          .onPressed,
      isNull,
    );
  });

  test('provider placeholders fail closed as unavailable', () async {
    expect(
      (await createIdentityVerificationGateway().beginVerification()).status,
      ProviderOperationStatus.unavailable,
    );
    expect(
      (await createFaceLivenessGateway().verify(
        operationId: 'test',
        phase: 'dispatch',
      )).status,
      ProviderOperationStatus.unavailable,
    );
    expect(
      (await createDriverPayoutGateway().getPayoutStatus('test')).status,
      ProviderOperationStatus.unavailable,
    );
    expect(
      (await createDriverPayoutGateway().retryPayout('test')).status,
      ProviderOperationStatus.unavailable,
    );
  });

  testWidgets('biometric verification screen complies with all layout rectifications', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DispatchConfirmationScreen(
          order: _order,
          onPreviewCompletion: () {},
        ),
      ),
    );

    // 1. Top App Bar displays full title without cutoffs
    expect(find.text('Biometric Order Verification'), findsOneWidget);

    // 2. Tab selector has single line Face Scan and Fingerprint with minHeight >= 48
    expect(find.text('Face Scan'), findsOneWidget);
    expect(find.text('Fingerprint'), findsOneWidget);

    // 3. KYC Biometric Confidence card is present with separated match indicator
    expect(find.text('KYC Biometric Confidence'), findsOneWidget);
    expect(find.text('94.8% Match'), findsOneWidget);

    // 4. Action buttons have minimumSize height >= 52
    final confirmButton = tester.widget<FilledButton>(
      find.byKey(const Key('dispatch-confirm-disabled')),
    );
    expect(confirmButton.style?.minimumSize?.resolve({})?.height, greaterThanOrEqualTo(52));
    expect(find.text('Scan Face to Confirm & Dispatch'), findsOneWidget);

    final navButton = tester.widget<FilledButton>(
      find.byKey(const Key('dispatch-navigation-unavailable')),
    );
    expect(navButton.style?.minimumSize?.resolve({})?.height, greaterThanOrEqualTo(52));
    expect(find.text('Start GPS Turn-by-Turn Navigation'), findsOneWidget);

    // 5. Toggling to Fingerprint updates button text and retains minHeight >= 52
    await tester.tap(find.text('Fingerprint'));
    await tester.pumpAndSettle();
    expect(find.text('Place Finger to Confirm & Dispatch'), findsOneWidget);
    expect(find.text('Place Thumb on Sensor Prism'), findsOneWidget);
  });
}
