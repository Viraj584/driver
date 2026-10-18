import 'package:flutter/material.dart';

import '../../core/integrations/driver_provider_gateways.dart';

const _blue = Color(0xFF2563EB);
const _canvas = Color(0xFFFAF8FF);
const _ink = Color(0xFF131B2E);
const _muted = Color(0xFF434655);
const _line = Color(0xFFC3C6D7);
const _green = Color(0xFF006C49);
const _blueWash = Color(0xFFE9EEFF);

class DriverOrderSummary {
  const DriverOrderSummary({
    required this.id,
    required this.title,
    required this.pickup,
    required this.dropoff,
    required this.amount,
    required this.distance,
    required this.eta,
    required this.serviceType,
    required this.recipientLabel,
    this.tags = '',
    this.notes = '',
  });

  final String id;
  final String title;
  final String pickup;
  final String dropoff;
  final int amount;
  final String distance;
  final String eta;
  final String serviceType;
  final String recipientLabel;
  final String tags;
  final String notes;

  String get amountLabel => '₹$amount';
}

enum DriverBiometricModality { faceScan, fingerprint }

enum PayoutStatus { pending, processing, paid, failed, unavailable }

/// Stitch dispatch-confirmation page, shown as a demo preview until both
/// server dispatch authorization and an approved face/liveness provider exist.
class DispatchConfirmationScreen extends StatefulWidget {
  const DispatchConfirmationScreen({
    required this.order,
    required this.onPreviewCompletion,
    super.key,
  });

  final DriverOrderSummary order;
  final VoidCallback onPreviewCompletion;

  @override
  State<DispatchConfirmationScreen> createState() =>
      _DispatchConfirmationScreenState();
}

