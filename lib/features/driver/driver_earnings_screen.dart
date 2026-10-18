import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/api/driver_finance_api.dart';

const _canvas = Color(0xFFFAF8FF);
const _ink = Color(0xFF131B2E);
const _muted = Color(0xFF434655);
const _blue = Color(0xFF2563EB);
const _line = Color(0xFFC3C6D7);

class DriverEarningsScreen extends StatefulWidget {
  const DriverEarningsScreen({this.repository, super.key});
  final DriverFinanceRepository? repository;

  @override
  State<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends State<DriverEarningsScreen> {
  late final DriverFinanceRepository _repository;
  late final DriverFinanceApi? _ownedApi;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  DriverFinanceSummary? _summary;
  List<DriverPayoutAccount> _accounts = const [];
  List<DriverPayoutRecord> _payouts = const [];
  List<DriverLedgerEntry> _ledger = const [];
  String? _pendingKey;

  @override
  void initState() {
    super.initState();
    if (widget.repository != null) {
      _repository = widget.repository!;
      _ownedApi = null;
    } else {
      final api = DriverFinanceApi(
        baseUrl: driverApiBaseUrl,
        auth: FirebaseAuth.instance,
      );
      _repository = api;
      _ownedApi = api;
    }
    _load();
  }

  @override
  void dispose() {
    _ownedApi?.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        _repository.getSummary(),
        _repository.getAccounts(),
        _repository.getPayouts(),
        _repository.getLedger(),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as DriverFinanceSummary;
        _accounts = results[1] as List<DriverPayoutAccount>;
        _payouts = (results[2] as DriverFinancePage<DriverPayoutRecord>).items;
        _ledger = (results[3] as DriverFinancePage<DriverLedgerEntry>).items;
      });
    } on DriverApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Earnings are unavailable. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setupAccount() async {
    final result = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _canvas,
      builder: (_) => const _PayoutAccountForm(),
    );
    if (result == null) return;
    setState(() => _busy = true);
    try {
      await _repository.setupAccount(result);
      await _load();
    } on DriverApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Payout account could not be saved. Retry after checking your connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestPayout() async {
    final summary = _summary;
    final eligibleAccounts = _accounts
        .where((a) => a.status == 'active')
        .toList();
    final account = eligibleAccounts.isEmpty ? null : eligibleAccounts.first;
    if (summary == null ||
        account == null ||
        summary.availablePaise < 100 ||
        _pendingKey != null) {
      return;
    }
    final amountPaise = await showDialog<int>(
      context: context,
      builder: (_) =>
          _PayoutAmountDialog(availablePaise: summary.availablePaise),
    );
    if (amountPaise == null || !mounted) return;
    final key = DriverFinanceApi.newIdempotencyKey();
    setState(() {
      _busy = true;
      _pendingKey = key;
    });
    try {
      final payout = await _repository.requestPayout(
        amountPaise: amountPaise,
        payoutAccountId: account.id,
        idempotencyKey: key,
      );
      if (!mounted) return;
      setState(() => _pendingKey = null);
      _showMessage('Request status: ${_statusLabel(payout.status)}.');
      await _load();
    } on DriverApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'payout_outcome_unknown') {
        _showMessage(
          'The request may have reached the server. Check its status before trying again.',
        );
      } else {
        setState(() => _pendingKey = null);
        _showMessage(error.message);
      }
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Request outcome could not be confirmed. Check its status before trying again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkPendingStatus() async {
    final key = _pendingKey;
    if (key == null) return;
    setState(() => _busy = true);
    try {
      final payout = await _repository.getPayoutByIdempotency(key);
      if (!mounted) return;
      setState(() => _pendingKey = null);
      _showMessage('Request status: ${_statusLabel(payout.status)}.');
      await _load();
    } on DriverApiException catch (error) {
      if (mounted) {
        _showMessage(
          error.statusCode == 404
              ? 'No request is visible yet. Keep this key and check again; do not create a second request.'
              : error.message,
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Could not check the request status. Try again later.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _canvas,
    appBar: AppBar(
      backgroundColor: _canvas,
      foregroundColor: _ink,
      title: const Text('Driver earnings'),
      actions: [
        IconButton(
          onPressed: _loading || _busy ? null : _load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
        ),
      ],
    ),
    body: SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorState(message: _error!, onRetry: _load)
          : _content(),
    ),
  );

  Widget _content() {
    final summary = _summary!;
    final activeAccount = _accounts.any((a) => a.status == 'active');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          const _InfoBanner(
            text: 'EARNINGS AND PAYOUT STATUS COME FROM THE SERVER',
          ),
          const SizedBox(height: 14),
          _BalanceCard(summary: summary),
          const SizedBox(height: 16),
          _sectionTitle('Payout destination'),
          if (_accounts.isEmpty)
            _EmptyCard(
              icon: Icons.account_balance_outlined,
              title: 'No payout account added',
              detail: 'Bank or VPA details are sent to the Trust Juggler server for RazorpayX setup. The app displays only masked destination details.',
            )
          else
            ..._accounts.map((account) => _AccountCard(account: account)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy || _accounts.any((a) => a.status != 'rejected')
                ? null
                : _setupAccount,
            icon: const Icon(Icons.add),
            label: Text(
              _accounts.isEmpty
                  ? 'Set up payout account'
                  : 'Payout account review pending',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed:
                _busy ||
                    _pendingKey != null ||
                    !activeAccount ||
                    summary.availablePaise < 100
                ? null
                : _requestPayout,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Request payout'),
          ),
          if (_pendingKey != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _checkPendingStatus,
              icon: const Icon(Icons.search),
              label: const Text('Check existing request status'),
            ),
          ],
          const SizedBox(height: 22),
          _sectionTitle('Payout history'),
          if (_payouts.isEmpty)
            const _EmptyCard(
              icon: Icons.receipt_long_outlined,
              title: 'No payout requests',
              detail:
                  'Requests and their server-reported status will appear here.',
            )
          else
            ..._payouts.map((payout) => _PayoutCard(payout: payout)),
          const SizedBox(height: 22),
          _sectionTitle('Earnings ledger'),
          if (_ledger.isEmpty)
            const _EmptyCard(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No credited earnings',
              detail: 'Delivery credits remain disabled until an approved pricing policy, managed route service, and reviewed evidence process are configured. Sample delivery values are not earnings.',
            )
          else
            ..._ledger.map((entry) => _LedgerCard(entry: entry)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: _ink,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _PayoutAccountForm extends StatefulWidget {
  const _PayoutAccountForm();
  @override
  State<_PayoutAccountForm> createState() => _PayoutAccountFormState();
}

class _PayoutAccountFormState extends State<_PayoutAccountForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _account = TextEditingController();
  final _ifsc = TextEditingController();
  final _vpa = TextEditingController();
  String _type = 'bank_account';

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _account.dispose();
    _ifsc.dispose();
    _vpa.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Set up payout account',
              style: TextStyle(
                color: _ink,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Details are sent over HTTPS to the server and RazorpayX. Trust Juggler stores provider references and masked details; it does not store your raw bank number or VPA.',
              style: TextStyle(color: _muted, height: 1.4),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'bank_account',
                  label: Text('Bank account'),
                ),
                ButtonSegment(value: 'vpa', label: Text('UPI VPA')),
              ],
              selected: {_type},
              onSelectionChanged: (values) =>
                  setState(() => _type = values.first),
            ),
            const SizedBox(height: 10),
            _field(_name, 'Account holder name', minLength: 2),
            _field(
              _email,
              'Email address',
              keyboardType: TextInputType.emailAddress,
              validator: (v) => v != null && v.contains('@')
                  ? null
                  : 'Enter an email address.',
            ),
            _field(
              _phone,
              'Phone number (+91XXXXXXXXXX)',
              keyboardType: TextInputType.phone,
              validator: (v) =>
                  v != null && RegExp(r'^\+91[6-9]\d{9}$').hasMatch(v)
                  ? null
                  : 'Enter an Indian mobile number with +91.',
            ),
            if (_type == 'bank_account') ...[
              _field(
                _account,
                'Bank account number',
                keyboardType: TextInputType.number,
                validator: (v) => v != null && RegExp(r'^\d{9,18}$').hasMatch(v)
                    ? null
                    : 'Enter 9–18 digits.',
              ),
              _field(
                _ifsc,
                'IFSC',
                validator: (v) =>
                    v != null &&
                        RegExp(r'^[A-Za-z]{4}0[A-Za-z0-9]{6}$').hasMatch(v)
                    ? null
                    : 'Enter a valid IFSC.',
              ),
            ] else
              _field(
                _vpa,
                'UPI VPA',
                validator: (v) =>
                    v != null &&
                        RegExp(r'^[A-Za-z0-9._-]{2,}@[A-Za-z0-9.-]{2,}$')
                            .hasMatch(v)
                    ? null
                    : 'Enter a valid VPA.',
              ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _submit,
              child: const Text('Submit for server review'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    int minLength = 1,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator:
          validator ??
          (value) => value != null && value.trim().length >= minLength
              ? null
              : 'Enter $label.',
    ),
  );

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final details = <String, Object?>{
      'type': _type,
      'name': _name.text.trim(),
      'email': _email.text.trim(),
      'phone': _phone.text.trim(),
      if (_type == 'bank_account') ...{
        'bankAccount': _account.text.trim(),
        'ifsc': _ifsc.text.trim().toUpperCase(),
      },
      if (_type == 'vpa') 'vpa': _vpa.text.trim(),
    };
    Navigator.of(context).pop(details);
  }
}

