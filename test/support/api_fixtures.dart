import 'package:builder_pro_mobile/core/auth/session_state.dart';
import 'package:builder_pro_mobile/core/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'fakes.dart';
import 'fixtures.dart';

/// JSON exactly as builder-pro-back sends it (Prisma decimals are strings).
Map<String, dynamic> timeEntryJson({
  String id = 'te1',
  String projectId = 'p1',
  String? clockInAt,
  String? clockOutAt,
  bool withProject = true,
  int breakMinutes = 0,
  String regularHours = '0',
  String overtimeHours = '0',
  String status = 'PENDING',
}) => {
  'id': id,
  'companyId': 'c1',
  'projectId': projectId,
  'taskId': null,
  'workerId': 'u1',
  'clockInAt': clockInAt ?? DateTime.now().toUtc().toIso8601String(),
  'clockOutAt': clockOutAt,
  'breakMinutes': breakMinutes,
  'regularHours': regularHours,
  'overtimeHours': overtimeHours,
  'hourlyRate': '5.00',
  'labourCost': '0',
  'isManualEntry': false,
  'status': status,
  if (withProject)
    'project': {'id': projectId, 'name': 'Harare Tower', 'code': 'HT-01'},
};

Map<String, dynamic> taskJson({
  String id = 't1',
  String title = 'Pour slab',
  String status = 'TODO',
  String priority = 'HIGH',
  String? dueDate,
  String projectId = 'p1',
  String projectName = 'Harare Tower',
  List<Map<String, dynamic>> checklists = const [],
  List<Map<String, dynamic>>? comments,
  int commentCount = 0,
  String? description,
}) => {
  'id': id,
  'companyId': 'c1',
  'projectId': projectId,
  'title': title,
  'description': description,
  'status': status,
  'priority': priority,
  'dueDate': dueDate,
  'startDate': null,
  'estimatedHours': '8.00',
  'project': {'id': projectId, 'code': 'HT-01', 'name': projectName},
  'assignees': [
    {
      'user': {'id': 'u1', 'firstName': 'Tendai', 'lastName': 'Moyo'},
    },
  ],
  'checklists': checklists,
  'comments': ?comments,
  '_count': {'comments': commentCount, 'attachments': 0},
};

Map<String, dynamic> checklistJson({
  String id = 'cl1',
  List<Map<String, dynamic>>? items,
}) => {
  'id': id,
  'title': 'Safety',
  'items':
      items ??
      [
        {'id': 'i1', 'content': 'Wear hard hat', 'isDone': false},
        {'id': 'i2', 'content': 'Check scaffolding', 'isDone': true},
      ],
};

Map<String, dynamic> materialJson({
  String id = 'm1',
  String name = 'Cement 50kg',
  String unit = 'bag',
  String unitCost = '12.50',
  String stock = '40.000',
}) => {
  'id': id,
  'name': name,
  'unit': unit,
  'unitCost': unitCost,
  'stockOnHand': stock,
  'sku': 'CEM-50',
  'supplier': {'id': 's1', 'name': 'Zim Cement'},
  'categoryRef': {'id': 'cat1', 'code': 'CEM', 'name': 'Cement'},
};

Map<String, dynamic> conversationJson({
  String id = 'conv1',
  String type = 'PROJECT',
  String? title,
  String? lastBody,
}) => {
  'id': id,
  'type': type,
  'title': title,
  'updatedAt': DateTime.now().toUtc().toIso8601String(),
  'project': {'id': 'p1', 'name': 'Harare Tower'},
  'messages': [
    if (lastBody != null)
      {
        'id': 'm-last',
        'body': lastBody,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'sender': {'firstName': 'Rudo', 'lastName': 'Banda'},
      },
  ],
  'participants': [],
};

Map<String, dynamic> messageJson({
  String id = 'msg1',
  String conversationId = 'conv1',
  String senderId = 'u2',
  String first = 'Rudo',
  String last = 'Banda',
  String body = 'Slab is ready',
  DateTime? at,
}) => {
  'id': id,
  'conversationId': conversationId,
  'senderId': senderId,
  'body': body,
  'createdAt': (at ?? DateTime.now()).toUtc().toIso8601String(),
  'sender': {'id': senderId, 'firstName': first, 'lastName': last},
  'attachments': [],
};

