import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/json.dart';
import 'finance_models.dart';

/// How much time a money screen looks at.
enum PeriodKind { all, day, month, range }

DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// A period of whole calendar days on this phone (or all time) that the Collected,
/// Costs, Profit and Budget screens are filtered to. The days are sent to the
/// server as the exact moments they begin and end here, so a payment made late in
/// the evening stays on its own day.
@immutable
class MoneyPeriod {
  const MoneyPeriod._(this.kind, this.start, this.end);

  final PeriodKind kind;

  /// First day (inclusive), as a local date. Null for all time.
  final DateTime? start;

  /// Last day (inclusive), as a local date. Null for all time.
  final DateTime? end;

  static const all = MoneyPeriod._(PeriodKind.all, null, null);

  factory MoneyPeriod.day(DateTime d) {
    final x = _dayOf(d);
    return MoneyPeriod._(PeriodKind.day, x, x);
  }

  factory MoneyPeriod.month(DateTime d) => MoneyPeriod._(
    PeriodKind.month,
    DateTime(d.year, d.month),
    // Day 0 of the next month is the last day of this one.
    DateTime(d.year, d.month + 1, 0),
  );

  factory MoneyPeriod.range(DateTime a, DateTime b) {
    final x = _dayOf(a);
    final y = _dayOf(b);
    return x.isAfter(y)
        ? MoneyPeriod._(PeriodKind.range, y, x)
        : MoneyPeriod._(PeriodKind.range, x, y);
  }

  /// The first moment of the period, for `from` (inclusive).
  String? get fromParam => start?.toUtc().toIso8601String();

  /// The start of the day after the period, for `to` (exclusive).
  String? get toParam {
    final e = end;
    return e == null
        ? null
        : DateTime(e.year, e.month, e.day + 1).toUtc().toIso8601String();
  }

  /// The period one step earlier or later (a day or a month); unchanged for all
  /// time and for a range.
  MoneyPeriod shifted(int steps) {
    final s = start;
    if (s == null) return this;
    return switch (kind) {
      PeriodKind.day => MoneyPeriod.day(
        DateTime(s.year, s.month, s.day + steps),
      ),
      PeriodKind.month => MoneyPeriod.month(DateTime(s.year, s.month + steps)),
      _ => this,
    };
  }

  /// Whether a later day or month exists that is not in the future.
  bool canGoLater(DateTime now) {
    final s = start;
    if (s == null) return false;
    return switch (kind) {
      PeriodKind.day => s.isBefore(_dayOf(now)),
      PeriodKind.month => s.isBefore(DateTime(now.year, now.month)),
      _ => false,
    };
  }

  String get label {
    final s = start;
    final e = end;
    if (s == null || e == null) return 'All time';
    switch (kind) {
      case PeriodKind.day:
        return DateFormat('EEE d MMM y').format(s);
      case PeriodKind.month:
        return DateFormat('MMMM y').format(s);
      case PeriodKind.range:
      case PeriodKind.all:
        return s.year == e.year
            ? '${DateFormat('d MMM').format(s)} – ${DateFormat('d MMM y').format(e)}'
            : '${DateFormat('d MMM y').format(s)} – ${DateFormat('d MMM y').format(e)}';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is MoneyPeriod &&
      other.kind == kind &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);
}

/// What to work money out for: a period and, optionally, one project. A family
/// key, so it compares by value.
@immutable
class MoneyQuery {
  const MoneyQuery(this.period, [this.projectId]);

  final MoneyPeriod period;
  final String? projectId;

  MoneyQuery withProject(String? id) => MoneyQuery(period, id);
  MoneyQuery withPeriod(MoneyPeriod p) => MoneyQuery(p, projectId);

  /// The query string. The offset lets the server put labour on the right local
  /// day.
  Map<String, Object?> toQuery() => {
    'from': period.fromParam,
    'to': period.toParam,
    'projectId': projectId,
    'utcOffsetMinutes':
        (period.start ?? DateTime.now()).timeZoneOffset.inMinutes,
  };

