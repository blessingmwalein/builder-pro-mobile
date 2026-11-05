import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

/// Company money figures from `GET /financials/summary` (cash basis).
///
/// `revenueExpected`, `outstanding` and `profitMarginPct` are deliberately not
/// read: the API adds up DRAFT and VOID invoices as well, which overstates them
/// (the margin divides by the inflated figure). Receivables come from the
/// invoice aging report instead (see [AgingReport]).
@immutable
class FinanceSummary {
  const FinanceSummary({
    required this.collected,
    required this.actualCost,
    required this.profit,
    required this.budgetPlanned,
    required this.budgetLeft,
  });

  final double collected;
  final double actualCost;
  final double profit;
  final double budgetPlanned;
  final double budgetLeft;

  static FinanceSummary parse(Object? raw) {
    final m = J.map(raw);
    return FinanceSummary(
      collected: J.number(m['revenueCollected']) ?? 0,
      actualCost: J.number(m['actualCost']) ?? 0,
      profit: J.number(m['profit']) ?? 0,
      budgetPlanned: J.number(m['budgetPlanned']) ?? 0,
      budgetLeft: J.number(m['costToComplete']) ?? 0,
    );
  }
}

/// One unpaid invoice in the aging report.
@immutable
class AgingEntry {
  const AgingEntry({
    required this.invoiceId,
    required this.number,
    required this.clientName,
    required this.balance,
    required this.daysOverdue,
    this.dueDate,
  });

  final String invoiceId;
  final String number;
  final String clientName;
  final double balance;
  final int daysOverdue;
  final DateTime? dueDate;

  bool get isOverdue => daysOverdue > 0;
}

/// Money owed to the company, by how late it is (sent, partly paid and overdue
/// invoices only).
@immutable
class AgingReport {
  const AgingReport({
    required this.notDue,
    required this.days1to30,
    required this.days31to60,
    required this.days61to90,
    required this.over90,
    required this.entries,
  });

  final double notDue;
  final double days1to30;
  final double days31to60;
  final double days61to90;
  final double over90;

  /// Every unpaid invoice, most overdue first.
  final List<AgingEntry> entries;

  double get total => notDue + days1to30 + days31to60 + days61to90 + over90;
  double get overdue => days1to30 + days31to60 + days61to90 + over90;

  static AgingReport parse(Object? raw) {
    final m = J.map(raw);
    final totals = J.map(m['totals']);
    final buckets = J.map(m['buckets']);
    final entries = <AgingEntry>[];
    for (final key in const [
      'current',
      'days1to30',
      'days31to60',
      'days61to90',
      'over90',
    ]) {
      for (final e in J.maps(buckets[key])) {
        final id = J.str(e['id']);
        if (id == null) continue;
        entries.add(
          AgingEntry(
            invoiceId: id,
            number: J.strOr(e['invoiceNumber'], 'Invoice'),
            clientName: J.strOr(J.map(e['client'])['name'], 'Client'),
            balance: J.number(e['balanceAmount']) ?? 0,
            daysOverdue: J.integer(e['daysOverdue']) ?? 0,
            dueDate: J.date(e['dueDate']),
          ),
        );
      }
    }
    entries.sort((a, b) => b.daysOverdue.compareTo(a.daysOverdue));
    return AgingReport(
      notDue: J.number(totals['current']) ?? 0,
      days1to30: J.number(totals['days1to30']) ?? 0,
      days31to60: J.number(totals['days31to60']) ?? 0,
      days61to90: J.number(totals['days61to90']) ?? 0,
      over90: J.number(totals['over90']) ?? 0,
      entries: entries,
    );
  }
}

/// A project whose budget has reached its alert level. Only how much of the
/// budget is used is read, never the amounts.
@immutable
class BudgetAlert {
  const BudgetAlert({
    required this.projectId,
    required this.projectName,
    required this.percentUsed,
  });
  final String projectId;
  final String projectName;
  final int percentUsed;

  bool get isOver => percentUsed > 100;
}

/// The reliable parts of the company dashboard: how many projects are active and
/// which budgets are at their alert level. The revenue figures the same reply
/// carries add up draft and void invoices (backend-gaps G41) and are not read.
@immutable
class CompanyDashboard {
  const CompanyDashboard({required this.activeProjects, required this.alerts});