Map<String, dynamic> paged(
  List<Map<String, dynamic>> items, {
  int page = 1,
  int limit = 20,
  int? total,
}) => {
  'items': items,
  'meta': {'page': page, 'limit': limit, 'total': total ?? items.length},
};

/// A container for controller tests: signed-in user [u1] with [perms], fake
/// API, in-memory database, no sockets.
ProviderContainer makeContainer(
  TestEnv env, {
  List<String> perms = workerPerms,
  List<Override> extra = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      ...env.overrides,
      sessionProvider.overrideWith(
        () =>
            FakeSession(SessionState.authenticated(testMe(permissions: perms))),
      ),
      ...extra,
    ],
    retry: (_, _) => null,
  );
  return container;
}

/// A pending time entry as `GET /time-tracking` returns it for supervisors
/// (worker, project and task are included).
Map<String, dynamic> approvalEntryJson({
  String id = 'e1',
  String workerId = 'w1',
  String first = 'Tendai',
  String last = 'Moyo',
  DateTime? clockIn,
  DateTime? clockOut,
  bool open = false,
  String regular = '8.00',
  String overtime = '0.00',
  bool manual = false,
  String? notes,
  int breakMinutes = 30,
}) {
  final start =
      clockIn ?? DateTime.now().subtract(const Duration(days: 1, hours: 9));
  return {
    'id': id,
    'workerId': workerId,
    'projectId': 'p1',
    'clockInAt': start.toUtc().toIso8601String(),
    'clockOutAt': open
        ? null
        : (clockOut ?? start.add(const Duration(hours: 8, minutes: 30)))
              .toUtc()
              .toIso8601String(),
    'breakMinutes': breakMinutes,
    'regularHours': regular,
    'overtimeHours': overtime,
    'hourlyRate': '5.00',
    'labourCost': '40.00',
    'isManualEntry': manual,
    'notes': notes,
    'status': 'PENDING',
    'worker': {'id': workerId, 'firstName': first, 'lastName': last},
    'project': {'id': 'p1', 'name': 'Harare Tower', 'code': 'HT-01'},
    'task': {'id': 't1', 'title': 'Pour slab'},
  };
}

Map<String, dynamic> projectJson({
  String id = 'p1',
  String name = 'Harare Tower',
  String code = 'HT-01',
  String status = 'ACTIVE',
  int completion = 40,
  List<Map<String, dynamic>>? members,
}) => {
  'id': id,
  'companyId': 'c1',
  'code': code,
  'name': name,
  'description': 'Ten storey office block',
  'projectType': 'COMMERCIAL',
  'siteAddress': '12 Samora Machel Ave',
  'status': status,
  'startDate': DateTime(2026, 3, 1).toUtc().toIso8601String(),
  'endDate': DateTime(2027, 2, 1).toUtc().toIso8601String(),
  // Money the API returns to anyone with projects.view; the app must ignore it.
  'baselineBudget': '2500000.00',
  'actualCost': '812000.00',
  'completionPercent': completion,
  'client': {
    'id': 'cl1',
    'name': 'Zim Properties',
    'contactPerson': 'Chipo Dube',
    'phone': '+263771000000',
    'email': 'chipo@zimprops.test',
  },
  '_count': {'tasks': 12, 'members': 3},
  'members': ?members,
};

Map<String, dynamic> memberJson({
  String id = 'u2',
  String first = 'Rudo',
  String last = 'Banda',
  String? role = 'Foreman',
}) => {
  'userId': id,
  'role': role,
  'user': {
    'id': id,
    'firstName': first,
    'lastName': last,
    'email': '$first@x.test',
  },
};