  @override
  bool operator ==(Object other) =>
      other is MoneyQuery &&
      other.period == period &&
      other.projectId == projectId;

  @override
  int get hashCode => Object.hash(period, projectId);
}

/// The kinds of cost the server lists.
enum CostSource {
  materials('materials', 'Materials used'),
  recorded('recorded', 'Recorded costs'),
  labour('labour', 'Labour'),
  purchases('purchases', 'Purchases');

  const CostSource(this.api, this.label);
  final String api;
  final String label;
}

@immutable
class CostsKey {
  const CostsKey(this.query, this.source);
  final MoneyQuery query;
  final CostSource source;

  @override
  bool operator ==(Object other) =>
      other is CostsKey && other.query == query && other.source == source;

  @override
  int get hashCode => Object.hash(query, source);
}

@immutable
class CategoryCost {
  const CategoryCost({
    required this.categoryId,
    required this.name,
    required this.amount,
  });
  final String categoryId;
  final String name;
  final double amount;
}

/// What the costs of a period are made of. Material bought for a project
/// ([purchases]) is listed but not part of [total]: it is counted when it is used.
@immutable
class CostBreakdown {
  const CostBreakdown({
    required this.total,
    required this.materialsUsed,
    required this.recorded,
    required this.labour,
    required this.labourHours,
    required this.purchases,
    required this.byCategory,
  });

  final double total;
  final double materialsUsed;
  final double recorded;
  final double labour;
  final double labourHours;
  final double purchases;
  final List<CategoryCost> byCategory;

  static CostBreakdown parse(Object? raw) {
    final m = J.map(raw);
    return CostBreakdown(
      total: J.number(m['total']) ?? 0,
      materialsUsed: J.number(m['materialsUsed']) ?? 0,
      recorded: J.number(m['recorded']) ?? 0,
      labour: J.number(m['labour']) ?? 0,
      labourHours: J.number(m['labourHours']) ?? 0,
      purchases: J.number(m['purchases']) ?? 0,
      byCategory: [
        for (final c in J.maps(m['byCategory']))
          if (J.str(c['categoryId']) != null)
            CategoryCost(
              categoryId: J.str(c['categoryId'])!,
              name: J.strOr(c['name'], 'Category'),
              amount: J.number(c['amount']) ?? 0,
            ),
      ],
    );
  }
}

/// Budgets added up. They are not dated, so a period never changes them.
@immutable
class BudgetTotals {
  const BudgetTotals({
    required this.planned,
    required this.spent,
    required this.left,
    required this.percentUsed,
    required this.overLines,
    required this.warningLines,
  });
  final double planned;
  final double spent;

  /// Planned minus spent; negative when over.
  final double left;
  final int percentUsed;
  final int overLines;
  final int warningLines;

  bool get isOver => left < 0 && planned > 0;

  static BudgetTotals parse(Object? raw) {
    final m = J.map(raw);
    return BudgetTotals(
      planned: J.number(m['planned']) ?? 0,
      spent: J.number(m['spent']) ?? 0,
      left: J.number(m['left']) ?? 0,
      percentUsed: J.integer(m['percentUsed']) ?? 0,
      overLines: J.integer(m['overLines']) ?? 0,
      warningLines: J.integer(m['warningLines']) ?? 0,
    );
  }
}

/// One project's money for a period, with its budget as it stands.
@immutable
class ProjectMoney {
  const ProjectMoney({
    required this.projectId,
    required this.name,
    required this.collected,
    required this.costs,
    required this.profit,
    required this.planned,
    required this.spent,
    required this.left,
    required this.percentUsed,
    required this.overLines,
    required this.warningLines,
    required this.status,
    this.code,
  });

  /// Null for money that is not tied to a project.
  final String? projectId;
  final String name;
  final String? code;
  final double collected;
  final double costs;
  final double profit;
  final double planned;
  final double spent;
  final double left;
  final int percentUsed;
  final int overLines;
  final int warningLines;

