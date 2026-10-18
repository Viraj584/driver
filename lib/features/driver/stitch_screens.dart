import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'dart:async';

import 'driver_journey_screens.dart';

const _blue = Color(0xFF2563EB);
const _deepBlue = Color(0xFF004AC6);
const _page = Color(0xFFFAF8FF);
const _ink = Color(0xFF131B2E);
const _muted = Color(0xFF434655);
const _line = Color(0xFFC3C6D7);
const _green = Color(0xFF006C49);

/// Landing role choice. Fleet access intentionally routes to a separate
/// unavailable state and never assigns an administrator role.
class TrustJugglerRoleSelector extends StatefulWidget {
  const TrustJugglerRoleSelector({
    required this.onDriverAuth,
    required this.onOnboarding,
    required this.onFleetAccess,
    required this.onRiskEngine,
    this.onPortal,
    super.key,
  });

  final VoidCallback onDriverAuth;
  final VoidCallback onOnboarding;
  final VoidCallback onFleetAccess;
  final VoidCallback onRiskEngine;
  final VoidCallback? onPortal;

  @override
  State<TrustJugglerRoleSelector> createState() =>
      _TrustJugglerRoleSelectorState();
}

class _TrustJugglerRoleSelectorState extends State<TrustJugglerRoleSelector> {
  int _selectedDestination = 0;

  void _selectDestination(int index) {
    setState(() => _selectedDestination = index);
    switch (index) {
      case 0:
        widget.onPortal?.call();
        break;
      case 1:
        widget.onOnboarding();
        break;
      case 2:
        widget.onRiskEngine();
        break;
      default:
        widget.onDriverAuth();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _page,
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _BrandHeader(),
                const SizedBox(height: 34),
                const Text(
                  'Choose your workspace',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Secure access for drivers and fleet teams.',
                  style: TextStyle(color: _muted, fontSize: 15),
                ),
                const SizedBox(height: 24),
                _RoleCard(
                  icon: Icons.delivery_dining_outlined,
                  title: 'Driver Portal',
                  subtitle: 'Sign in, complete verification and view available deliveries.',
                  action: 'ACCESS DRIVER PORTAL',
                  onTap: widget.onDriverAuth,
                  prominent: true,
                ),
                const SizedBox(height: 12),
                _RoleCard(
                  icon: Icons.local_shipping_outlined,
                  title: 'Admin Command',
                  subtitle:
                      'Fleet access requires an authorized operator account.',
                  action: 'ENTER FLEET COMMAND',
                  onTap: widget.onFleetAccess,
                ),
                const SizedBox(height: 24),
                const Text(
                  'QUICK ACCESS',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _QuickAction(
                        icon: Icons.lock_open_outlined,
                        label: 'Driver Auth',
                        onTap: widget.onDriverAuth,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _QuickAction(
                        icon: Icons.assignment_ind_outlined,
                        label: 'Onboarding',
                        onTap: widget.onOnboarding,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _QuickAction(
                        icon: Icons.shield_outlined,
                        label: 'Risk Engine',
                        onTap: widget.onRiskEngine,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Driver approval and dispatch authorization are controlled by the server.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    bottomNavigationBar: NavigationBar(
      backgroundColor: Colors.white,
      indicatorColor: const Color(0xFFE9EEFF),
      selectedIndex: _selectedDestination,
      onDestinationSelected: _selectDestination,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home, color: _blue),
          label: 'Portal',
        ),
        NavigationDestination(
          icon: Icon(Icons.assignment_ind_outlined),
          label: 'Onboarding',
        ),
        NavigationDestination(
          icon: Icon(Icons.monitor_heart_outlined),
          label: 'Risk Engine',
        ),
      ],
    ),
  );
}

class FleetAccessUnavailableScreen extends StatelessWidget {
  const FleetAccessUnavailableScreen({this.onAuthenticate, super.key});

  final VoidCallback? onAuthenticate;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _page,
    appBar: AppBar(
      backgroundColor: _page,
      foregroundColor: _ink,
      title: const Text('Fleet Dispatch'),
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.admin_panel_settings_outlined, color: _blue, size: 52),
            SizedBox(height: 16),
            Text(
              'Authorized fleet access required',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _ink,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            const Text(
              'Fleet access is checked against a trusted administrator claim. Selecting Fleet Dispatch does not grant access.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, height: 1.5),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAuthenticate,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Sign in to Fleet Command'),
            ),
          ],
        ),
      ),
    ),
  );
}

class FleetAuditDashboard extends StatefulWidget {
  const FleetAuditDashboard({this.functions, this.onSessionExpired, super.key});

  final FirebaseFunctions? functions;
  final VoidCallback? onSessionExpired;

  @override
  State<FleetAuditDashboard> createState() => _FleetAuditDashboardState();
}