class _DispatchConfirmationScreenState
    extends State<DispatchConfirmationScreen> {
  DriverBiometricModality _modality = DriverBiometricModality.faceScan;

  @override
  Widget build(BuildContext context) => _DriverJourneyScaffold(
    title: 'Biometric Order Verification',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _DemoBanner(
          text: 'SAMPLE ORDER · DISPATCH IS NOT AVAILABLE',
          icon: Icons.info_outline,
        ),
        const SizedBox(height: 16),
        _OrderSummaryCard(order: widget.order, title: 'Confirm Verification'),
        const SizedBox(height: 20),
        const Text(
          'Choose a verification method',
          style: TextStyle(
            color: _ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        SegmentedButton<DriverBiometricModality>(
          segments: const [
            ButtonSegment(
              value: DriverBiometricModality.faceScan,
              icon: Icon(Icons.face_retouching_natural_outlined),
              label: Text('Face scan'),
            ),
            ButtonSegment(
              value: DriverBiometricModality.fingerprint,
              icon: Icon(Icons.fingerprint),
              label: Text('Fingerprint'),
            ),
          ],
          selected: {_modality},
          onSelectionChanged: (value) =>
              setState(() => _modality = value.first),
        ),
        const SizedBox(height: 14),
        _modality == DriverBiometricModality.faceScan
            ? const _ProviderUnavailableCard(
                icon: Icons.face_retouching_natural_outlined,
                title: 'Face scan & liveness unavailable',
                detail: 'No approved identity or face/liveness provider is connected. No camera scan or identity match is being performed.',
              )
            : const _ProviderUnavailableCard(
                icon: Icons.fingerprint,
                title: 'Device biometric is local only',
                detail: 'Android biometrics unlock this app session. They do not prove identity to the server or authorize dispatch.',
              ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          key: const Key('dispatch-navigation-unavailable'),
          onPressed: null,
          icon: const Icon(Icons.near_me_outlined),
          label: const Text('Turn-by-turn navigation unavailable'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('dispatch-confirm-disabled'),
          onPressed: null,
          icon: const Icon(Icons.lock_outline),
          label: const Text('Dispatch authorization unavailable'),
        ),
        const SizedBox(height: 8),
        const Text(
          'This preview cannot start or assign a delivery. Server authorization and real verification evidence are required.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 12, height: 1.45),
        ),
        const SizedBox(height: 18),
        OutlinedButton(
          key: const Key('preview-delivery-completion'),
          onPressed: widget.onPreviewCompletion,
          child: const Text('Preview delivery completion screen'),
        ),
      ],
    ),
  );
}

/// Stitch completion page. Completion and payout are read-only previews until
/// server transitions and recipient verification are implemented.
class DeliveryCompletionScreen extends StatefulWidget {
  const DeliveryCompletionScreen({
    required this.order,
    required this.onPreviewPayout,
    super.key,
  });

  final DriverOrderSummary order;
  final VoidCallback onPreviewPayout;

  @override
  State<DeliveryCompletionScreen> createState() =>
      _DeliveryCompletionScreenState();
}

class _DeliveryCompletionScreenState extends State<DeliveryCompletionScreen> {
  DriverBiometricModality _modality = DriverBiometricModality.fingerprint;

  @override
  Widget build(BuildContext context) => _DriverJourneyScaffold(
    title: 'Delivery Completion Verification',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _DemoBanner(
          text: 'DEMO DELIVERY · NOT COMPLETED',
          icon: Icons.info_outline,
        ),
        const SizedBox(height: 14),
        _OrderSummaryCard(
          order: widget.order,
          title: 'Active delivery preview',
        ),
        const SizedBox(height: 14),
        const _StatusRow(
          title: 'Recipient verification',
          value: 'Unavailable',
          detail: 'No recipient OTP or verification provider is connected.',
          icon: Icons.person_search_outlined,
          tone: _muted,
        ),
        const SizedBox(height: 8),
        const _StatusRow(
          title: 'Completion status',
          value: 'Not submitted',
          detail: 'No delivery-completion operation exists on the server.',
          icon: Icons.pending_actions_outlined,
          tone: _muted,
        ),
        const SizedBox(height: 20),
        const Text(
          'Confirm verification',
          style: TextStyle(
            color: _ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        SegmentedButton<DriverBiometricModality>(
          segments: const [
            ButtonSegment(
              value: DriverBiometricModality.faceScan,
              icon: Icon(Icons.face_retouching_natural_outlined),
              label: Text('Face scan'),
            ),
            ButtonSegment(
              value: DriverBiometricModality.fingerprint,
              icon: Icon(Icons.fingerprint),
              label: Text('Fingerprint'),
            ),
          ],
          selected: {_modality},
          onSelectionChanged: (value) =>
              setState(() => _modality = value.first),
        ),
        const SizedBox(height: 14),
        _ProviderUnavailableCard(
          icon: _modality == DriverBiometricModality.faceScan
              ? Icons.face_retouching_natural_outlined
              : Icons.fingerprint,
          title: _modality == DriverBiometricModality.faceScan
              ? 'Face/liveness provider unavailable'
              : 'Device biometric does not verify recipient delivery',
          detail: _modality == DriverBiometricModality.faceScan
              ? 'No approved provider is configured for a face match or liveness check.'
              : 'Local device authentication does not replace recipient verification or server evidence.',
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const Key('delivery-completion-disabled'),
          onPressed: null,
          icon: const Icon(Icons.lock_outline),
          label: const Text('Completion is unavailable'),
        ),
        const SizedBox(height: 8),
        const Text(
          'No completion or payout is recorded by this preview.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 12),
        ),
        const SizedBox(height: 18),
        OutlinedButton(
          key: const Key('preview-payout'),
          onPressed: widget.onPreviewPayout,
          child: const Text('Preview payout status screen'),
        ),
      ],
    ),
  );
}

/// Stitch payout page. Only provider-returned states/references can be shown;
/// the default state here is unavailable and no QR or transfer is generated.
class DriverPayoutScreen extends StatelessWidget {
  const DriverPayoutScreen({
    required this.order,
    this.status = PayoutStatus.unavailable,
    this.transactionReference,
    super.key,
  });

  final DriverOrderSummary order;
  final PayoutStatus status;
  final String? transactionReference;

  @override
  Widget build(BuildContext context) => _DriverJourneyScaffold(
    title: 'UPI Payout',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _DemoBanner(
          text: 'SAMPLE AMOUNT · NO PAYMENT HAS BEEN INITIATED',
          icon: Icons.info_outline,
        ),
        const SizedBox(height: 14),
        _DesignCard(
          child: Column(
            children: [
              const Text(
                'ILLUSTRATIVE DELIVERY AMOUNT',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .7,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                order.amountLabel,
                style: const TextStyle(
                  color: _blue,
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${order.title} · ${order.dropoff}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _StatusRow(
          title: 'Payout status',
          value: _payoutLabel(status),
          detail: _payoutDetail(status),
          icon: _payoutIcon(status),
          tone: _payoutTone(status),
        ),
        const SizedBox(height: 14),
        _DesignCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              Row(
                children: [
                  Icon(Icons.qr_code_2, color: _blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Dynamic QR code unavailable',
                      style: TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Text(
                'A payment provider and server-generated transaction are required before a scannable code can be shown.',
                style: TextStyle(color: _muted, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _StatusRow(
          title: 'Transaction reference',
          value: transactionReference ?? 'Not available',
          detail: transactionReference == null
              ? 'No provider has returned a transaction reference.'
              : 'Reference supplied by the configured payment provider.',
          icon: Icons.receipt_long_outlined,
          tone: transactionReference == null ? _muted : _green,
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const Key('payout-retry-disabled'),
          onPressed: null,
          icon: const Icon(Icons.refresh),
          label: const Text('Payout retry unavailable'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('payout-received-disabled'),
          onPressed: null,
          icon: const Icon(Icons.lock_outline),
          label: const Text('Payout receipt cannot be confirmed here'),
        ),
        const SizedBox(height: 10),
        const Text(
          'No UPI ID, QR code, transfer, escrow release, or payment confirmation is configured in this app.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 12, height: 1.45),
        ),
      ],
    ),
  );
}

String _payoutLabel(PayoutStatus status) => switch (status) {
  PayoutStatus.pending => 'Pending',
  PayoutStatus.processing => 'Processing',
  PayoutStatus.paid => 'Paid',
  PayoutStatus.failed => 'Failed',
  PayoutStatus.unavailable => 'Unavailable',
};

String _payoutDetail(PayoutStatus status) => switch (status) {
  PayoutStatus.pending => 'Awaiting provider processing.',
  PayoutStatus.processing => 'Provider reports the transfer is processing.',
  PayoutStatus.paid => 'Paid status must be confirmed by the payment provider.',
  PayoutStatus.failed =>
    'Provider reported a failure; retry must be idempotent.',
  PayoutStatus.unavailable => 'No payout service or status is connected.',
};

IconData _payoutIcon(PayoutStatus status) => switch (status) {
  PayoutStatus.pending => Icons.schedule,
  PayoutStatus.processing => Icons.sync,
  PayoutStatus.paid => Icons.check_circle_outline,
  PayoutStatus.failed => Icons.error_outline,
  PayoutStatus.unavailable => Icons.cloud_off_outlined,
};

Color _payoutTone(PayoutStatus status) => switch (status) {
  PayoutStatus.pending || PayoutStatus.processing => _blue,
  PayoutStatus.paid => _green,
  PayoutStatus.failed => const Color(0xFFB42318),
  PayoutStatus.unavailable => _muted,
};

class _DriverJourneyScaffold extends StatelessWidget {
  const _DriverJourneyScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _canvas,
    appBar: AppBar(
      backgroundColor: _canvas,
      foregroundColor: _ink,
      elevation: 0,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    ),
    body: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: child,
          ),
        ),
      ),
    ),
  );
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('demo-state-banner'),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: _blueWash,
      border: Border.all(color: const Color(0xFFBFDBFE)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon, color: _blue, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: _ink,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: .35,
            ),
          ),
        ),
      ],
    ),
  );
}