  /// `ON_TRACK`, `WARNING`, `OVER_BUDGET` or `NO_BUDGET`.
  final String status;

  bool get hasBudget => status != 'NO_BUDGET';
  bool get isOver => status == BudgetStatus.overBudget;
  bool get isWarning => status == BudgetStatus.warning;
  bool get hasMoney => collected != 0 || costs != 0;

  static ProjectMoney? tryParse(Map<String, dynamic> m) {
    final name = J.str(m['name']);
    if (name == null) return null;
    return ProjectMoney(
      projectId: J.str(m['projectId']),
      name: name,
      code: J.str(m['code']),
      collected: J.number(m['collected']) ?? 0,
      costs: J.number(m['costs']) ?? 0,
      profit: J.number(m['profit']) ?? 0,
      planned: J.number(m['planned']) ?? 0,
      spent: J.number(m['spent']) ?? 0,
      left: J.number(m['left']) ?? 0,
      percentUsed: J.integer(m['percentUsed']) ?? 0,
      overLines: J.integer(m['overLines']) ?? 0,
      warningLines: J.integer(m['warningLines']) ?? 0,
      status: J.strOr(m['status'], 'NO_BUDGET'),
    );
  }
}

/// `GET /financials/overview`: the company's (or one project's) money for a period.
@immutable
class MoneyOverview {
  const MoneyOverview({
    required this.collected,
    required this.costs,
    required this.profit,
    required this.budget,
    required this.projects,
  });

  final double collected;
  final CostBreakdown costs;
  final double profit;
  final BudgetTotals budget;
  final List<ProjectMoney> projects;

  /// Profit as a share of what was collected; null when nothing was collected.
  int? get marginPercent =>
      collected > 0 ? ((profit / collected) * 100).round() : null;

  static MoneyOverview parse(Object? raw) {
    final m = J.map(raw);
    return MoneyOverview(
      collected: J.number(m['collected']) ?? 0,
      costs: CostBreakdown.parse(m['costs']),
      profit: J.number(m['profit']) ?? 0,
      budget: BudgetTotals.parse(m['budget']),
      projects: J
          .maps(m['projects'])
          .map(ProjectMoney.tryParse)
          .whereType<ProjectMoney>()
          .toList(),
    );
  }
}

/// One payment that makes up the money collected.
@immutable
class CollectionEntry {
  const CollectionEntry({
    required this.id,
    required this.amount,
    required this.method,
    required this.invoiceNumber,
    this.paidAt,
    this.reference,
    this.notes,
    this.invoiceId,
    this.clientName,
    this.projectName,
  });

  final String id;
  final double amount;
  final String method;
  final DateTime? paidAt;
  final String? reference;
  final String? notes;
  final String? invoiceId;
  final String invoiceNumber;
  final String? clientName;
  final String? projectName;

  String get methodLabel => ManualPayment.label(method);

  /// The server's own reference for a payment typed in by hand is not worth
  /// showing.
  String? get shownReference =>
      reference == null || reference!.startsWith('MANUAL-') ? null : reference;

  static CollectionEntry? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    if (id == null) return null;
    final invoice = J.map(m['invoice']);
    return CollectionEntry(
      id: id,
      amount: J.number(m['amount']) ?? 0,
      method: J.strOr(m['method'], 'OTHER'),
      paidAt: J.date(m['paidAt']),
      reference: J.str(m['reference']),
      notes: J.str(m['notes']),
      invoiceId: J.str(invoice['id']),
      invoiceNumber: J.strOr(invoice['number'], 'Invoice'),
      clientName: J.str(invoice['clientName']),
      projectName: J.str(J.map(m['project'])['name']),
    );
  }
}

/// One row behind a kind of cost. A labour row is a day's labour on a project
/// added up: it never says who worked or what they are paid.
@immutable
class CostEntry {
  const CostEntry({
    required this.id,
    required this.source,
    required this.description,
    required this.amount,
    this.date,
    this.projectName,
    this.categoryName,
    this.vendor,
    this.reference,
    this.notes,
    this.receiptUrl,
    this.quantity,
    this.unit,
    this.unitCost,
    this.hours,
    this.people,
  });

