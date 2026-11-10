import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/sure_colors.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_segmented_control.dart';
import '../widgets/sure_text_field.dart';
import 'local_store.dart';

/// Parses a user-entered amount into cents. Returns null when unparseable.
/// [allowNegative] is for opening balances (e.g. a credit-card balance owed).
int? parseAmountToCents(String raw, {bool allowNegative = false}) {
  var s = raw.trim().replaceAll(RegExp(r'[^0-9.,-]'), '');
  if (s.isEmpty) return null;
  if (s.contains(',') && !s.contains('.')) s = s.replaceAll(',', '.');
  s = s.replaceAll(',', '');
  final value = double.tryParse(s);
  if (value == null) return null;
  if (!allowNegative && value <= 0) return null;
  return (value * 100).round();
}

String centsToInput(int cents) => (cents / 100).toStringAsFixed(2);

const accountTypeLabels = <String, String>{
  'depository': 'Bank Account',
  'credit_card': 'Credit Card',
  'investment': 'Investment',
  'loan': 'Loan',
  'crypto': 'Crypto',
  'property': 'Property',
  'vehicle': 'Vehicle',
  'other_asset': 'Other Asset',
  'other_liability': 'Other Liability',
};

class AccountFormScreen extends StatefulWidget {
  final LocalAccount? existing;

  const AccountFormScreen({super.key, this.existing});

  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  late final TextEditingController _name;
  late final TextEditingController _currency;
  late final TextEditingController _opening;
  late String _type;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _currency = TextEditingController(text: e?.currency ?? 'USD');
    _opening = TextEditingController(
      text: e != null ? centsToInput(e.openingCents) : '',
    );
    _type = e?.type ?? 'depository';
  }

  @override
  void dispose() {
    _name.dispose();
    _currency.dispose();
    _opening.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final currency = _currency.text.trim().toUpperCase();
    final opening = _opening.text.trim().isEmpty
        ? 0
        : parseAmountToCents(_opening.text, allowNegative: true);
    if (name.isEmpty) {
      setState(() => _error = 'Give the account a name.');
      return;
    }
    if (currency.length != 3) {
      setState(() => _error = 'Currency must be a 3-letter code, e.g. USD.');
      return;
    }
    if (opening == null) {
      setState(() => _error = 'Opening balance is not a valid amount.');
      return;
    }
    final store = LocalStore.instance;
    final e = widget.existing;
    if (e == null) {
      await store.addAccount(
        name: name,
        type: _type,
        currency: currency,
        openingCents: opening,
      );
    } else {
      await store.updateAccount(
        e.copyWith(
          name: name,
          type: _type,
          currency: currency,
          openingCents: opening,
        ),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit account' : 'Add account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SureTextField(
            controller: _name,
            label: 'Name',
            hint: 'e.g. Main bank account',
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: accountTypeLabels.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 16),
          SureTextField(
            controller: _currency,
            label: 'Currency',
            hint: 'USD',
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 16),
          SureTextField(
            controller: _opening,
            label: 'Opening balance',
            hint: '0.00',
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(
                color: SureColors.of(context).palette.destructive,
              ),
            ),
          ],
          const SizedBox(height: 24),
          SureButton(
            label: isEdit ? 'Save changes' : 'Add account',
            onPressed: _save,
            fullWidth: true,
          ),
        ],
      ),
    );
  }
}

class TransactionFormScreen extends StatefulWidget {
  final LocalTxn? existing;
  final String? presetAccountId;

  const TransactionFormScreen({super.key, this.existing, this.presetAccountId});

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late String _nature;
  late DateTime _date;
  String? _accountId;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _amount = TextEditingController(
      text: e != null ? centsToInput(e.amountCents) : '',
    );
    _nature = e?.nature ?? 'expense';
    _date = e != null
        ? DateTime.parse(e.date)
        : DateTime.now();
    _accountId = e?.accountId ??
        widget.presetAccountId ??
        (LocalStore.instance.accounts.isNotEmpty
            ? LocalStore.instance.accounts.first.id
            : null);
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  String get _dateIso => DateFormat('yyyy-MM-dd').format(_date);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final amount = parseAmountToCents(_amount.text);
    if (name.isEmpty) {
      setState(() => _error = 'Give the transaction a name.');
      return;
    }
    if (amount == null) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    if (_accountId == null) {
      setState(() => _error = 'Add an account first.');
      return;
    }
    final store = LocalStore.instance;
    final e = widget.existing;
    if (e == null) {
      await store.addTxn(
        accountId: _accountId!,
        name: name,
        amountCents: amount,
        nature: _nature,
        date: _dateIso,
      );
    } else {
      await store.updateTxn(
        e.copyWith(
          accountId: _accountId,
          name: name,
          amountCents: amount,
          nature: _nature,
          date: _dateIso,
        ),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: Text('“${e.name}” will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await LocalStore.instance.deleteTxn(e.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final accounts = LocalStore.instance.accounts;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit transaction' : 'Add transaction'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SureSegmentedControl<String>(
            segments: const [
              SureSegment(value: 'expense', label: 'Expense'),
              SureSegment(value: 'income', label: 'Income'),
            ],
            selected: _nature,
            onChanged: (v) => setState(() => _nature = v),
          ),
          const SizedBox(height: 16),
          SureTextField(
            controller: _name,
            label: 'Name',
            hint: 'e.g. Groceries',
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          SureTextField(
            controller: _amount,
            label: 'Amount',
            hint: '0.00',
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _accountId,
            decoration: const InputDecoration(labelText: 'Account'),
            items: accounts
                .map(
                  (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
                )
                .toList(),
            onChanged: (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: 16),
          SureTextField(
            label: 'Date',
            hint: DateFormat.yMMMd().format(_date),
            readOnly: true,
            onTap: _pickDate,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(
                color: SureColors.of(context).palette.destructive,
              ),
            ),
          ],
          const SizedBox(height: 24),
          SureButton(
            label: isEdit ? 'Save changes' : 'Add transaction',
            onPressed: _save,
            fullWidth: true,
          ),
          if (isEdit) ...[
            const SizedBox(height: 12),
            SureButton(
              label: 'Delete transaction',
              onPressed: _delete,
              variant: SureButtonVariant.destructive,
              fullWidth: true,
            ),
          ],
        ],
      ),
    );
  }
}
