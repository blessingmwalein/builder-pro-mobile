# Architecture

ownit2buildit Mobile is a Flutter app (Android + iOS) for the existing BuilderPro platform. It is a **client only**: all business rules, authorisation and data live in `builder-pro-back`.

## Verified vs assumed
- **Verified** (read from source): API prefix, auth contract, permission model, response shapes listed in `api-integration.md`.
- **Assumed** (not yet exercised against the live server): hosted API (`builder-pro-back.vercel.app`) behaves like the local source (e.g. file uploads, WebSockets — see `backend-gaps.md`).

## Layers

```
lib/
├── main.dart                  ProviderScope (provider retry disabled: writes must never repeat silently)
├── app/
│   ├── app.dart               MaterialApp.router, light/dark themes, permission re-check on resume
│   ├── router/                GoRouter, destinations (permission-driven), redirect rules (route_guard.dart)
│   ├── shell/                 Bottom bar (phones) / side rail (tablets), offline banner
│   └── theme/                 tokens.dart, app_colors.dart (light+dark), app_typography.dart, app_theme.dart
├── core/
│   ├── config/                AppConfig (--dart-define=API_BASE_URL)
│   ├── network/               ApiClient (Dio): auth headers, single-flight refresh, 402 event, error mapping
│   ├── auth/                  models, AuthRepository, SessionController (Riverpod Notifier), SessionState
│   ├── permissions/           PermissionEvaluator (mirrors backend guard), Feature maps (from web FEATURE_PERMS)
│   ├── storage/               TokenStore (flutter_secure_storage / in-memory for tests)
│   ├── offline/               AppDatabase (Drift/SQLite): per-user cache, outbox, wiped on sign-out
│   ├── errors/                AppException + mapper
│   ├── providers.dart         app-wide providers: API client, session, database, connectivity, resume tick
│   └── utils/                 J (tolerant JSON), Fmt (dates, durations, quantities), Validators
├── features/<feature>/
│   ├── data/                  models + repository (+ local store / outbox where needed)
│   ├── application/           Riverpod controllers (state, reconcile logic, offline fallback)
│   └── presentation/          screens and feature widgets
│   (authentication, settings, time, tasks, materials, messaging, projects, approvals, finance, requests, purchasing, equipment, stages)
└── shared/
    ├── components/            design-system widgets used by every feature (list_widgets.dart: StatusFilterRow, pagedRows, AdaptiveRow)
    ├── state/                 PagedCatalog: first page, filter, show more, stale-reply guard (invoices, quotes, requests, purchasing)
    └── services/              platform wrappers behind interfaces (photo picker)
```

Rule: **no network calls in widgets.** Widgets read Riverpod providers; providers call repositories; repositories call `ApiClient`.