  final int activeProjects;

  /// One entry per project (its highest percentage), highest first.
  final List<BudgetAlert> alerts;

  static CompanyDashboard parse(Object? raw) {
    final m = J.map(raw);
    final worst = <String, BudgetAlert>{};
    for (final a in J.maps(m['budgetAlerts'])) {
      final project = J.map(a['project']);
      final id = J.str(project['id']);
      final percent = J.integer(a['percentUsed']);
      if (id == null || percent == null) continue;
      final known = worst[id];
      if (known == null || percent > known.percentUsed) {
        worst[id] = BudgetAlert(
          projectId: id,
          projectName: J.strOr(project['name'], 'Project'),
          percentUsed: percent,
        );
      }
    }
    return CompanyDashboard(
      activeProjects: J.integer(m['activeProjects']) ?? 0,
      alerts: worst.values.toList()
        ..sort((a, b) => b.percentUsed.compareTo(a.percentUsed)),
    );
  }
}

/// Budget statuses the backend uses for one budget line.
abstract final class BudgetStatus {
  static const onTrack = 'ON_TRACK';
  static const warning = 'WARNING';
  static const overBudget = 'OVER_BUDGET';
}

/// One budget line of a project: what was planned and what has been spent.
@immutable
class BudgetLine {
  const BudgetLine({
    required this.categoryName,
    required this.planned,
    required this.actual,
    required this.percentUsed,
    required this.status,
    this.categoryId = '',
    this.thresholdPct,
  });

  final String categoryName;

  /// Needed to save a changed budget (the server files it by category).
  final String categoryId;

  /// When the line turns to a warning, as a percentage of what is planned.
  final int? thresholdPct;
  final double planned;
  final double actual;
  final int percentUsed;
  final String status;

  bool get isOver => status == BudgetStatus.overBudget;

  /// At or past its alert level but not yet over.
  bool get isWarning => status == BudgetStatus.warning;

  /// Planned minus spent; negative when over.
  double get remaining => planned - actual;

  static BudgetLine? tryParse(Map<String, dynamic> m) {
    final name = J.str(J.map(m['category'])['name']);
    if (name == null) return null;
    final planned = J.number(m['plannedAmount']) ?? 0;
    final actual = J.number(m['actualAmount']) ?? 0;
    return BudgetLine(
      categoryName: name,
      planned: planned,
      actual: actual,
      percentUsed:
          J.integer(m['percentUsed']) ??
          (planned > 0 ? ((actual / planned) * 100).round() : 0),
      status: J.strOr(m['status'], BudgetStatus.onTrack),
      categoryId: J.strOr(m['categoryId'], J.strOr(J.map(m['category'])['id'])),
      thresholdPct: J.integer(m['thresholdPct']),
    );
  }
}

/// A budget category (Materials, Labour…), shared by every project.
@immutable
class BudgetCategory {
  const BudgetCategory({
    required this.id,
    required this.name,
    required this.code,
  });
  final String id;
  final String name;
  final String code;

  static BudgetCategory? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    final name = J.str(m['name']);
    if (id == null || name == null) return null;
    return BudgetCategory(id: id, name: name, code: J.strOr(m['code']));
  }
}

/// One category's planned amount, as saved.
@immutable
class BudgetEdit {
  const BudgetEdit({
    required this.categoryId,
    required this.plannedAmount,
    this.thresholdPct,
  });
  final String categoryId;
  final double plannedAmount;

  /// Left out for a category that has none yet (the server then uses 80).
  final int? thresholdPct;
}

/// A project's budget by category. Reading it needs `financials.view`. The
/// category ledger (one line's items) is read by [BudgetLedger], which keeps only
/// hours and cost for labour because the server sends each worker's hourly rate
/// there (backend-gaps G44).
@immutable
class ProjectBudget {
  const ProjectBudget({
    required this.lines,
    required this.totalPlanned,
    required this.totalActual,
  });

  final List<BudgetLine> lines;
  final double totalPlanned;
  final double totalActual;