Map<String, dynamic> invoiceJson({
  String id = 'inv1',
  String number = 'INV-2026-0001',
  String status = 'SENT',
  String client = 'Zim Properties',
  String total = '1150.00',
  String paid = '400.00',
  String balance = '750.00',
  DateTime? due,
  bool detail = false,

  /// The invoice's payments (detail only). The default is one earlier payment.
  List<Map<String, dynamic>>? payments,
}) => {
  'id': id,
  'invoiceNumber': number,
  'status': status,
  'clientId': 'cl1',
  'client': detail
      ? {
          'id': 'cl1',
          'name': client,
          'contactPerson': 'Chipo Dube',
          'phone': '0771',
          'address': 'secret street',
        }
      : {'id': 'cl1', 'name': client},
  'project': {'id': 'p1', 'name': 'Harare Tower', 'code': 'HT-01'},
  'issueDate': DateTime(2026, 9, 1).toUtc().toIso8601String(),
  'dueDate': (due ?? DateTime(2026, 10, 1)).toUtc().toIso8601String(),
  'subtotal': '1000.00',
  'taxAmount': '150.00',
  'totalAmount': total,
  'paidAmount': paid,
  'balanceAmount': balance,
  'retentionPct': '5.00',
  'paymentTerms': 'Net 30',
  'notes': 'Thank you',
  'quote': {'id': 'q1', 'quoteNumber': 'Q-2026-0007'},
  'lineItems': [
    {
      'id': 'l1',
      'description': 'Concrete supply',
      'quantity': '10.000',
      'unit': 'm3',
      'unitPrice': '85.00',
      'totalPrice': '850.00',
      'sortOrder': 0,
    },
    {
      'id': 'l2',
      'description': 'Labour',
      'quantity': '1.000',
      'unit': null,
      'unitPrice': '150.00',
      'totalPrice': '150.00',
      'sortOrder': 1,
    },
  ],
  'payments':
      payments ??
      [
        {
          'id': 'pay1',
          'amount': '400.00',
          'method': 'BANK_TRANSFER',
          'status': 'SUCCESS',
          'transactionRef': 'REF-123',
          'paidAt': DateTime(2026, 9, 20).toUtc().toIso8601String(),
          // Raw gateway data the app must never read or show.
          'providerPayload': {'card': '4111-SECRET', 'token': 'tok_secret'},
        },
      ],
};

/// A payment against an invoice, as the API sends it.
Map<String, dynamic> payJson({
  String id = 'pay2',
  num amount = 100,
  String method = 'CASH',
  String status = 'SUCCESS',
  DateTime? paidAt,
}) => {
  'id': id,
  'invoiceId': 'inv1',
  'amount': amount.toStringAsFixed(2),
  'method': method,
  'status': status,
  'transactionRef': 'MANUAL-$id',
  'paidAt': (paidAt ?? DateTime.now()).toUtc().toIso8601String(),
  'createdAt': (paidAt ?? DateTime.now()).toUtc().toIso8601String(),
  'providerPayload': {'secret': 'never read'},
};

Map<String, dynamic> quoteJson({
  String id = 'q1',
  String number = 'Q-2026-0007',
  String title = 'Foundation works',
  String status = 'SENT',
  String total = '5750.00',
}) => {
  'id': id,
  'quoteNumber': number,
  'title': title,
  'status': status,
  'client': {'id': 'cl1', 'name': 'Zim Properties'},
  'issueDate': DateTime(2026, 9, 1).toUtc().toIso8601String(),
  'expiryDate': DateTime(2026, 11, 1).toUtc().toIso8601String(),
  'subtotal': '5000.00',
  'discountAmount': '250.00',
  'taxRate': '15.00',
  'taxAmount': '1000.00',
  'totalAmount': total,
  'notes': 'Includes site clearing',
  'paymentTerms': '50% upfront',
  'rejectionNotes': status == 'REJECTED' ? 'Too expensive' : null,
  'lineItems': [
    {
      'id': 'l1',
      'description': 'Excavation',
      'quantity': '1.000',
      'unit': 'lot',
      'unitPrice': '5000.00',
      'totalPrice': '5000.00',
    },
  ],
};