class _PayoutAmountDialog extends StatefulWidget {
  const _PayoutAmountDialog({required this.availablePaise});
  final int availablePaise;
  @override
  State<_PayoutAmountDialog> createState() => _PayoutAmountDialogState();
}

class _PayoutAmountDialogState extends State<_PayoutAmountDialog> {
  final _controller = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Request payout'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Available: ${_inr(widget.availablePaise)}'),
        TextField(
          controller: _controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Amount in INR',
            errorText: _error,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'The server reserves the requested amount and requires operator approval. Request status does not mean funds were received.',
          style: TextStyle(color: _muted, fontSize: 12),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Continue')),
    ],
  );
  void _submit() {
    final paise = _parseInr(_controller.text.trim());
    if (paise == null || paise < 100 || paise > widget.availablePaise) {
      setState(
        () => _error = 'Enter a valid amount up to your available balance.',
      );
      return;
    }
    Navigator.pop(context, paise);
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.summary});
  final DriverFinanceSummary summary;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AVAILABLE EARNINGS',
          style: TextStyle(
            color: _muted,
            fontSize: 11,
            letterSpacing: .8,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          _inr(summary.availablePaise),
          style: const TextStyle(
            color: _blue,
            fontSize: 32,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Divider(height: 20),
        _moneyRow('Reserved', summary.reservedPaise),
        _moneyRow('Processing', summary.processingPaise),
        _moneyRow('Paid', summary.paidPaise),
        _moneyRow('Failed', summary.failedPaise),
        _moneyRow('Released', summary.releasedPaise),
      ],
    ),
  );
}

