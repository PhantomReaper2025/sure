import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/account.dart' as upstream;
import '../theme/sure_colors.dart';
import '../widgets/account_card.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_card.dart';
import 'local_store.dart';
import 'offline_forms.dart';

String formatMoney(int cents, String currency) {
  return NumberFormat.simpleCurrency(name: currency).format(cents / 100);
}

String formatDate(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  return DateFormat.yMMMd().format(parsed);
}

/// Root screen of the offline build: no server, no login. Two tabs —
/// accounts (balances computed locally) and transactions.
class OfflineHomeScreen extends StatefulWidget {
  const OfflineHomeScreen({super.key});

  @override
  State<OfflineHomeScreen> createState() => _OfflineHomeScreenState();
}

class _OfflineHomeScreenState extends State<OfflineHomeScreen> {
  int _tab = 0;
  final LocalStore _store = LocalStore.instance;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget local load. On platforms without the sqflite plugin
    // (e.g. widget tests pumping the full app) the database is unavailable;
    // swallow the failure and mark the store loaded so the empty offline
    // UI renders instead of surfacing an unhandled async error.
    _store.load().catchError((Object _) {
      _store.loaded = true;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Sure'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    'Offline',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ),
            ],
          ),
          body: !_store.loaded
              ? const Center(child: CircularProgressIndicator())
              : _tab == 0
                  ? _AccountsTab(store: _store)
                  : _TransactionsTab(store: _store),
          floatingActionButton: !_store.loaded
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _onAdd(context),
                  icon: const Icon(Icons.add),
                  label: Text(_tab == 0 ? 'Account' : 'Transaction'),
                ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet),
                label: 'Accounts',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'Transactions',
              ),
            ],
          ),
        );
      },
    );
  }

  void _onAdd(BuildContext context) {
    if (_tab == 0) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AccountFormScreen()),
      );
      return;
    }
    if (_store.accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add an account first.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TransactionFormScreen()),
    );
  }
}

class _AccountsTab extends StatelessWidget {
  final LocalStore store;

  const _AccountsTab({required this.store});

  @override
  Widget build(BuildContext context) {
    if (store.accounts.isEmpty) {
      return _EmptyState(
        message: 'No accounts yet.\nAdd one to start tracking your money — '
            'everything stays on this device.',
        buttonLabel: 'Add account',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AccountFormScreen()),
        ),
      );
    }
    final netWorth = store.netWorthByCurrency();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SureCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Net worth',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              for (final entry in netWorth.entries)
                Text(
                  formatMoney(entry.value, entry.key),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final account in store.accounts) ...[
          AccountCard(
            account: upstream.Account(
              id: account.id,
              name: account.name,
              balance:
                  (store.balanceCents(account.id) / 100).toStringAsFixed(2),
              currency: account.currency,
              classification:
                  account.isLiability ? 'liability' : 'asset',
              accountType: account.type,
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AccountDetailScreen(accountId: account.id),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _TransactionsTab extends StatelessWidget {
  final LocalStore store;

  const _TransactionsTab({required this.store});

  @override
  Widget build(BuildContext context) {
    if (store.transactions.isEmpty) {
      return const _EmptyState(
        message: 'No transactions yet.\nAdd an income or expense and your '
            'account balances update instantly.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: store.transactions.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TransactionRow(store: store, txn: store.transactions[i]),
      ),
    );
  }
}

class TransactionRow extends StatelessWidget {
  final LocalStore store;
  final LocalTxn txn;

  const TransactionRow({super.key, required this.store, required this.txn});

  @override
  Widget build(BuildContext context) {
    final account = store.accounts.where((a) => a.id == txn.accountId);
    final accountName = account.isEmpty ? '' : account.first.name;
    final currency = account.isEmpty ? 'USD' : account.first.currency;
    final palette = SureColors.of(context).palette;
    final amountColor = txn.isIncome ? palette.success : palette.destructive;
    return SureCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TransactionFormScreen(existing: txn),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  txn.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  [formatDate(txn.date), accountName]
                      .where((s) => s.isNotEmpty)
                      .join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text(
            '${txn.isIncome ? '+' : '−'}${formatMoney(txn.amountCents, currency)}',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: amountColor),
          ),
        ],
      ),
    );
  }
}

class AccountDetailScreen extends StatelessWidget {
  final String accountId;

  const AccountDetailScreen({super.key, required this.accountId});

  @override
  Widget build(BuildContext context) {
    final store = LocalStore.instance;
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final matches = store.accounts.where((a) => a.id == accountId);
        if (matches.isEmpty) {
          // Account was deleted while this screen was open.
          return const Scaffold(body: SizedBox.shrink());
        }
        final account = matches.first;
        final balance = store.balanceCents(account.id);
        final txns = store.transactionsFor(account.id);
        return Scaffold(
          appBar: AppBar(title: Text(account.name)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SureCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      accountTypeLabels[account.type] ?? account.type,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      formatMoney(balance, account.currency),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Opening balance '
                      '${formatMoney(account.openingCents, account.currency)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SureButton(
                      label: 'Add transaction',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TransactionFormScreen(
                            presetAccountId: account.id,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SureButton(
                      label: 'Edit account',
                      variant: SureButtonVariant.secondary,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              AccountFormScreen(existing: account),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SureButton(
                label: 'Delete account',
                variant: SureButtonVariant.destructive,
                fullWidth: true,
                onPressed: () => _confirmDelete(context, account),
              ),
              const SizedBox(height: 24),
              Text(
                'Transactions',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (txns.isEmpty)
                Text(
                  'No transactions for this account yet.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              for (final txn in txns) ...[
                TransactionRow(store: store, txn: txn),
                const SizedBox(height: 12),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    LocalAccount account,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: Text(
          '“${account.name}” and all its transactions will be permanently '
          'deleted.',
        ),
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
    await LocalStore.instance.deleteAccount(account.id);
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  const _EmptyState({required this.message, this.buttonLabel, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (buttonLabel != null && onPressed != null) ...[
              const SizedBox(height: 20),
              SureButton(label: buttonLabel!, onPressed: onPressed),
            ],
          ],
        ),
      ),
    );
  }
}