Map<String, dynamic> agingJson({
  double notDue = 500,
  double d30 = 300,
  double d60 = 0,
  double d90 = 0,
  double over = 1200,
}) => {
  'buckets': {
    'current': [
      {
        'id': 'i-cur',
        'invoiceNumber': 'INV-0001',
        'client': {'id': 'c1', 'name': 'Alpha Ltd'},
        'dueDate': DateTime(2026, 12, 1).toUtc().toIso8601String(),
        'balanceAmount': notDue,
        'daysOverdue': 0,
      },
    ],
    'days1to30': [
      {
        'id': 'i-30',
        'invoiceNumber': 'INV-0002',
        'client': {'id': 'c2', 'name': 'Beta Ltd'},
        'dueDate': DateTime(2026, 10, 10).toUtc().toIso8601String(),
        'balanceAmount': d30,
        'daysOverdue': 16,
      },
    ],
    'days31to60': [],
    'days61to90': [],
    'over90': [
      {
        'id': 'i-90',
        'invoiceNumber': 'INV-0003',
        'client': {'id': 'c3', 'name': 'Gamma Ltd'},
        'dueDate': DateTime(2026, 6, 1).toUtc().toIso8601String(),
        'balanceAmount': over,
        'daysOverdue': 147,
      },
    ],
  },
  'totals': {
    'current': notDue,
    'days1to30': d30,
    'days31to60': d60,
    'days61to90': d90,
    'over90': over,
  },
};

Map<String, dynamic> financeSummaryJson() => {
  'budgetPlanned': 100000,
  'actualCost': 40000,
  'variance': 60000,
  'revenueCollected': 55000,
  // Inflated by draft and void invoices: the app must not show these.
  'revenueExpected': 999999,
  'outstanding': 888888,
  'profit': 15000,
  'profitMarginPct': 77,
  'costToComplete': 60000,
};

Map<String, dynamic> requestJson({
  String id = 'r1',
  String type = 'PROCUREMENT_PO',
  String? notes = 'Rebar for block A',
  String status = 'PENDING',
  String me = 'u1',
  String myStatus = 'PENDING',
  bool second = false,
}) => {
  'id': id,
  'entityType': type,
  'entityId': 'ent-12345678',
  'status': status,
  'notes': notes,
  'createdAt': DateTime.now()
      .subtract(const Duration(hours: 5))
      .toUtc()
      .toIso8601String(),
  'requestedBy': {'id': 'u9', 'firstName': 'Farai', 'lastName': 'Ncube'},
  'steps': [
    {
      'id': 'step1',
      'stepOrder': 1,
      'approverId': me,
      'status': myStatus,
      'comment': null,
      'approver': {'id': me, 'firstName': 'Tendai', 'lastName': 'Moyo'},
    },
    if (second)
      {
        'id': 'step2',
        'stepOrder': 2,
        'approverId': 'u7',
        'status': 'PENDING',
        'comment': null,
        'approver': {'id': 'u7', 'firstName': 'Chipo', 'lastName': 'Dube'},
      },
  ],
};

Map<String, dynamic> prJson({
  String id = 'pr1',
  String number = 'PR-2026-0001',
  String status = 'SUBMITTED',
  String requestedById = 'u9',
  String requester = 'Farai',
  String? notes = 'For the slab pour',
  DateTime? createdAt,
  bool detail = false,
  int items = 2,
  bool withCosts = true,
}) => {
  'id': id,
  'prNumber': number,
  'status': status,
  'notes': notes,
  'requestedById': requestedById,
  'requestedBy': {
    'id': requestedById,
    'firstName': requester,
    'lastName': 'Ncube',
  },
  'approvedBy': status == 'APPROVED'
      ? {'id': 'u3', 'firstName': 'Chipo', 'lastName': 'Dube'}
      : null,
  'approvedAt': status == 'APPROVED'
      ? DateTime(2026, 10, 20).toUtc().toIso8601String()
      : null,
  'rejectedAt': null,
  'project': {'id': 'p1', 'name': 'Harare Tower'},
  'createdAt': (createdAt ?? DateTime.now().subtract(const Duration(hours: 3)))
      .toUtc()
      .toIso8601String(),
  '_count': {'items': items, 'orders': 0},
  if (detail) ...{
    'items': [
      {
        'id': 'i1',
        'description': 'Portland cement 50kg',
        'quantity': '40.000',
        'unit': 'bag',
        'estimatedUnitCost': withCosts ? '12.50' : null,
        'material': {'id': 'm1', 'name': 'Cement 50kg', 'unit': 'bag'},
      },
      if (items > 1)
        {
          'id': 'i2',
          'description': 'River sand',
          'quantity': '5.000',
          'unit': 'm3',
          'estimatedUnitCost': withCosts ? '30.00' : null,
        },
    ],
    'orders': [
      {
        'id': 'po1',
        'poNumber': 'PO-2026-0001',
        'status': 'SENT',
        'totalAmount': '650.00',
      },
    ],
  },
};