  final String id;
  final CostSource source;
  final String description;
  final double amount;
  final DateTime? date;
  final String? projectName;
  final String? categoryName;
  final String? vendor;
  final String? reference;
  final String? notes;
  final String? receiptUrl;
  final double? quantity;
  final String? unit;
  final double? unitCost;
  final double? hours;
  final int? people;

  static CostEntry? tryParse(Object? raw, CostSource source) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    if (id == null) return null;
    final receipt = J.str(m['receiptUrl']);
    final isLink =
        receipt != null &&
        (receipt.startsWith('http://') || receipt.startsWith('https://'));
    return CostEntry(
      id: id,
      source: source,
      description: J.strOr(m['description'], source.label),
      amount: J.number(m['amount']) ?? 0,
      date: J.date(m['date']),
      projectName: J.str(J.map(m['project'])['name']),
      categoryName: J.str(J.map(m['category'])['name']),
      vendor: J.str(m['vendor']),
      reference: J.str(m['reference']),
      notes: J.str(m['notes']),
      receiptUrl: isLink ? receipt : null,
      quantity: J.number(m['quantity']),
      unit: J.str(m['unit']),
      unitCost: J.number(m['unitCost']),
      hours: J.number(m['hours']),
      people: J.integer(m['people']),
    );
  }
}

// ---- one budget line's items ------------------------------------------------

/// Material used on the project (a Materials line).
@immutable
class LedgerUsage {
  const LedgerUsage({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unitCost,
    required this.amount,
    required this.date,
    this.unit,
    this.notes,
  });
  final String id;
  final String name;
  final double quantity;
  final double unitCost;
  final double amount;
  final DateTime date;
  final String? unit;
  final String? notes;
}

/// A day's labour on the project added up (a Labour line). Built from the time
/// entries the server sends, but only hours and cost are kept: the worker and
/// the hourly rate that come with each entry are never read (backend-gaps G44).
@immutable
class LedgerLabourDay {
  const LedgerLabourDay({
    required this.day,
    required this.hours,
    required this.amount,
    required this.entries,
  });
  final DateTime day;
  final double hours;
  final double amount;
  final int entries;
}

/// Everything behind one budget line of a project, from
/// `GET /financials/projects/:id/budget/:categoryId/ledger`.
@immutable
class BudgetLedger {
  const BudgetLedger({
    required this.categoryName,
    required this.categoryCode,
    required this.planned,
    required this.actual,
    required this.recorded,
    required this.purchases,
    required this.usage,
    required this.labour,
    this.thresholdPct,
  });

  final String categoryName;
  final String categoryCode;
  final double planned;

  /// What the server counts as spent on this line.
  final double actual;
  final int? thresholdPct;

  /// Costs recorded against the line (equipment, subcontractors…).
  final List<SpendEntry> recorded;

  /// Material bought for the project. Counted when it is used, not here.
  final List<SpendEntry> purchases;
  final List<LedgerUsage> usage;
  final List<LedgerLabourDay> labour;

  double get recordedTotal => recorded.fold(0.0, (s, e) => s + e.amount);
  double get purchasesTotal => purchases.fold(0.0, (s, e) => s + e.amount);
  double get usageTotal => usage.fold(0.0, (s, e) => s + e.amount);
  double get labourTotal => labour.fold(0.0, (s, e) => s + e.amount);
  double get labourHours => labour.fold(0.0, (s, e) => s + e.hours);

  /// What the server adds to this line: costs recorded plus material used.
  double get itemisedTotal => recordedTotal + usageTotal;

  bool get isEmpty =>
      recorded.isEmpty && purchases.isEmpty && usage.isEmpty && labour.isEmpty;