Widget _moneyRow(String label, int value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(
    children: [
      Expanded(
        child: Text(label, style: const TextStyle(color: _muted)),
      ),
      Text(
        _inr(value),
        style: const TextStyle(color: _ink, fontWeight: FontWeight.w600),
      ),
    ],
  ),
);

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account});
  final DriverPayoutAccount account;
  @override
  Widget build(BuildContext context) => _SurfaceCard(
    child: Row(
      children: [
        const Icon(Icons.account_balance_outlined, color: _blue),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                account.maskedDestination,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${account.type.replaceAll('_', ' ')} · ${_statusLabel(account.status)}',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PayoutCard extends StatelessWidget {
  const _PayoutCard({required this.payout});
  final DriverPayoutRecord payout;
  @override
  Widget build(BuildContext context) => _SurfaceCard(
    child: Row(
      children: [
        const Icon(Icons.receipt_long_outlined, color: _blue),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _inr(payout.amountPaise),
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${_statusLabel(payout.status)} · ${payout.id}',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
              if (payout.utr != null)
                Text(
                  'UTR ${payout.utr}',
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _LedgerCard extends StatelessWidget {
  const _LedgerCard({required this.entry});
  final DriverLedgerEntry entry;
  @override
  Widget build(BuildContext context) => _SurfaceCard(
    child: Row(
      children: [
        Icon(
          entry.amountPaise < 0 ? Icons.south_west : Icons.north_east,
          color: _blue,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${entry.type.replaceAll('_', ' ')} · ${entry.referenceId}',
            style: const TextStyle(color: _ink),
          ),
        ),
        Text(
          '${entry.amountPaise < 0 ? '−' : '+'}${_inr(entry.amountPaise.abs())}',
          style: const TextStyle(color: _ink, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => _SurfaceCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _muted),
        const SizedBox(width: 10),
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
              const SizedBox(height: 3),
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, color: _blue, size: 44),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _ink),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFE9EEFF),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: _ink,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );
}

String _inr(int paise) =>
    '₹${paise ~/ 100}.${(paise % 100).abs().toString().padLeft(2, '0')}';
int? _parseInr(String value) {
  if (!RegExp(r'^\d{1,8}(\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  final whole = int.tryParse(parts[0]);
  if (whole == null || whole > 10000) return null;
  final fraction = parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0'));
  final amount = whole * 100 + fraction;
  return amount <= 1000000 ? amount : null;
}

String _statusLabel(String value) => value
    .replaceAll('_', ' ')
    .replaceFirstMapped(RegExp(r'^.'), (m) => m[0]!.toUpperCase());