class _FleetAuditDashboardState extends State<FleetAuditDashboard> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _events = const [];
  StreamSubscription<User?>? _authSubscription;
  bool _expiredHandled = false;

  @override
  void initState() {
    super.initState();
    _loadAudit();
    _authSubscription = FirebaseAuth.instance.userChanges().listen((user) {
      if (user == null && !_expiredHandled) {
        _expiredHandled = true;
        widget.onSessionExpired?.call();
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadAudit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result =
          await (widget.functions ??
                  FirebaseFunctions.instanceFor(region: 'us-central1'))
              .httpsCallable('getFleetAuditHistory')
              .call<Map<String, dynamic>>();
      final events = result.data['events'];
      if (events is! List) {
        throw const FormatException('Audit response is invalid.');
      }
      if (!mounted) return;
      setState(() {
        _events = events
            .whereType<Map>()
            .map((event) => Map<String, dynamic>.from(event))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Fleet audit history could not be loaded. Check administrator access and service availability.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _page,
    appBar: AppBar(
      backgroundColor: Colors.white,
      foregroundColor: _ink,
      title: const Text('Fleet Command · Audit'),
      actions: [
        IconButton(
          tooltip: 'Sign out',
          onPressed: () => FirebaseAuth.instance.signOut(),
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _loadAudit,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          )
        : _events.isEmpty
        ? const Center(child: Text('No audit events have been recorded.'))
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _events.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final event = _events[index];
              return Card(
                color: Colors.white,
                child: ListTile(
                  leading: const Icon(
                    Icons.receipt_long_outlined,
                    color: _blue,
                  ),
                  title: Text('${event['action'] ?? 'Audit event'}'),
                  subtitle: Text(
                    'Rider: ${event['riderId'] ?? 'unknown'}\n${event['reason'] ?? ''}',
                  ),
                  isThreeLine: true,
                  trailing: Text(
                    '${event['newStatus'] ?? ''}',
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                ),
              );
            },
          ),
  );
}

class DriverDeliveryPoolPage extends StatefulWidget {
  const DriverDeliveryPoolPage({
    required this.driverIdentity,
    required this.onSignOut,
    required this.onSessionExpired,
    required this.onOpenBiometricQuickUnlock,
    this.watchFirebaseSession = true,
    this.demoMode = false,
    super.key,
  });

  final String driverIdentity;
  final Future<void> Function() onSignOut;
  final VoidCallback onSessionExpired;
  final VoidCallback onOpenBiometricQuickUnlock;
  final bool watchFirebaseSession;
  final bool demoMode;

  @override
  State<DriverDeliveryPoolPage> createState() => _DriverDeliveryPoolPageState();
}

class _DriverDeliveryPoolPageState extends State<DriverDeliveryPoolPage> {
  StreamSubscription<User?>? _authSubscription;
  bool _signingOut = false;
  bool _sessionExpiredHandled = false;

  @override
  void initState() {
    super.initState();
    if (widget.watchFirebaseSession && !widget.demoMode) {
      _authSubscription = FirebaseAuth.instance.userChanges().listen((user) {
        if (user == null && !_sessionExpiredHandled) {
          _sessionExpiredHandled = true;
          widget.onSessionExpired();
        }
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await widget.onSignOut();
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _page,
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 12, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _blue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.local_shipping_outlined,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Driver Delivery Pool',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        widget.driverIdentity,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Local biometric quick unlock',
                  onPressed: widget.onOpenBiometricQuickUnlock,
                  icon: const Icon(Icons.fingerprint, color: _blue),
                ),
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: _signingOut ? null : _signOut,
                  icon: _signingOut
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.logout, color: _muted),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _line),
          if (widget.demoMode)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              color: const Color(0xFFFFF1D6),
              child: const Text(
                'LOCAL DEMO — NOT SYNCED TO FIREBASE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF704900),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              child: DriverDeliveryPoolScreen(
                driverIdentity: widget.driverIdentity,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class RiskEngineUnavailableScreen extends StatelessWidget {
  const RiskEngineUnavailableScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _page,
    appBar: AppBar(
      backgroundColor: _page,
      foregroundColor: _ink,
      title: const Text('Risk Engine'),
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.monitor_heart_outlined, color: _blue, size: 52),
            SizedBox(height: 16),
            Text(
              'Risk engine is not connected',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _ink,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'No live risk events or fleet telemetry are available in this app. Connect an authorized backend before using risk decisions.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, height: 1.5),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Delivery examples are explicitly marked as sample data. Acceptance is
/// disabled because no server-side order acceptance operation exists.
class DriverDeliveryPoolScreen extends StatefulWidget {
  const DriverDeliveryPoolScreen({
    this.onPreviewDispatch,
    this.driverIdentity,
    super.key,
  });

  final ValueChanged<DriverOrderSummary>? onPreviewDispatch;
  final String? driverIdentity;

  @override
  State<DriverDeliveryPoolScreen> createState() =>
      _DriverDeliveryPoolScreenState();
}

class _DriverDeliveryPoolScreenState extends State<DriverDeliveryPoolScreen> {
  String _filter = 'All';
  int _selected = 0;

  static const _orders = <DriverOrderSummary>[
    DriverOrderSummary(
      id: 'TJ-DEMO-8492',
      title: 'Express Cargo',
      pickup: 'TechCorp Logistics Hub (Gate 3)',
      dropoff: 'Apex Towers, 8th Floor, Sector 4',
      amount: 380,
      distance: '4.2 km',
      eta: '18 min',
      serviceType: 'Express',
      recipientLabel: 'Sample recipient',
      notes: '12 kg · Contactless PIN shown as a design reference only',
      tags: 'High payout',
    ),
    DriverOrderSummary(
      id: 'TJ-DEMO-8493',
      title: 'Cold-Chain Pharma',
      pickup: 'Metro Cold Storage Unit B',
      dropoff: 'St. Jude Healthcare & Research',
      amount: 520,
      distance: '7.8 km',
      eta: '26 min',
      serviceType: 'Cold chain',
      recipientLabel: 'Sample recipient',
      notes: '2–8°C temperature regulated · Priority',
      tags: 'High payout Cold Chain',
    ),
    DriverOrderSummary(
      id: 'TJ-DEMO-8494',
      title: 'Standard Parcel',
      pickup: 'Greenfield Regional Depot (Bay 11)',
      dropoff: 'Phoenix Market City, Level 2',
      amount: 260,
      distance: '3.1 km',
      eta: '14 min',
      serviceType: 'Standard',
      recipientLabel: 'Sample recipient',
      notes: 'Sample order details · no dispatch is available',
      tags: 'Nearby',
    ),
  ];

  bool _matchesFilter(DriverOrderSummary order, String filter) =>
      switch (filter) {
        'High Payout' => order.tags.toLowerCase().contains('high payout'),
        'Express Delivery' => order.serviceType.toLowerCase() == 'express',
        'Cold Chain' => order.serviceType.toLowerCase() == 'cold chain',
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final order = _orders[_selected];
    return Container(
      key: const Key('delivery-pool'),
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'DELIVERY POOL',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F8F0),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text(
                  'APPROVED ACCOUNT',
                  style: TextStyle(
                    color: _green,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (widget.driverIdentity != null) ...[
            Text(
              'Signed in as ${widget.driverIdentity}',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 6),
          ],
          const Text(
            'Illustrative demo orders · not live dispatch inventory',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            children: ['All', 'High Payout', 'Express Delivery', 'Cold Chain']
                .map(
                  (filter) => ChoiceChip(
                    label: Text(filter),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() {
                      _filter = filter;
                      if (!_matchesFilter(_orders[_selected], filter)) {
                        _selected = _orders.indexWhere(
                          (order) => _matchesFilter(order, filter),
                        );
                      }
                    }),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          ..._orders
              .asMap()
              .entries
              .where((entry) => _matchesFilter(entry.value, _filter))
              .map(
                (entry) => _OrderCard(
                  order: entry.value,
                  selected: entry.key == _selected,
                  onTap: () => setState(() => _selected = entry.key),
                ),
              ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SELECTED ORDER SUMMARY',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '${order.id} · ${order.pickup} → ${order.dropoff}',
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${order.amountLabel}  ·  ${order.distance}  ·  ${order.eta}',
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Semantics(
            button: true,
            enabled: false,
            label: 'Slide to confirm acceptance, unavailable until server authorization is implemented',
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.5,
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _deepBlue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'SLIDE TO ACCEPT · UNAVAILABLE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('preview-dispatch-verification'),
            onPressed: () {
              if (widget.onPreviewDispatch != null) {
                widget.onPreviewDispatch!(order);
                return;
              }
              showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Sample order preview'),
                  content: Text(
                    '${order.id} remains a demo order. No acceptance or dispatch was submitted.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.verified_user_outlined),
            label: const Text('Preview dispatch verification'),
          ),
          const SizedBox(height: 6),
          const Text(
            'Fresh biometric verification and server authorization are required before any real acceptance.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.selected,
    required this.onTap,
  });
  final DriverOrderSummary order;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? _blue : _line,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.pickup,
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  order.amountLabel,
                  style: const TextStyle(
                    color: _deepBlue,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Pickup → ${order.dropoff}',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              '${order.id}  ·  ${order.serviceType}  ·  ${order.distance}  ·  ${order.eta}',
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
    this.prominent = false,
  });
  final IconData icon;
  final String title, subtitle, action;
  final VoidCallback onTap;
  final bool prominent;
  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: prominent ? _blue : _line,
        width: prominent ? 1.5 : 1,
      ),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: _blue, size: 25),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(color: _muted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    action,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: prominent ? _blue : _muted,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: .7,
                    ),
                  ),
                ),
                const Spacer(),
                const Icon(Icons.arrow_forward, color: _blue, size: 18),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _blue,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.shield_outlined, color: Colors.white),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TRUST JUGGLER',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _ink,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const Text(
              'DRIVER & FLEET SECURITY',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _muted, fontSize: 10, letterSpacing: 1.1),
            ),
          ],
        ),
      ),
    ],
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: _ink,
      side: const BorderSide(color: _line),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
    ),
    child: Column(
      children: [
        Icon(icon, color: _blue, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10),
        ),
      ],
    ),
  );
}