  /// Planned minus spent; negative when over.
  double get remaining => totalPlanned - totalActual;
  bool get isOver => totalActual > totalPlanned && totalPlanned > 0;
  int get percentUsed =>
      totalPlanned > 0 ? ((totalActual / totalPlanned) * 100).round() : 0;
  bool get isEmpty => lines.isEmpty && totalPlanned == 0 && totalActual == 0;

  /// How many lines are over budget, and how many are at their alert level.
  int get overLines => lines.where((l) => l.isOver).length;
  int get warningLines => lines.where((l) => l.isWarning).length;

  /// Whether anything here is over budget or at its alert level.
  bool get needsAttention => isOver || overLines > 0 || warningLines > 0;

  static ProjectBudget parse(Object? raw) {
    final m = J.map(raw);
    return ProjectBudget(
      lines: J
          .maps(m['budgets'])
          .map(BudgetLine.tryParse)
          .whereType<BudgetLine>()
          .toList(),
      totalPlanned: J.number(m['totalPlanned']) ?? 0,
      totalActual: J.number(m['totalActual']) ?? 0,
    );
  }
}

/// One expense recorded against a project.
@immutable
class SpendEntry {
  const SpendEntry({
    required this.id,
    required this.description,
    required this.amount,
    required this.occurredAt,
    this.vendor,
    this.categoryName,
    this.source,
    this.reference,
    this.notes,
    this.receiptUrl,
  });

  final String id;
  final String description;
  final double amount;
  final DateTime occurredAt;
  final String? vendor;
  final String? categoryName;

  /// `MATERIAL_PURCHASE` (a delivery) or `MANUAL` (equipment, overheads).
  /// Labour is never a transaction, so no row carries anyone's pay.
  final String? source;
  final String? reference;
  final String? notes;

  /// The proof of purchase, when the server kept a web address for it.
  final String? receiptUrl;

  /// "Material purchase", "Manual entry"…
  String? get sourceLabel {
    final s = source;
    if (s == null) return null;
    final words = s
        .toLowerCase()
        .split('_')
        .where((w) => w.isNotEmpty)
        .join(' ');
    if (words.isEmpty) return null;
    return s == 'MANUAL'
        ? 'Manual entry'
        : words[0].toUpperCase() + words.substring(1);
  }

  static SpendEntry? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    final description = J.str(m['description']);
    if (id == null || description == null) return null;
    final receipt = J.str(m['receiptUrl']);
    final isLink =
        receipt != null &&
        (receipt.startsWith('http://') || receipt.startsWith('https://'));
    return SpendEntry(
      id: id,
      description: description,
      amount: J.number(m['amount']) ?? 0,
      occurredAt: J.date(m['occurredAt']) ?? DateTime.now(),
      vendor: J.str(m['vendor']),
      categoryName: J.str(J.map(m['category'])['name']),
      source: J.str(m['sourceType']),
      reference: J.str(m['reference']),
      notes: J.str(m['notes']),
      receiptUrl: isLink ? receipt : null,
    );
  }
}

/// The latest expenses of a project, and how many there are in all.
@immutable
class RecentSpending {
  const RecentSpending({required this.items, required this.total});
  final List<SpendEntry> items;
  final int total;

  static RecentSpending parse(Object? body) {
    final paged = J.paged(body);
    return RecentSpending(
      items: paged.items
          .map(SpendEntry.tryParse)
          .whereType<SpendEntry>()
          .toList(),
      total: paged.total,
    );
  }
}

@immutable
class LineItem {
  const LineItem({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    this.unit,
    this.category,
  });

  final String description;
  final double quantity;
  final String? unit;

  /// Quote lines carry a category (Labour, Materials…); invoice lines do not.
  final String? category;
  final double unitPrice;
  final double total;

  static LineItem? tryParse(Map<String, dynamic> m) {
    final description = J.str(m['description']);
    if (description == null) return null;
    return LineItem(
      description: description,
      quantity: J.number(m['quantity']) ?? 0,
      unit: J.str(m['unit']),
      category: J.str(m['category']),
      unitPrice: J.number(m['unitPrice']) ?? 0,
      total: J.number(m['totalPrice']) ?? 0,
    );
  }
}