Map<String, dynamic> poJson({
  String id = 'po1',
  String number = 'PO-2026-0001',
  String status = 'SENT',
  String supplier = 'Zim Cement',
  String total = '650.00',
  bool detail = false,

  /// The order's delivery notes (detail only). The default is one empty note.
  List<Map<String, dynamic>>? deliveryNotes,
}) => {
  'id': id,
  'poNumber': number,
  'status': status,
  'totalAmount': total,
  'createdAt': DateTime(2026, 10, 15).toUtc().toIso8601String(),
  'expectedDelivery': DateTime(2026, 11, 2).toUtc().toIso8601String(),
  'supplier': {'id': 's1', 'name': supplier, 'email': 'sales@zimcement.test'},
  '_count': {'items': 2, 'deliveryNotes': 1},
  if (detail) ...{
    'items': [
      {
        'id': 'pi1',
        'materialId': 'm1',
        'description': 'Portland cement 50kg',
        'quantity': '40.000',
        'unitCost': '12.50',
        'totalCost': '500.00',
        'material': {'id': 'm1', 'name': 'Cement 50kg', 'unit': 'bag'},
      },
      {
        'id': 'pi2',
        'materialId': 'm2',
        'description': 'River sand',
        'quantity': '5.000',
        'unitCost': '30.00',
        'totalCost': '150.00',
        'material': {'id': 'm2', 'name': 'River sand', 'unit': 'm3'},
      },
    ],
    'purchaseRequest': {'id': 'pr1', 'prNumber': 'PR-2026-0001'},
    'deliveryNotes':
        deliveryNotes ??
        [
          {'id': 'dn1', 'items': []},
        ],
    'notes': 'Deliver to gate B',
  },
};

/// An equipment assignment as the API sends it. Dates are calendar days at UTC
/// midnight; `returnedAt` and `createdAt` are instants.
Map<String, dynamic> allocJson({
  String id = 'a1',
  String projectId = 'p1',
  String project = 'Harare Tower',
  DateTime? start,
  DateTime? end,
  DateTime? returnedAt,
  String by = 'u1',
  String? notes,
  DateTime? createdAt,
}) => {
  'id': id,
  'equipmentId': 'e1',
  'projectId': projectId,
  'allocatedById': by,
  'startDate': (start ?? DateTime.utc(2026, 10, 26)).toIso8601String(),
  'endDate': end?.toIso8601String(),
  'returnedAt': returnedAt?.toUtc().toIso8601String(),
  'notes': notes,
  'createdAt': (createdAt ?? DateTime.utc(2026, 10, 26, 7, 30))
      .toIso8601String(),
  'project': {'id': projectId, 'name': project},
  'allocatedBy': {'id': by, 'firstName': 'Tendai', 'lastName': 'Moyo'},
};