## Key decisions
| Decision | Reason |
|---|---|
| Permissions, not role names, drive everything | Owners create custom roles; the web app already works this way (`builder-pro-web/lib/permissions.ts`). |
| One `PermissionEvaluator` mirroring `PermissionsGuard` | A *required* `x.*` is satisfied only by holding `x.*`; held `x.*` satisfies any `x.y`. Unknown/empty fails closed. |
| UI gating is convenience, not security | The backend authorises every request; mobile never filters company-wide data client-side to "secure" it. |
| Hand-written tolerant JSON models (no codegen) | API returns decimals as strings, empty 200 bodies, plain arrays on some lists. |
| Single-flight token refresh | Refresh tokens rotate; concurrent refreshes would invalidate each other. |
| A refresh that fails because of the network never signs the user out | Sites have poor signal. Only a definite 400/401/403 from `/auth/refresh` ends the session. |
| Cached `/auth/me` for offline start | Lets a worker open the app with no signal; backend still authorises each call once online. |
| Non-idempotent writes are never queued silently | Backend has no idempotency keys for clock-in/out or material usage (see `backend-gaps.md`). |
| Riverpod provider retry disabled | Automatic retry could repeat a write. |
| After an uncertain write the server is asked what happened (`ClockController`, `MaterialUsageActions`, `ThreadController`) | A timeout after sending does not mean it failed. Repeating clock-in/usage/message could create a duplicate; reporting failure could hide a saved record. If the server cannot be asked, the UI says the outcome is unknown. |
| Only idempotent writes are queued offline (task status) | "Set status to X" can be replayed safely. A checklist toggle flips state, so it is never retried. |
| Cached data and the outbox are keyed by user and wiped on sign-out/expiry | A shared phone must never show the previous person's tasks. |
| A refusal (403/404/400) never falls back to cached data | Only connection trouble does; otherwise a user who lost access would keep seeing old data. |
| Realtime is an optimisation, polling is the guarantee | Serverless hosting cannot keep WebSockets open; the thread polls every 8 s while the socket is down. |
| Writes that cannot be repeated safely are reconciled by reading the server (clock in/out, material usage, new task, request decisions); writes that only set a value are sent once more (approving time, assigning, editing a task) | Matches what each endpoint tolerates. A request decision answers 400 the second time, so it is checked, not resent. |
| Money is formatted in the company currency, and only fields the API sends reliably are shown | The financial summary adds draft and void invoices; the app takes receivables from the aging report instead (`backend-gaps.md` G27). |
| Procurement writes are checked against the server's status, not resent (`PurchasingActions`) | Creating a request has no idempotency key, and submit / approve / reject answer 400 when repeated. After a timeout the request (or the newest own DRAFT) is read back and the message says what the server holds. A failed submit after a successful create keeps the draft. |
| The Requests inbox looks up what a purchase request or order is (`requestContextProvider`) | The approvals API carries only a type and an id. The lookup runs only for people who can read purchasing and shows nothing when it fails, so an approver is never shown a guess. Deciding there also refreshes the purchasing lists, because the approvals engine changes the same record (`backend-gaps.md` G34). |
| Location is opt-in and can never block the clock (`LocationService`, `ClockLocationPreference`) | Clocking in is the most-used write. A missing permission, a switched-off service or a slow fix returns no position and the clock event goes ahead; the choice is a personal switch kept on the phone. |
| Sending to a client states the consequence first (`SendToClientButton`) | Sending can email someone outside the company, so the person chooses between emailing and only marking as sent, and sees the address. |
| The budget view skips the category ledger (`ProjectBudgetSection`) | The ledger for the Labour category carries every worker's pay (G44); the budget totals and the expense list are enough and are not sensitive beyond `financials.view`. |
| Quote decisions are plain status sets that are read back, never resent (`QuoteActions`) | `approve` / `reject` answer 400 when repeated, and approving also logs material usage on the server (G43), which the confirmation states. |
| Calling and emailing go through a small interface (`ContactLauncher`) | The `url_launcher` plugin stays behind it, like the photo picker, so screens can be tested without a platform and fall back to showing the number when no app can open it. |
| The company overview reads only the dashboard fields that are right (`CompanyDashboard`) | The dashboard reply mixes reliable fields (active projects, budget alerts) with revenue totals that include drafts and void invoices (G41). Owed and overdue come from the aging report instead, and budgets are shown as a percentage, never an amount. |
| Payments are checked, to the cent, and never resent (`PaymentActions`) | The payment endpoint checks neither invoice status nor amount, has no idempotency key, and starts a gateway charge for PayNow / EcoCash (`backend-gaps.md` G40). The app records cash and bank transfers only, re-reads the invoice, checks status and balance, and after a timeout looks for a payment of its own (new, same method and amount, received, recent). |
| Deliveries are sent whole, capped, and never resent (`PurchasingActions.receiveDelivery`) | The delivery endpoint adds to stock on every call, has no idempotency key, and judges "received in full" from the totals of that one request (`backend-gaps.md` G37). The app re-reads the order, sends every outstanding line, refuses more than is outstanding, and after a timeout looks for a delivery of its own (new, mine, recent, same quantities) before saying anything. |
| Stage moves mirror the web's guided moves and send a status once more, never an approval twice (`StageActions`) | The server accepts any status from any status, so the app offers only the moves that fit (and never "complete" on a stage that needs approval). A status is a plain set, so one retry is safe; an approval answers 400 the second time, so it is read back. |
| Approving a change request is its own screen that states its effect (`ChangeRequestDecisionScreen`, `changeApprovalEffect`) | An approval adds money to a project's budget and moves its end date, and cannot be undone from the app. The cost and days start empty so a quick approval changes nothing, the screen shows what the typed numbers will do, and a confirmation repeats it. |
| The project page is tabs with sheets, not one long column | A project has many parts (tasks, stages, budget, changes, documents, team, client). One scroll through all of them hides what matters. A pinned row of tabs (only the ones a person may open), an Overview whose tiles each open their tab, and bottom sheets for details and team keep every part one tap away. |
| Materials, categories, suppliers and units follow the web app's data (`MaterialManagement`, `material_units.dart`) | Categories and suppliers are the company's own records, so a new one made on the phone is the one the web app shows. Units are free text on the server, so the app offers a construction list and never rewrites a stored unit. |
| The Gantt chart is one widget fed by tasks, with its date maths apart (`gantt_layout.dart`) | The same chart serves My Tasks and a project's Tasks tab. Dates are whole calendar days (days since 1970) so a clock change can never move a bar a day, and the window, bar and placement rules are plain functions that can be tested without drawing anything. It is laid out for a phone: each task is a full-width row (name, status, dates) with its bar on a strip underneath, and the period always fits the screen's width, so there is no name column and no sideways scroll. Row heights follow their content, so large text makes a row taller instead of overflowing it. Each bar takes a colour from `AppColors.series` by its place in start-date order (`GanttBar.slot`), so neighbours differ and a task keeps its colour from one period to the next. |
| The costs on the money pages are material used + recorded costs + labour; purchases are listed, not added | The server's budgets count material when it is used and costs when they are recorded; a purchase for a project is also recorded as a cost, so adding it to the used material would count the same material twice. Labour is added because the question asked for it, though the server's own cost figure leaves it out (G68), and the page says so. |
| Labour is added up on the server and never itemised | The cost rows for labour come per day and project with hours and how many people, so nobody's name or pay rate reaches the phone. The older ledger endpoint for a Labour budget line does send them (G44), so the app keeps only hours and cost from it and drops the rest while reading. |
| A period is whole local days sent as exact instants | The phone turns the chosen days into the instants they begin and end where the person is, and sends its offset so labour lands on the right local day. A payment late in the evening stays on its own day instead of moving with UTC. |
| Recording a cost is never resent | A repeat would count the cost twice and the server cannot tell a repeat from a second cost, so the app reads the project's costs back for one with the same description, amount and exact moment instead of sending again. |
| Light or dark is read before the app starts | The choice is stored with the small on-device settings and loaded in `main()` before the first frame, then handed to the controller as its starting value, so the app never paints in the wrong colours first. It belongs to the phone, not the account, because the sign-in screen needs it too. |
| Company edits send only what changed, and a settings change is confirmed | `PATCH /companies/me` sets fields, so sending only the changed ones cannot overwrite what someone else changed meanwhile, and a resend after a lost answer is harmless. Settings affect the whole company, so they list each change in a confirmation first. |
| The chat asks the server what it can do, and falls back to plain text | `GET /messaging/capabilities` is read when a chat opens. An older server (404) gets text only and the attach and microphone buttons explain that photos, files and voice need the update; a server without the optional table keeps replies in the message text as a first line `> Name: words`, which the app shows as a quote, and tags stay plain `@Name` text. Nothing is sent that the server would refuse. |
| A voice message is a file | The recorder writes an `.m4a` (AAC); it is uploaded like any file and sent as an attachment with its length, so no new message type is needed. One player is shared by the whole chat so two voice messages never play at once. |
| A message is uploaded first, then sent, and only the send is not repeated | Files are uploaded (safe to repeat; the server answer is kept, so a retry does not upload again); the message that names them is sent once. After a lost answer the thread is read back for a message from me with the same text and number of files before offering a resend. |
| A direct chat is looked for before it is made | The conversation list is read fresh and an existing chat with that person is opened; only then is one created, and after a lost answer the list is read again. Newer servers also return the existing chat themselves. |
| Time stats are worked out on the phone from the time list, by a pure function | The project's time entries are paged (up to 3000) and added up by local day; pay fields in the reply are dropped at parse time. A server summary would be lighter but would need a deploy. |
| Alerts are described once and sent from one place | `events.ts` names each event with its category, title and the route on the phone and on the web; services only call a one-line method on `ActivityNotifier` after their main write. The message, the category and who is told live together, so the rule for "who hears about a time entry" is in one place and tested. |
| Who is told comes from permissions, not role names | There is no owner flag and roles can be renamed, so owners are the holders of `settings.*` and managers of `projects.*`, worked out with the same `holds()` the permission guard uses. A project's manager field is not trusted (it can name an inactive or outside person); it is checked against the active people, and a project with no valid manager falls back to everyone who manages projects. |
| An alert never fails the action | Alerts run after the data is saved, outside transactions, inside a safe wrapper, with a 4 second cap; a failure is only logged. Replays (a phone resending an offline clock-out) send nothing. |
| The type is a legal old value; the meaning lives in the data | The notification type column is a database enum, so new events use an existing value (or `GENERAL`, with a retry if the database refuses one) and carry the real event and category in `metadata`. The phone and the web read that, so no enum migration is needed. |
| Muting is optional infrastructure | Switches live in one new table; if it is missing every alert stays on and the screens say "needs an update". A muted category still stores nothing for that person and sends no push. |
| The web is told over a socket, the phone over Firebase | The phone is mostly asleep, so it gets push and refreshes on resume; the web keeps a socket (a room per user) for the bell, and read, mark-all and delete changes are broadcast so every open tab and the unread count stay true. A read on the phone reaches the web bell at once (the same server call broadcasts it); a read on the web reaches the phone when the app is next opened or resumed. |
| Direct purchases, stock counts and order edits follow the same safety rules as the rest | A purchase adds stock and cost, so it is never resent and is found again by its exact moment; a stock count is an absolute set with a reason and is refused if stock moved; an order edit sets the whole order so it can be repeated, and a cancel is read back. See `api-integration.md`. |
| Completed is a closing step, not a status choice (`ProjectActions.close`) | The plain update only sets the word "Completed"; closing also records the end date, 100% and a final cost summary. The app always uses the closing call for Completed, like the web app, and tells the person what it does. |
| A request becomes an order from the request's own page (`createOrder`), and the order line carries the material id | The server flips the request to Ordered, which makes a repeat refuse itself, so it is read back rather than resent. The material id is what lets a delivery add to stock. |
| A quote is flagged converted only after its invoice has been made (`QuoteInvoiceActions.createInvoice`) | The server's convert call only flips a status. Doing it first, as the web app does, leaves a converted quote with no invoice whenever the form is abandoned or the invoice call fails. |
| Offline saving is a separate, append-only queue (`WriteQueue`, `queued_writes`), not the task-status outbox | The outbox keeps one "latest value wins" row per target, which would merge two clock-ins. Events are never merged, are sent oldest first within a stream, and carry the time they happened so the server can be asked for that exact moment before a resend. |
| Clock events are saved offline only after the server has said it can read their time (`X-Offline-Writes`) | A server that cannot would stamp the time of sending: wrong hours and wrong pay, silently. Until it is deployed the feature stays off rather than guess. |
| A refusal is an answer and an unanswered send is not | Retrying a refusal never helps and an unanswered send may have landed, so the first waits for the person and the second waits, then looks, then (only if it is not there) sends again. |
| Signing out with unsent entries asks first; an expired session keeps them | They are the person's own time and material. Only a deliberate sign-out may discard them. |
| Alerts are opt-in, only open screens inside the app, and sign-out stops them (`PushController`, `safeAppRoute`) | An alert comes from outside the app and must not be able to send it anywhere else; a signed-out phone must not keep receiving a person's alerts even if the server could not be reached, so the phone's own token is deleted too. |
| The approve confirmation says what approving does for each kind of request (`approvalEffect`) | The approvals engine only moves purchase requests and orders and part-handles change requests; stages, documents and budgets are not changed at all (G39). A one-tap approval must not promise more than it does. |
| Equipment returns re-read the item first (`EquipmentActions`) | A return closes the assignment id it is given and frees the item whatever that is (`backend-gaps.md` G35), so a stale screen could free equipment that has gone to another site. The app re-reads, returns only the one open assignment, and after a timeout reads back instead of resending. |
| Calendar days are shown by their UTC date (`Fmt.calendarDay`) and sent as `yyyy-MM-dd` | The server keeps them at UTC midnight; formatting through the device time zone shifts them a day behind UTC. |
| One project picker (`chooseProject`) reads its own pages | The Projects screen's list carries whatever search / filter the user last used; a form picker reading that list silently offered a subset. |
| Detail screens open on the root navigator | They cover the bottom bar (more room for the keyboard and composer). Deep links are still permission-checked by prefix. |

