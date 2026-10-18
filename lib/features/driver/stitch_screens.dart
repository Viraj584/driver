import 'package:flutter/material.dart';

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
    super.key,
  });

  final VoidCallback onDriverAuth;
  final VoidCallback onOnboarding;
  final VoidCallback onFleetAccess;
  final VoidCallback onRiskEngine;

  @override
  State<TrustJugglerRoleSelector> createState() =>
      _TrustJugglerRoleSelectorState();
}

class _TrustJugglerRoleSelectorState extends State<TrustJugglerRoleSelector> {
  int _selectedDestination = 0;

  void _selectDestination(int index) {
    setState(() => _selectedDestination = index);
    switch (index) {
      case 1:
        widget.onDriverAuth();
        break;
      case 2:
        widget.onOnboarding();
        break;
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
                  action: 'CONTINUE AS DRIVER',
                  onTap: widget.onDriverAuth,
                  prominent: true,
                ),
                const SizedBox(height: 12),
                _RoleCard(
                  icon: Icons.local_shipping_outlined,
                  title: 'Fleet Dispatch',
                  subtitle:
                      'Fleet access requires an authorized operator account.',
                  action: 'FLEET ACCESS',
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
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.route_outlined),
          label: 'Deliveries',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Account',
        ),
      ],
    ),
  );
}

class FleetAccessUnavailableScreen extends StatelessWidget {
  const FleetAccessUnavailableScreen({super.key});

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
          children: const [
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
            Text(
              'This app has no fleet-operator sign-in or administrator provisioning configured. Selecting Fleet Dispatch does not grant access.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, height: 1.5),
            ),
          ],
        ),
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
  const DriverDeliveryPoolScreen({this.onPreviewDispatch, super.key});

  final ValueChanged<DriverOrderSummary>? onPreviewDispatch;

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
        'High payout' => order.tags.toLowerCase().contains('high payout'),
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
          const Text(
            'Illustrative demo orders · not live dispatch inventory',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            children: ['All', 'High payout', 'Express Delivery', 'Cold Chain']
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
            onPressed: widget.onPreviewDispatch == null
                ? null
                : () => widget.onPreviewDispatch!(order),
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