/// Money to the cent. A value that is not a finite number is returned as it is,
/// so callers can reject it (rounding NaN or infinity would throw).
double roundMoney(double v) => v.isFinite ? (v * 100).round() / 100 : v;

/// Invoice statuses the backend uses.
abstract final class InvoiceStatus {
  static const draft = 'DRAFT';
  static const sent = 'SENT';
  static const partiallyPaid = 'PARTIALLY_PAID';
  static const paid = 'PAID';
  static const overdue = 'OVERDUE';
  static const voided = 'VOID';
}

/// The ways the app can record a payment: money already received by hand.
/// PayNow and EcoCash make the server start a payment with the customer's phone
/// through the payment provider, which is not something to do from a record
/// screen, so they stay on the web app.
abstract final class ManualPayment {
  static const bank = 'BANK_TRANSFER';
  static const cash = 'CASH';
  static const all = [bank, cash];

  static String label(String method) => switch (method) {
    'BANK_TRANSFER' => 'Bank transfer',
    'CASH' => 'Cash',
    'PAYNOW' => 'PayNow',
    'ECOCASH' => 'EcoCash',
    'CARD' => 'Card',
    _ => method,
  };
}

/// A payment against an invoice. The provider payload the API attaches (raw
/// gateway data) is never read.
@immutable
class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.amount,
    required this.method,
    required this.status,
    this.paidAt,
    this.reference,
  });

  /// The status of a payment that has been received.
  static const success = 'SUCCESS';

  final String id;
  final double amount;
  final String method;
  final String status;
  final DateTime? paidAt;
  final String? reference;

  static PaymentRecord? tryParse(Map<String, dynamic> m) {
    final id = J.str(m['id']);
    if (id == null) return null;
    return PaymentRecord(
      id: id,
      amount: J.number(m['amount']) ?? 0,
      method: J.strOr(m['method'], 'OTHER'),
      status: J.strOr(m['status'], 'PENDING'),
      paidAt: J.date(m['paidAt']) ?? J.date(m['createdAt']),
      reference: J.str(m['transactionRef']),
    );
  }
}

@immutable
class InvoiceSummary {
  const InvoiceSummary({
    required this.id,
    required this.number,
    required this.status,
    required this.clientName,
    required this.total,
    required this.paid,
    required this.balance,
    this.clientId = '',
    this.projectName,
    this.issueDate,
    this.dueDate,
    this.createdAt,
  });

  final String id;
  final String number;
  final String status;
  final String clientName;
  final String clientId;
  final DateTime? createdAt;
  final String? projectName;
  final DateTime? issueDate;
  final DateTime? dueDate;
  final double total;
  final double paid;
  final double balance;

  /// Sent to the client and not yet paid in full. The server does not check
  /// this when a payment is recorded, so the app does.
  bool get isOpenForPayment =>
      (status == InvoiceStatus.sent ||
          status == InvoiceStatus.partiallyPaid ||
          status == InvoiceStatus.overdue) &&
      roundMoney(balance) > 0;

  static InvoiceSummary? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    if (id == null) return null;
    return InvoiceSummary(
      id: id,
      number: J.strOr(m['invoiceNumber'], 'Invoice'),
      status: J.strOr(m['status'], 'DRAFT'),
      clientName: J.strOr(J.map(m['client'])['name'], 'Client'),
      clientId: J.strOr(m['clientId'], J.strOr(J.map(m['client'])['id'])),
      createdAt: J.date(m['createdAt']),
      projectName: J.str(J.map(m['project'])['name']),
      issueDate: J.date(m['issueDate']),
      dueDate: J.date(m['dueDate']),
      total: J.number(m['totalAmount']) ?? 0,
      paid: J.number(m['paidAmount']) ?? 0,
      balance: J.number(m['balanceAmount']) ?? 0,
    );
  }
}

@immutable
class InvoiceDetail {
  const InvoiceDetail({
    required this.summary,
    required this.subtotal,
    required this.tax,
    required this.retentionPercent,
    required this.lines,
    required this.payments,
    this.notes,
    this.paymentTerms,
    this.quoteNumber,
    this.clientContact,
    this.clientEmail,
  });

