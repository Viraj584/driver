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
}