## Session lifecycle
`bootstrapping → (no tokens) unauthenticated | (tokens) /auth/me →`
`authenticated | subscriptionBlocked (402) | expired (refresh rejected) | startupFailed (offline, no cache)`.
Logout/expiry clears secure storage and runs `SessionCleanup` hooks (local DB, drafts, queue) so the next user sees nothing of the previous one.

## Offline model
```
network ok  -> fetch -> cache (per user) -> show
network bad -> show cached copy with a banner ("Offline. Showing tasks saved at 14:05")
               nothing cached -> error panel with Retry
status change -> try server; connection trouble -> outbox + show immediately ("Waiting to send");
                 refusal -> show the reason, queue nothing
connection back / app resumed -> flush outbox oldest first, then reload
```
Tables: `CachedRecords(userId, scope, recordKey, json, position, fetchedAt)` and `OutboxOps(id, userId, kind, targetId, payload, attempts, status, lastError)`. After editing the tables in `app_database.dart` run `dart run build_runner build`.

## Navigation
Each destination declares the permission groups it needs (AND of ORs) and one rank per persona (manager, finance, field). `planNavigation(permissions)` keeps the allowed ones and picks up to four for the bottom bar: field order (Clock, My Tasks, Materials, Messages) for most people, overview order (Today, Projects, Approvals, Messages, then My Tasks, Clock, Materials) for anyone holding a supervisory key. The rest appear under More → Also in the app, and More stays highlighted while one of them is open. More is always last. `computeRedirect` guards every location (including deep links and notification taps) with the same rules and sends forbidden targets to `/denied`.

## Theming
Brand colours come from `builder-pro-web/app/globals.css` (brick red `#760f1b`, Inter). The dark palette is hand-tuned. All colours/spacing/radii live in `app/theme/`; screens never hard-code them.

## Platform notes
- Android: debug APK builds with Android Studio's JDK 21 (`flutter config --jdk-dir`).
- iOS: project is configured but **cannot be built or verified on this Windows machine**.