class _OrderSummaryCard extends StatelessWidget {
  const _OrderSummaryCard({required this.order, required this.title});

  final DriverOrderSummary order;
  final String title;

  @override
  Widget build(BuildContext context) => _DesignCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _ink,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.inventory_2_outlined, color: _blue),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                order.title,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              order.amountLabel,
              style: const TextStyle(
                color: _blue,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _RouteRow(
          icon: Icons.trip_origin,
          title: 'Pickup',
          detail: order.pickup,
        ),
        const Padding(
          padding: EdgeInsets.only(left: 9),
          child: SizedBox(
            height: 12,
            child: VerticalDivider(width: 1, color: _line),
          ),
        ),
        _RouteRow(
          icon: Icons.location_on_outlined,
          title: 'Drop-off',
          detail: order.dropoff,
        ),
        const Divider(height: 22),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            _Metric(icon: Icons.route_outlined, label: order.distance),
            _Metric(icon: Icons.schedule_outlined, label: order.eta),
            _Metric(
              icon: Icons.local_shipping_outlined,
              label: order.serviceType,
            ),
          ],
        ),
        if (order.notes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            order.notes,
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ],
      ],
    ),
  );
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 19, color: title == 'Pickup' ? _blue : _green),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: _muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: .5,
              ),
            ),
            Text(
              detail,
              style: const TextStyle(
                color: _ink,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: _muted),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
    ],
  );
}

class _ProviderUnavailableCard extends StatelessWidget {
  const _ProviderUnavailableCard({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => _DesignCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: _blueWash,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _blue, size: 25),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                detail,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
    required this.tone,
  });

  final String title;
  final String value;
  final String detail;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) => _DesignCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: tone),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      color: tone,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DesignCard extends StatelessWidget {
  const _DesignCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _line.withValues(alpha: .6)),
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [
        BoxShadow(
          color: Color(0x080F172A),
          blurRadius: 4,
          offset: Offset(0, 1),
        ),
      ],
    ),
    child: child,
  );
}

/// Integration point for an approved identity provider. It accepts no
/// document values in this app; a real implementation belongs behind a
/// reviewed provider and server contract.
IdentityVerificationGateway createIdentityVerificationGateway() =>
    UnavailableIdentityVerificationGateway();

/// Integration point for future provider-backed face/liveness checks.
FaceLivenessGateway createFaceLivenessGateway() =>
    UnavailableFaceLivenessGateway();

/// Integration point for a server-authoritative payout provider.
DriverPayoutGateway createDriverPayoutGateway() =>
    UnavailableDriverPayoutGateway();
