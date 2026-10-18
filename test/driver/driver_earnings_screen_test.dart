import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/core/api/driver_finance_api.dart';
import 'package:rider_app/features/driver/driver_earnings_screen.dart';

class _FinanceRepository implements DriverFinanceRepository {
  _FinanceRepository({this.fail = false});
  final bool fail;
  @override
  Future<DriverFinanceSummary> getSummary() async {
    if (fail) {
      throw const DriverApiException(
        'unavailable',
        'The service is temporarily unavailable.',
      );
    }
    return const DriverFinanceSummary(
      availablePaise: 0,
      reservedPaise: 0,
      processingPaise: 0,
      paidPaise: 0,
      failedPaise: 0,
      releasedPaise: 0,
    );
  }

  @override
  Future<DriverFinancePage<DriverLedgerEntry>> getLedger({
    String? cursor,
  }) async => const DriverFinancePage(items: [], nextCursor: null);
  @override
  Future<List<DriverPayoutAccount>> getAccounts() async => [];
  @override
  Future<DriverFinancePage<DriverPayoutRecord>> getPayouts({
    String? cursor,
  }) async => const DriverFinancePage(items: [], nextCursor: null);
  @override
  Future<DriverPayoutAccount> setupAccount(
    Map<String, Object?> details,
  ) async => const DriverPayoutAccount(
    id: 'primary',
    type: 'bank_account',
    maskedDestination: '••••1234',
    status: 'pending_review',
  );
  @override
  Future<DriverPayoutRecord> requestPayout({
    required int amountPaise,
    required String payoutAccountId,
    required String idempotencyKey,
  }) async => const DriverPayoutRecord(
    id: 'payout',
    amountPaise: 100,
    status: 'awaiting_approval',
  );
  @override
  Future<DriverPayoutRecord> getPayoutByIdempotency(String key) async =>
      const DriverPayoutRecord(
        id: 'payout',
        amountPaise: 100,
        status: 'awaiting_approval',
      );
}

void main() {
  testWidgets(
    'earnings screen shows server empty state and no enabled payout without balance',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DriverEarningsScreen(repository: _FinanceRepository()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Request payout'),
      );
      expect(button.onPressed, isNull);
      await tester.drag(find.byType(ListView), const Offset(0, -1400));
      await tester.pumpAndSettle();
      expect(find.text('No credited earnings'), findsOneWidget);
      expect(
        find.text(
          'Delivery credits remain disabled until an approved pricing policy, managed route service, and reviewed evidence process are configured. Sample delivery values are not earnings.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('earnings service failure has retry state and no fake balance', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverEarningsScreen(repository: _FinanceRepository(fail: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('The service is temporarily unavailable.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('₹0.00'), findsNothing);
  });
}
