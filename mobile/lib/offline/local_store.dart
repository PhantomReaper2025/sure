import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Local-only data layer for the offline build.
///
/// All data lives in a dedicated sqflite database (`sure_local_tracker.db`),
/// separate from the upstream server-cache database, and never leaves the
/// device. Balances are computed from the opening balance plus transactions:
/// income adds, expense subtracts.
class LocalAccount {
  final String id;
  final String name;

  /// Upstream account-type vocabulary (depository, credit_card, investment,
  /// loan, crypto, other_asset, other_liability) so upstream widgets such as
  /// AccountCard render the right icon/label.
  final String type;
  final String currency;
  final int openingCents;

  const LocalAccount({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
    required this.openingCents,
  });

  bool get isLiability =>
      type == 'credit_card' || type == 'loan' || type == 'other_liability';

  LocalAccount copyWith({
    String? name,
    String? type,
    String? currency,
    int? openingCents,
  }) {
    return LocalAccount(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      currency: currency ?? this.currency,
      openingCents: openingCents ?? this.openingCents,
    );
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'type': type,
        'currency': currency,
        'opening_cents': openingCents,
      };

  factory LocalAccount.fromRow(Map<String, Object?> row) {
    return LocalAccount(
      id: row['id'] as String,
      name: row['name'] as String,
      type: row['type'] as String,
      currency: row['currency'] as String,
      openingCents: (row['opening_cents'] as num).toInt(),
    );
  }
}

class LocalTxn {
  final String id;
  final String accountId;
  final String name;

  /// Always positive; direction comes from [nature].
  final int amountCents;

  /// 'income' or 'expense' (upstream vocabulary).
  final String nature;

  /// ISO date, yyyy-MM-dd.
  final String date;

  const LocalTxn({
    required this.id,
    required this.accountId,
    required this.name,
    required this.amountCents,
    required this.nature,
    required this.date,
  });

  bool get isIncome => nature == 'income';

  int get signedCents => isIncome ? amountCents : -amountCents;

  LocalTxn copyWith({
    String? accountId,
    String? name,
    int? amountCents,
    String? nature,
    String? date,
  }) {
    return LocalTxn(
      id: id,
      accountId: accountId ?? this.accountId,
      name: name ?? this.name,
      amountCents: amountCents ?? this.amountCents,
      nature: nature ?? this.nature,
      date: date ?? this.date,
    );
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'account_id': accountId,
        'name': name,
        'amount_cents': amountCents,
        'nature': nature,
        'date': date,
      };

  factory LocalTxn.fromRow(Map<String, Object?> row) {
    return LocalTxn(
      id: row['id'] as String,
      accountId: row['account_id'] as String,
      name: row['name'] as String,
      amountCents: (row['amount_cents'] as num).toInt(),
      nature: row['nature'] as String,
      date: row['date'] as String,
    );
  }
}

class LocalStore extends ChangeNotifier {
  LocalStore._();
  static final LocalStore instance = LocalStore._();

  static const _uuid = Uuid();
  Database? _db;
  Future<void>? _loading;

  List<LocalAccount> accounts = [];
  List<LocalTxn> transactions = [];
  bool loaded = false;

  Future<Database> _database() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'sure_local_tracker.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE local_accounts(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            currency TEXT NOT NULL,
            opening_cents INTEGER NOT NULL DEFAULT 0
          )''');
        await db.execute('''
          CREATE TABLE local_transactions(
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL,
            name TEXT NOT NULL,
            amount_cents INTEGER NOT NULL,
            nature TEXT NOT NULL,
            date TEXT NOT NULL
          )''');
      },
    );
    return _db!;
  }

  Future<void> load() {
    return _loading ??= _load();
  }

  Future<void> _load() async {
    final db = await _database();
    final accountRows = await db.query('local_accounts', orderBy: 'name ASC');
    final txnRows = await db.query(
      'local_transactions',
      orderBy: 'date DESC, rowid DESC',
    );
    accounts = accountRows.map(LocalAccount.fromRow).toList();
    transactions = txnRows.map(LocalTxn.fromRow).toList();
    loaded = true;
    notifyListeners();
  }

  int balanceCents(String accountId) {
    final account = accounts.firstWhere((a) => a.id == accountId);
    var cents = account.openingCents;
    for (final txn in transactions) {
      if (txn.accountId == accountId) cents += txn.signedCents;
    }
    return cents;
  }

  /// Net worth summed per currency (no FX conversion in the offline build).
  Map<String, int> netWorthByCurrency() {
    final totals = <String, int>{};
    for (final account in accounts) {
      totals[account.currency] =
          (totals[account.currency] ?? 0) + balanceCents(account.id);
    }
    return totals;
  }

  List<LocalTxn> transactionsFor(String accountId) =>
      transactions.where((t) => t.accountId == accountId).toList();

  Future<LocalAccount> addAccount({
    required String name,
    required String type,
    required String currency,
    required int openingCents,
  }) async {
    final account = LocalAccount(
      id: _uuid.v4(),
      name: name,
      type: type,
      currency: currency,
      openingCents: openingCents,
    );
    final db = await _database();
    await db.insert('local_accounts', account.toRow());
    accounts = [...accounts, account]
      ..sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
    return account;
  }

  Future<void> updateAccount(LocalAccount account) async {
    final db = await _database();
    await db.update(
      'local_accounts',
      account.toRow(),
      where: 'id = ?',
      whereArgs: [account.id],
    );
    accounts = accounts
        .map((a) => a.id == account.id ? account : a)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
  }

  Future<void> deleteAccount(String accountId) async {
    final db = await _database();
    await db.delete(
      'local_transactions',
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
    await db.delete(
      'local_accounts',
      where: 'id = ?',
      whereArgs: [accountId],
    );
    accounts = accounts.where((a) => a.id != accountId).toList();
    transactions = transactions.where((t) => t.accountId != accountId).toList();
    notifyListeners();
  }

  Future<LocalTxn> addTxn({
    required String accountId,
    required String name,
    required int amountCents,
    required String nature,
    required String date,
  }) async {
    final txn = LocalTxn(
      id: _uuid.v4(),
      accountId: accountId,
      name: name,
      amountCents: amountCents,
      nature: nature,
      date: date,
    );
    final db = await _database();
    await db.insert('local_transactions', txn.toRow());
    transactions = [txn, ...transactions];
    notifyListeners();
    return txn;
  }

  Future<void> updateTxn(LocalTxn txn) async {
    final db = await _database();
    await db.update(
      'local_transactions',
      txn.toRow(),
      where: 'id = ?',
      whereArgs: [txn.id],
    );
    transactions = transactions.map((t) => t.id == txn.id ? txn : t).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
  }

  Future<void> deleteTxn(String txnId) async {
    final db = await _database();
    await db.delete('local_transactions', where: 'id = ?', whereArgs: [txnId]);
    transactions = transactions.where((t) => t.id != txnId).toList();
    notifyListeners();
  }
}