  static BudgetLedger parse(Object? raw) {
    final m = J.map(raw);
    final category = J.map(m['category']);
    final budget = J.map(m['budget']);

    final recorded = <SpendEntry>[];
    final purchases = <SpendEntry>[];
    for (final t in J.list(m['transactions'])) {
      final e = SpendEntry.tryParse(t);
      if (e == null) continue;
      (e.source == 'MATERIAL_PURCHASE' ? purchases : recorded).add(e);
    }

    final usage = <LedgerUsage>[];
    for (final l in J.maps(m['materialLogs'])) {
      final id = J.str(l['id']);
      if (id == null) continue;
      final material = J.map(l['material']);
      usage.add(
        LedgerUsage(
          id: id,
          name: J.strOr(material['name'], 'Material'),
          unit: J.str(material['unit']),
          quantity: J.number(l['quantity']) ?? 0,
          unitCost: J.number(l['unitCost']) ?? 0,
          amount: J.number(l['totalCost']) ?? 0,
          date: J.date(l['usedAt']) ?? DateTime.now(),
          notes: J.str(l['notes']),
        ),
      );
    }

    // Added up by day on the spot; nothing about who worked is kept.
    final days = <DateTime, ({double hours, double amount, int entries})>{};
    for (final e in J.maps(m['timeEntries'])) {
      if (J.str(e['status']) == 'REJECTED') continue;
      final at = J.date(e['clockInAt'])?.toLocal();
      if (at == null || J.date(e['clockOutAt']) == null) continue;
      final day = DateTime(at.year, at.month, at.day);
      final known = days[day];
      final hours =
          (J.number(e['regularHours']) ?? 0) +
          (J.number(e['overtimeHours']) ?? 0);
      final cost = J.number(e['labourCost']) ?? 0;
      days[day] = (
        hours: (known?.hours ?? 0) + hours,
        amount: (known?.amount ?? 0) + cost,
        entries: (known?.entries ?? 0) + 1,
      );
    }
    final labour = [
      for (final d in days.entries)
        LedgerLabourDay(
          day: d.key,
          hours: d.value.hours,
          amount: d.value.amount,
          entries: d.value.entries,
        ),
    ]..sort((a, b) => b.day.compareTo(a.day));

    return BudgetLedger(
      categoryName: J.strOr(category['name'], 'Budget line'),
      categoryCode: J.strOr(category['code']),
      planned: J.number(budget['plannedAmount']) ?? 0,
      actual: J.number(budget['actualAmount']) ?? 0,
      thresholdPct: J.integer(budget['thresholdPct']),
      recorded: recorded,
      purchases: purchases,
      usage: usage,
      labour: labour,
    );
  }
}

// ---- recording a cost -------------------------------------------------------

/// A cost to record against a project and one of its budget categories.
@immutable
class NewCostInput {
  const NewCostInput({
    required this.projectId,
    required this.categoryId,
    required this.description,
    required this.amount,
    required this.occurredAt,
    this.vendor,
    this.reference,
    this.notes,
  });

  final String projectId;
  final String categoryId;
  final String description;
  final double amount;

  /// The day chosen with the moment it was entered, kept exactly so the cost can
  /// be found again if the answer to saving it is lost.
  final DateTime occurredAt;
  final String? vendor;
  final String? reference;
  final String? notes;

  Map<String, Object?> toBody() => {
    'projectId': projectId,
    'categoryId': categoryId,
    'description': description.trim(),
    'amount': roundMoney(amount),
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    if (vendor != null && vendor!.trim().isNotEmpty) 'vendor': vendor!.trim(),
    if (reference != null && reference!.trim().isNotEmpty)
      'reference': reference!.trim(),
    if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
  };

  /// Whether [e] (read back from the project's costs) is this cost.
  bool isSameAs(SpendEntry e) =>
      e.description.trim() == description.trim() &&
      roundMoney(e.amount) == roundMoney(amount) &&
      e.occurredAt.millisecondsSinceEpoch ==
          occurredAt.toUtc().millisecondsSinceEpoch;
}