  final InvoiceSummary summary;
  final double subtotal;
  final double tax;
  final double retentionPercent;
  final List<LineItem> lines;
  final List<PaymentRecord> payments;
  final String? notes;
  final String? paymentTerms;
  final String? quoteNumber;
  final String? clientContact;

  /// Where "send" would email the invoice. Shown so the sender can check it.
  final String? clientEmail;

  static InvoiceDetail? tryParse(Object? raw) {
    final m = J.map(raw);
    final summary = InvoiceSummary.tryParse(m);
    if (summary == null) return null;
    final client = J.map(m['client']);
    return InvoiceDetail(
      summary: summary,
      subtotal: J.number(m['subtotal']) ?? 0,
      tax: J.number(m['taxAmount']) ?? 0,
      retentionPercent: J.number(m['retentionPct']) ?? 0,
      lines: J
          .maps(m['lineItems'])
          .map(LineItem.tryParse)
          .whereType<LineItem>()
          .toList(),
      payments: J
          .maps(m['payments'])
          .map(PaymentRecord.tryParse)
          .whereType<PaymentRecord>()
          .toList(),
      notes: J.str(m['notes']),
      paymentTerms: J.str(m['paymentTerms']),
      quoteNumber: J.str(J.map(m['quote'])['quoteNumber']),
      clientContact: J.str(client['contactPerson']),
      clientEmail: J.str(client['email']),
    );
  }
}

@immutable
class QuoteSummary {
  const QuoteSummary({
    required this.id,
    required this.number,
    required this.title,
    required this.status,
    required this.clientName,
    required this.total,
    this.clientId = '',
    this.issueDate,
    this.expiryDate,
    this.createdAt,
  });

  final String id;
  final String number;
  final String title;
  final String status;
  final String clientName;
  final double total;
  final String clientId;
  final DateTime? issueDate;
  final DateTime? expiryDate;
  final DateTime? createdAt;

  static QuoteSummary? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    if (id == null) return null;
    return QuoteSummary(
      id: id,
      number: J.strOr(m['quoteNumber'], 'Quote'),
      title: J.strOr(m['title'], 'Untitled quote'),
      status: J.strOr(m['status'], 'DRAFT'),
      clientName: J.strOr(J.map(m['client'])['name'], 'Client'),
      total: J.number(m['totalAmount']) ?? 0,
      clientId: J.strOr(m['clientId'], J.strOr(J.map(m['client'])['id'])),
      issueDate: J.date(m['issueDate']),
      expiryDate: J.date(m['expiryDate']),
      createdAt: J.date(m['createdAt']),
    );
  }
}

@immutable
class QuoteDetail {
  const QuoteDetail({
    required this.summary,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.taxRate,
    required this.lines,
    this.projectId,
    this.notes,
    this.paymentTerms,
    this.rejectionNotes,
    this.clientEmail,
  });

  final QuoteSummary summary;
  final double subtotal;
  final double discount;
  final double tax;
  final double taxRate;
  final List<LineItem> lines;

  /// The project the quote is for, when it has one.
  final String? projectId;
  final String? notes;
  final String? paymentTerms;
  final String? rejectionNotes;

  /// Where "send" would email the quote. Shown so the sender can check it.
  final String? clientEmail;

  static QuoteDetail? tryParse(Object? raw) {
    final m = J.map(raw);
    final summary = QuoteSummary.tryParse(m);
    if (summary == null) return null;
    return QuoteDetail(
      summary: summary,
      subtotal: J.number(m['subtotal']) ?? 0,
      discount: J.number(m['discountAmount']) ?? 0,
      tax: J.number(m['taxAmount']) ?? 0,
      taxRate: J.number(m['taxRate']) ?? 0,
      lines: J
          .maps(m['lineItems'])
          .map(LineItem.tryParse)
          .whereType<LineItem>()
          .toList(),
      projectId: J.str(m['projectId']),
      notes: J.str(m['notes']),
      paymentTerms: J.str(m['paymentTerms']),
      rejectionNotes: J.str(m['rejectionNotes']),
      clientEmail: J.str(J.map(m['client'])['email']),
    );
  }
}