/// A piece of equipment. The cost fields are always present, as in the real
/// API, so tests can prove the app never reads or shows them.
Map<String, dynamic> equipJson({
  String id = 'e1',
  String name = 'Excavator CAT 320',
  String status = 'AVAILABLE',
  String? category = 'Heavy plant',
  String? serial = 'CAT-0042',
  bool detail = false,
  List<Map<String, dynamic>> allocations = const [],
}) => {
  'id': id,
  'name': name,
  'description': detail ? 'Tracked excavator, 20 t' : null,
  'serialNumber': serial,
  'status': status,
  'dailyRate': '250.00',
  'purchaseCost': '84000.00',
  'purchasedAt': DateTime.utc(2024, 3, 1).toIso8601String(),
  'category': category == null ? null : {'id': 'c1', 'name': category},
  if (!detail) '_count': {'allocations': allocations.length},
  if (detail) 'allocations': allocations,
};

/// One line of a delivery note. `m1` is the cement and `m2` the sand of [poJson].
Map<String, dynamic> dnLine({
  String description = 'Portland cement 50kg',
  String? materialId = 'm1',
  num ordered = 40,
  num received = 10,
}) => {
  'id': 'dl-$description',
  'materialId': materialId,
  'description': description,
  'quantityOrdered': ordered.toStringAsFixed(3),
  'quantityReceived': received.toStringAsFixed(3),
};

/// A delivery recorded against an order.
Map<String, dynamic> dnJson({
  String id = 'dn1',
  String by = 'u1',
  DateTime? date,
  DateTime? createdAt,
  String? notes,
  List<Map<String, dynamic>>? lines,
}) => {
  'id': id,
  'purchaseOrderId': 'po1',
  'deliveryDate': (date ?? DateTime.utc(2026, 10, 20)).toIso8601String(),
  'notes': notes,
  'receivedById': by,
  'createdAt': (createdAt ?? DateTime.utc(2026, 10, 20, 9)).toIso8601String(),
  'items': lines ?? [dnLine()],
};

/// A project stage as the API sends it. Dates are calendar days at UTC midnight.
Map<String, dynamic> stageJson({
  String id = 's1',
  String code = 'PLANNING',
  String name = 'Site survey',
  int order = 1,
  String status = 'PENDING',
  bool requiresApproval = false,
  DateTime? plannedStart,
  DateTime? plannedEnd,
  DateTime? actualStart,
  DateTime? actualEnd,
  String? approvedBy,
  DateTime? approvedAt,
  String? notes,
}) => {
  'id': id,
  'projectId': 'p1',
  'workflowCode': code,
  'stageName': name,
  'stageOrder': order,
  'status': status,
  'requiresApproval': requiresApproval,
  'plannedStartDate': plannedStart?.toIso8601String(),
  'plannedEndDate': plannedEnd?.toIso8601String(),
  'actualStartDate': actualStart?.toIso8601String(),
  'actualEndDate': actualEnd?.toIso8601String(),
  'approvedAt': approvedAt?.toUtc().toIso8601String(),
  'approvedBy': approvedBy == null
      ? null
      : {
          'id': 'u3',
          'firstName': approvedBy.split(' ').first,
          'lastName': approvedBy.split(' ').last,
        },
  'notes': notes,
};

/// `GET /financials/dashboard`. The revenue figures are distinctive and wrong
/// on purpose (the API adds up draft and void invoices): the app must never
/// show them.
Map<String, dynamic> dashboardJson({
  int active = 7,
  List<Map<String, dynamic>>? alerts,
}) => {
  'activeProjects': active,
  'revenue': {
    'totalBilled': 987654.0,
    'totalCollected': 555555.0,
    'totalOutstanding': 424242.0,
    'monthlyBilled': 313131.0,
    'monthlyCollected': 212121.0,
  },
  'budgetAlerts':
      alerts ??
      [
        {
          'project': {'id': 'p1', 'name': 'Harare Tower'},
          'percentUsed': 92,
        },
        {
          // a second budget line of the same project, lower
          'project': {'id': 'p1', 'name': 'Harare Tower'},
          'percentUsed': 81,
        },
        {
          'project': {'id': 'p2', 'name': 'Borrowdale Villas'},
          'percentUsed': 112,
        },
      ],
  'recentInvoices': [],
};
