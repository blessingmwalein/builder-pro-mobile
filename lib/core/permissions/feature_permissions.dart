/// Feature → permission keys. Ported from `builder-pro-web/lib/permissions.ts`
/// (`FEATURE_PERMS`), the web app's single source of truth, so both clients
/// agree on who can see/do what. Each list is OR logic.
///
/// Phase 2 additions are marked; they follow the backend controller keys.
abstract final class Feature {
  // Projects
  static const projects = ['projects.*', 'projects.view'];
  static const projectsCreate = ['projects.*', 'projects.create'];
  static const projectsManage = ['projects.*'];

  // Tasks
  static const tasks = ['tasks.*', 'tasks.view'];
  static const tasksCreate = ['tasks.*', 'tasks.create'];

  /// Changing a task's details: the API accepts only `tasks.*` for this.
  static const tasksEdit = ['tasks.*'];
  static const tasksAssign = ['tasks.*', 'tasks.assign'];
  static const tasksComplete = ['tasks.*', 'tasks.complete'];

  /// Comments, checklist toggles and attachments: the deployed backend accepts
  /// only `tasks.*`. Backend change B2 (builder-pro-back, not yet deployed) also
  /// accepts `tasks.complete`; add it here once B2 is live so workers see the
  /// actions only when they work.
  static const tasksCollaborate = ['tasks.*'];

  // Time
  static const timesheets = [
    'timesheets.*',
    'timesheets.view_own',
    'timesheets.view_all',
  ];
  static const timesheetsOwn = ['timesheets.*', 'timesheets.view_own'];
  static const timesheetsApprove = ['timesheets.*', 'timesheets.approve'];
  static const timesheetsViewAll = ['timesheets.*', 'timesheets.view_all'];

  /// Deciding on time needs BOTH: the approve route, and the right to list
  /// other people's entries (the list endpoint returns only the caller's own
  /// without `view_all`). `timesheets.*` covers both.
  static const List<List<String>> approvals = [
    timesheetsApprove,
    timesheetsViewAll,
  ];

  // What separates a supervisor or manager from a field worker. The mobile
  // overview screens (Today, Projects, Approvals) are shown only to people who
  // hold one of these, because the API still returns company-wide lists to
  // anyone with `projects.view` (backend change B4 is not deployed).
  static const supervise = [
    'projects.*',
    'tasks.*',
    'timesheets.*',
    'timesheets.approve',
  ];

  /// Project overview: may view projects AND supervises work.
  static const List<List<String>> projectsOverview = [projects, supervise];

  /// Assigning people to tasks: needs the assign right AND the project team
  /// (served with the project, so `projects.view`) to choose from.
  static const List<List<String>> assignTasks = [tasksAssign, projects];

  // Materials
  static const materials = ['materials.*', 'materials.log'];
  static const materialsLog = ['materials.*', 'materials.log'];
  static const materialsManage = ['materials.*', 'materials.manage_inventory'];

  // Purchasing (procurement API). These keys are NOT the same as `materials.log`
  // that field workers hold, so workers never see purchasing.
  static const purchasingView = ['materials.*', 'materials.view'];
  static const purchasingManage = ['materials.*', 'materials.manage'];
  static const purchasingApprove = ['materials.*', 'materials.approve'];

  // Project stages: reading needs the project read key; starting, completing and
  // skipping needs `projects.update`; approving a stage needs `projects.*`.
  static const stagesView = ['projects.*', 'projects.view'];
  static const stagesUpdate = ['projects.*', 'projects.update'];
  static const stagesApprove = ['projects.*'];

  /// Adding a document to a project: the API accepts `projects.*` only.
  static const documentsUpload = ['projects.*'];

  /// A project's change requests: the API accepts `projects.*` only.
  static const changeRequests = ['projects.*'];

  // Equipment (the equipment API reuses the same `materials.*` read / manage keys).
  static const equipmentView = ['materials.*', 'materials.view'];
  static const equipmentManage = ['materials.*', 'materials.manage'];

  // Messaging
  static const messaging = ['messaging.*', 'messaging.view'];
  static const messagingSend = ['messaging.*', 'messaging.send'];

  /// The finance screens (overview, invoices, quotes). Anyone holding one of
  /// these is a finance user for navigation ordering.
  static const finance = [
    'financials.*',
    'financials.view',
    'invoices.*',
    'invoices.view',
    'quotes.*',
    'quotes.view',
  ];

  /// The approvals inbox (`/approvals` API: multi-step requests such as purchase
  /// orders and change requests). The controller accepts any of these.
  static const requests = ['projects.*', 'materials.*', 'financials.*'];

  // Financial / office features (used by later phases and the More menu)
  static const quotes = ['quotes.*', 'quotes.view'];

  /// Marking a sent quote approved or rejected.
  static const quotesApprove = ['quotes.*', 'quotes.approve'];
  static const invoices = ['invoices.*', 'invoices.view'];

  /// Sending a draft invoice (or quote) to the client.
  static const invoicesSend = ['invoices.*', 'invoices.send'];
  static const quotesSend = ['quotes.*', 'quotes.send'];

  /// Recording a payment received (cash or bank transfer).
  static const invoicesRecordPayment = ['invoices.*', 'invoices.mark_paid'];

  /// Adding and changing materials, categories and suppliers.
  static const materialsInventory = [
    'materials.*',
    'materials.manage_inventory',
  ];

  /// Reading categories and suppliers (the same key as logging material).
  static const materialsReference = ['materials.*', 'materials.log'];

  /// Setting a project's budget per category (the web app's "Edit Budget").
  static const financialsManage = ['financials.*'];

  /// Creating a quote or an invoice (as drafts; sending is separate).
  static const quotesCreate = ['quotes.*', 'quotes.create'];
  static const invoicesCreate = ['invoices.*', 'invoices.create'];

  /// Marking an approved quote as converted once its invoice exists. The
  /// endpoint needs the full `quotes.*` key, unlike creating a quote.
  static const quotesConvert = ['quotes.*'];
  static const financials = ['financials.*', 'financials.view'];
  static const employees = ['employees.*', 'employees.manage'];

  /// The people directory (`GET /users` accepts these two keys).
  static const team = ['employees.*', 'settings.*'];
  static const crm = ['crm.*', 'crm.view'];

  /// Adding and changing clients.
  static const crmManage = ['crm.*', 'crm.manage'];

  /// A client's portal logins (who can be messaged): the server needs the full
  /// `crm.*` key for them.
  static const clientPortal = ['crm.*'];
  static const documents = ['documents.*', 'documents.view'];
  static const reports = ['reports.*', 'reports.view'];
  static const settings = ['settings.*'];
}
