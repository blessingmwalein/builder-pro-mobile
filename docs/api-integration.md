# API integration

Source of truth: `builder-pro-back` source (verified by reading controllers/services). Base URL default: `https://api.ownit2buildit.com/api/v1` (same host the web app uses); override with `--dart-define=API_BASE_URL=...`.

## Conventions (verified)
- Lists: `{ "items": [...], "meta": { "page", "limit", "total" } }`. Exceptions returning plain arrays: `GET /tasks/my-queue` (≤50), `GET /messaging/conversations`, `GET /tasks/:id/comments`, `GET /projects/:id/documents`.
- **Always send both `page` and `limit`** on materials, invoices, documents, quotes, equipment, procurement, approvals, crm, employees, users lists (otherwise the server can answer 500).
- Prisma decimals arrive as **strings** (`"12.5"`). Use `J.number`.
- `POST` returns **201** (login/refresh included).
- `GET /time-tracking/active` returns an **empty 200 body** when nothing is open.
- Errors are Nest defaults: `{statusCode, message, error}`; `message` may be an array (validation). 402 adds `code`.
- Unknown body/query properties on DTO classes are rejected (400).
- Tenant: send `x-tenant-slug` (from `/auth/me`) and `Authorization: Bearer`.

## Auth
| Call | Notes |
|---|---|
| `POST /auth/login` `{email,password,companySlug?}` | 201 `{accessToken,refreshToken,tokenType,expiresIn:"15m"}`. Tokens only. `401 "Multiple accounts found…companySlug"` → ask for company code. |
| `GET /auth/me` | `{user{roles[]}, tenant{slug,defaultCurrency,timezone,…}, permissions[]}`. Returns 402 when subscription blocked. |
| `POST /auth/refresh` `{refreshToken}` | Rotates both tokens. Access TTL 15m, refresh 7d. |
| `POST /auth/forgot-password`, `/auth/reset-password` | 6-digit OTP (15 min): `{email, otp, password, companySlug?}`. |
| Logout | **No endpoint.** Delete tokens locally. |

Guard order is Jwt → Permissions → Subscription, so a user lacking permission gets 403 before any 402.

## Endpoints used by Phase 2 (worker experience)
| Feature | Endpoint | Permission(s) (any of) |
|---|---|---|
| My tasks | `GET /tasks/my-queue` | `tasks.*`, `tasks.view` |
| Task detail | `GET /tasks/:id` | same |
| Task status | `PUT /tasks/:id/status {status}` | `tasks.*`, `tasks.complete` |
| Task comments | `GET/POST /tasks/:id/comments` | GET `tasks.view`; POST `tasks.*` on the **deployed** API (`tasks.complete` too after B2) |
| Checklist toggle | `PUT /tasks/:t/checklists/:c/items/:i/toggle` | `tasks.*` deployed (`tasks.complete` too after B2). **Flips** the item: not idempotent |
| Task attachment | `POST /tasks/:id/attachments` (multipart `file`) | `tasks.*` deployed (`tasks.complete` too after B2). List rows carry no `url` |
| Clock status | `GET /time-tracking/active` | `timesheets.*`, `timesheets.view_own` |
| Clock in / out | `POST /time-tracking/clock-in`, `PUT /time-tracking/:id/clock-out` | same |
| Time list / week | `GET /time-tracking`, `GET /time-tracking/weekly-summary?weekStart=` | same / `view_all` |
| Materials | `GET /materials`, `GET /materials/logs`, `POST /materials/usage` | `materials.*`, `materials.log` |
| Messaging | `GET/POST /messaging/conversations`, `GET …/:id/messages`, `POST /messaging/messages`, `PUT …/:id/read` | `messaging.view` / `messaging.send` |
| Realtime | Socket.IO `/messaging` (auth.token), events `join-conversation`→`joined-conversation`, server `conversation-message` | JWT |
| Notifications | `GET /notifications/me`, `PATCH /notifications/:id/read {isRead}` | `settings.*` on the deployed API; any signed-in user after B1. The app treats 403 as "not available yet" |

## Endpoints used by Phase 3 (supervisors and managers)
| Feature | Endpoint | Permission(s) |
|---|---|---|
| Pending time | `GET /time-tracking?status=PENDING&page&limit` (no `workerId`) | `timesheets.*` or `timesheets.view_all` |
| Decide on time | `PUT /time-tracking/:id/approve {status: APPROVED\|REJECTED, approvalComment?}` | `timesheets.*`, `timesheets.approve` |
| Open tasks | `GET /tasks?status=<one of TODO, IN_PROGRESS, BLOCKED, REVIEW>&page=1&limit=100` (four calls) | `tasks.*`, `tasks.view` |
| Project tasks | `GET /tasks?projectId=&page=1&limit=100` | same |
| Projects | `GET /projects?page&limit&search&status`, `GET /projects/:id` (includes the team) | `projects.*`, `projects.view` |
| Assign / unassign | `POST` / `DELETE /tasks/:id/assignees/:userId` | `tasks.*`, `tasks.assign` |

Facts that shaped the design:
- `GET /projects` and `GET /projects/:id` return `baselineBudget` and `actualCost` to **anyone with `projects.view`**. The app never reads or shows them.
- `GET /time-tracking` rows include `worker`, `project` and `task`; they also include `hourlyRate` and `labourCost`, which the approval screen ignores.
- A time entry that is still clocked in is `PENDING` with no `clockOutAt`; approving it answers 400 "Cannot approve active clock-in". The app lists those as "Working now" and offers no buttons.
- `approve` only sets `status`, `approvedById` and `approvalComment`; it does not check the current status, so a decision can be overwritten by another one. That is why a repeat after an uncertain failure is safe.
- The tasks list has no "not done" or "due date" filter, so Today reads each open status separately (cap 100 each) and says when a cap was hit.
- Assignment endpoints accept **any** company user (no check that they are on the project); the app only offers project members.

## Endpoints used by Phase 4
| Feature | Endpoint | Permission(s) |
|---|---|---|
| Receivables | `GET /invoices/aging-report` | `invoices.*`, `invoices.view` |
| Money in and out | `GET /financials/summary` | `financials.*`, `financials.view` |
| Invoices | `GET /invoices?page&limit&status`, `GET /invoices/:id` | `invoices.*`, `invoices.view` |
| Quotes | `GET /quotes?page&limit&status`, `GET /quotes/:id` | `quotes.*`, `quotes.view` |
| My requests | `GET /approvals?myPending=true&page&limit`, `GET /approvals/pending/count`, `GET /approvals/:id` | `projects.*`, `materials.*` or `financials.*` |
| Decide a step | `POST /approvals/:id/steps/:stepId/decide {decision: APPROVED\|REJECTED, comment?}` | must be that step's approver |
| Create a task | `POST /tasks {projectId, title, description?, priority?, dueDate?, estimatedHours?, assigneeIds?}` | `tasks.*`, `tasks.create` |
| Edit a task | `PUT /tasks/:id {title?, description?, priority?, dueDate?, estimatedHours?}` | `tasks.*` only |

Facts that shaped the design:
- **`GET /financials/summary` adds up DRAFT and VOID invoices.** `revenueExpected`, `outstanding` and `profitMarginPct` are therefore overstated; the app does not read them. Receivables come from the aging report, which counts only sent, partly paid and overdue invoices. "Collected", "costs", "profit" and "budget left" are read as sent (money received minus costs recorded).
- Invoice detail returns the **whole client record** and each payment's raw **`providerPayload`**; the app reads only the client's name and contact person and never the payload.
- Money arrives as Prisma decimal strings (`"1150.00"`), except the summary and aging report which are plain numbers. Amounts are shown in `tenant.defaultCurrency`.
- **The approvals API carries only `entityType` + `entityId` + notes** (BUDGET, PROCUREMENT_PR, PROCUREMENT_PO, DOCUMENT, STAGE, CHANGE_REQUEST). It does not say what is being approved or for how much; the web app shows the same thin view. `GET /approvals` without `myPending=true` returns every request in the company, so the app always sends it. Step order is not enforced by the server.
- A second `decide` on the same step answers 400 ("already decided"), so it is **not** safe to repeat: after a timeout the app reads the request back and looks at its own step.
- `PUT /tasks/:id` ignores a missing `dueDate`/`estimatedHours`, so those can be changed but **not cleared** from the app. An empty `description` does clear. `POST /tasks` always creates a new task (no idempotency key).
- A new task starts as `TODO`; after a timed-out create the app looks for a `TODO` task with the same title created in the last two minutes.

## Endpoints used by Phase 5 (purchasing)
| Feature | Endpoint | Permission(s) |
|---|---|---|
| List / read purchase requests | `GET /procurement/purchase-requests?page&limit&status&projectId`, `GET /procurement/purchase-requests/:id` | `materials.*`, `materials.view` |
| Raise a request | `POST /procurement/purchase-requests {items[{description, quantity (≤3dp), unit, estimatedUnitCost? (≤2dp)}], projectId?, notes?}` → a **DRAFT** | `materials.*`, `materials.manage` |
| Submit a draft | `POST /procurement/purchase-requests/:id/submit` | `materials.*`, `materials.manage` |
| Approve / reject | `POST /procurement/purchase-requests/:id/approve`, `POST …/:id/reject {notes?}` | `materials.*`, `materials.approve` |
| List / read purchase orders | `GET /procurement/purchase-orders?page&limit&status`, `GET /procurement/purchase-orders/:id` | `materials.*`, `materials.view` |
| Record a delivery | `POST /procurement/purchase-orders/:id/deliver {deliveryDate, notes?, items[{description, materialId?, quantityOrdered, quantityReceived}]}` | `materials.*`, `materials.manage` |

Facts that shaped the design:
- Statuses: requests `DRAFT, SUBMITTED, APPROVED, REJECTED, ORDERED`; orders `DRAFT, SENT, PARTIAL, RECEIVED, CANCELLED`. The server checks the status on every change (submit needs DRAFT, approve needs SUBMITTED), so a repeated call answers 400. That makes a blind retry safe from double effects but misleading, so after a timeout the app reads the request back and tells the user what the server holds.
- **Creating a request is not idempotent** (no key). After a timeout the app lists the newest DRAFTs and accepts one only if it is the user's own, created within two minutes of the tap, with the same number of items. Otherwise it says nothing was created.
- Creating does not submit. "Submit for approval" on the form is create followed by submit; if the second call fails the draft stays and the message says so.
- **Rejecting overwrites the request's own `notes`** with the reason (`notes ?? pr.notes`; G31). Any status except DRAFT/SUBMITTED answers 400. The app offers Reject only on SUBMITTED requests.
- `estimatedUnitCost` is optional per item. The app shows an estimated total only from items that have one and says "at least" when some do not. Unit costs on a purchase **order** are real prices and are shown to anyone who can read orders.
- The order detail returns `deliveryNotes` (the app reads only how many) and the supplier's email (not read). Sending an order and receiving a delivery (`POST …/send`, `…/deliver`) change stock and supplier contact, so they stay on the web app.
- **Two ways to approve:** the procurement endpoints above, and the approvals engine (`POST /approvals/:id/steps/:stepId/decide`). The engine's `propagateEntityStatus` then sets the PR APPROVED/REJECTED (from any state) and marks an approved **PO as `SENT`**, with no company scope (G34). So deciding a purchase request or order in the Requests inbox moves the same record, and the app refreshes the purchasing lists afterwards and warns that approving an order marks it sent.
- **Recording a delivery is the riskiest write the app makes** (G37). The order must be SENT or PARTIAL (else 400). In one transaction the server writes a delivery note, adds each `quantityReceived` to the stock of its `materialId` (and logs a PURCHASE at the order line's unit cost), then sets the order RECEIVED when the *total received in this request* is at least the *total ordered in this request*, else PARTIAL. It has no idempotency key, so a repeat adds the stock again; once the order is RECEIVED a repeat is refused, but while it is PARTIAL it is not.
- So the app **sends every line the order still expects** (what was ordered minus earlier deliveries, matched by material or, for a line without one, by wording), with the outstanding quantity as `quantityOrdered` and what arrived now (possibly 0) as `quantityReceived`. Leaving a line out would let the server read a partial delivery as complete. It **caps each line at what is outstanding**, because the server compares totals: over-delivering one item would hide a shortfall on another (extra goes on the web app).
- **Never resent.** The order is re-read first (what is outstanding comes from the server as it is now, so a delivery recorded since the form opened is caught); after a timeout the order is read back and the delivery is accepted as the user's own only if it is new, by the user, made in the last two minutes, and holds exactly the quantities entered. A new delivery that is not that is reported as a conflict (someone else recorded one), never as "nothing recorded".
- Delivery dates are calendar days sent as `yyyy-MM-dd`; the order detail returns the notes with `receivedById` only (no names), so the screen says "received by you" or "by a colleague".
- Stock changes, so the Materials screen's catalogue is reloaded after a delivery.
- The Requests inbox looks the record up (`GET …/purchase-requests/:id` or `…/purchase-orders/:id`) to show "2 items · $650.00 estimated" or "supplier · total · items", only for users who hold `materials.view`. A failed or refused lookup shows nothing rather than a guess.

## Endpoints used by Phase 5 (equipment)
| Feature | Endpoint | Permission(s) |
|---|---|---|
| List equipment | `GET /equipment?page&limit&status` | `materials.*`, `materials.view` |
| Read one (with its last 10 assignments) | `GET /equipment/:id` | `materials.*`, `materials.view` |
| Assign to a project | `POST /equipment/:id/allocate {projectId, startDate, endDate?, notes?}` | `materials.*`, `materials.manage` |
| Mark returned | `POST /equipment/:id/return/:allocationId` | `materials.*`, `materials.manage` |

Facts that shaped the design:
- Statuses: `AVAILABLE, IN_USE, MAINTENANCE, RETIRED`. Allocating needs AVAILABLE and sets IN_USE; returning needs IN_USE and sets AVAILABLE. Both answer 400 otherwise, so a repeated assign is harmless.
- **A return closes the assignment id it is given and frees the item, whatever that assignment is** (G35). A stale id could free equipment that has since gone to another site. The app therefore re-reads the item first and returns only when that assignment is still open and is the item's one open assignment; after a timeout it reads back and never resends.
- Dates are calendar days. The app sends `yyyy-MM-dd` for `startDate` / `endDate` (as the web app does); the server stores UTC midnight, so they are shown by their UTC date (`Fmt.calendarDay`), not shifted into the device's time zone. `returnedAt` and `createdAt` are real instants.
- `GET /equipment` and the detail also return `dailyRate`, `purchaseCost` and `purchasedAt` (G36). The app does not read them. The detail returns only the 10 most recent assignments; an item in use whose open assignment is older than that cannot be returned from the app.
- Changing a status (maintenance, retired), adding, editing and deleting equipment, and categories stay on the web app; the app says so where relevant.
- The assign form's project list is read directly (up to 100 projects, 5 pages) and is independent of any search or filter on the Projects screen. The Purchasing form uses the same picker.

## Endpoints used by Phase 5 (project stages)
| Feature | Endpoint | Permission(s) |
|---|---|---|
| A project's stages | `GET /projects/:projectId/stages` (one plain array, not paged) | `projects.*`, `projects.view` |
| Start, complete, skip | `PATCH /projects/:projectId/stages/:stageId {status}` | `projects.*`, `projects.update` |
| Approve a stage | `POST /projects/:projectId/stages/:stageId/approve {notes?}` | `projects.*` only |

Facts that shaped the design:
- Statuses: `PENDING, IN_PROGRESS, COMPLETED, BLOCKED, SKIPPED`. The server accepts **any** status from any status and does not set the actual dates. The web app sends only `{status}` and offers three guided moves, which the app mirrors: a pending stage can be started or skipped; an in-progress stage can be completed, or, when it needs approval, approved; completed, skipped and blocked stages have no move. Because the server would let "complete" through on a stage that needs approval, the app does not offer it.
- A status change only sets one field, so after an uncertain failure it is sent **once more**; a second failure is reported.
- Approving answers 400 if the stage does not need approval or is already completed, so it is never resent: after a timeout the stages are read back and a completed stage counts as done (whoever completed it, since the approver is not reliably recorded, G38).
- Stage dates are calendar days (UTC midnight) and are shown by their UTC date.
- The approvals engine has no effect for STAGE, DOCUMENT or BUDGET requests and only sets a change request's status (G39), so the Requests inbox says what approving does for each kind in its confirmation.

## Endpoints used by Phase 5 (recording payments)
| Feature | Endpoint | Permission(s) |
|---|---|---|
| Record a payment received | `POST /invoices/:id/payments {method, amount}` (no other field: the API rejects unknown fields) | `invoices.*`, `invoices.mark_paid` |

Facts that shaped the design:
- Methods are `PAYNOW, ECOCASH, BANK_TRANSFER, CASH, CARD`. **PAYNOW and ECOCASH start a payment through the gateway** (the server asks the customer's phone to pay) instead of recording money already received, so the app never sends them. It records `CASH` and `BANK_TRANSFER` only; a manual payment is stored as received at once (reference `MANUAL-<time>`).
- **The server does not check the invoice or the amount** (G40): any status, any amount (the balance floors at 0 but `paidAmount` keeps growing), and no idempotency key, so a repeat adds the money again. The app therefore re-reads the invoice and refuses unless it is SENT, PARTIALLY_PAID or OVERDUE with a balance, refuses more than the balance as it is now, and sends the amount to the cent.
- **Never resent.** After a timeout the invoice is read back; the payment counts as the user's own only if it is new (not on the invoice before), has the same method and amount, is `SUCCESS`, and was received in the last two minutes. Any other new payment is a conflict ("a different payment was recorded"), never "done" and never "nothing recorded".
- After a payment the invoice, the invoice list, the finance summary (money collected) and the aging report (receivables) are reloaded.
- No note can be sent with a payment (the DTO forbids it).

## Endpoints used by Phase 5 (company overview)
| Feature | Endpoint | Permission(s) |
|---|---|---|
| Active projects and budget alerts | `GET /financials/dashboard` | `financials.*`, `financials.view` |
| What is owed, and how much is overdue | `GET /invoices/aging-report` (already used by Finance) | `invoices.*`, `invoices.view` |

Facts that shaped the design:
- `GET /financials/dashboard` also carries `revenue` totals and monthly figures that add up draft and void invoices (G41), so only `activeProjects` and `budgetAlerts` are read. `budgetAlerts` has **one row per budget line**, so the app keeps one entry per project (its highest percentage). Only the percentage of the budget used is shown, never the amounts.
- "Owed to you" and "overdue" come from the aging report, which counts only sent, part-paid and overdue invoices (the same source as the Finance screen).
- The two parts load and fail separately; a failed part shows "Could not load. Tap to retry" in its own tile.

## Endpoints used in the later Phase 5 batch
| Feature | Endpoint | Permission(s) |
|---|---|---|
| Mark a draft order as sent | `POST /procurement/purchase-orders/:id/send` | `materials.*`, `materials.manage` |
| A project's change requests | `GET /projects/:projectId/change-requests`, `GET …/:crId` | `projects.*` only |
| Clients | `GET /crm/clients?page&limit&search`, `GET /crm/clients/:id` | `crm.*`, `crm.view` |
| Mark a quote approved or rejected | `PUT /quotes/:id/approve`, `PUT /quotes/:id/reject {notes?}` | `quotes.*`, `quotes.approve` |
| Delay report | `GET /reporting/delays` | `reports.*`, `reports.view` |
| Productivity report | `GET /reporting/productivity` | `reports.*`, `reports.view` |

Facts that shaped the design:
- **Mark as sent** only sets the status (DRAFT → SENT); the server contacts nobody, and the screen says so. A repeat answers 400, so after a timeout the order is read back.
- **Change requests:** only `projects.*` can read them (no `projects.view` key), and they are listed on the project screen. Raising, submitting, reviewing, approving, rejecting and implementing are covered in the section on reviewing change requests below.
- **Clients:** the detail's amounts are shown only with the matching quotes / invoices key, and `financialSummary` is never read (G42). Calling and emailing use the phone's own apps (`tel:` / `mailto:` through `url_launcher`); when none can open, the number or address is shown instead.
- **Quote decisions:** `approve` and `reject` need a SENT quote and answer 400 otherwise. Approving also records the quote's material lines as used on its project (G43), which the confirmation says. After a timeout the quote is read back.
- **Reports:** only the delay and productivity reports are used because they carry days, task counts and hours but no money or pay. `GET /reporting/delays` lists active and on-hold projects with days past the end date and overdue stages; productivity lists tasks done and hours per project from approved time.

## Endpoints used in the second late Phase 5 batch
| Feature | Endpoint | Permission(s) |
|---|---|---|
| A project's budget by category | `GET /financials/projects/:projectId/budget` | `financials.*`, `financials.view` |
| A project's latest expenses | `GET /financials/projects/:projectId/transactions?page&limit` | `financials.*`, `financials.view` |
| People directory | `GET /users?page&limit&isActive&search` | `employees.*`, `settings.*` |
| Change my own name and phone | `PUT /users/me {firstName, lastName, phone}` | any signed-in user |

Facts that shaped the design:
- **The budget view is shown only to `financials.view`**, on the project screen, as totals and per-category lines with a status (on track / near limit / over budget) and percentage. The category **ledger endpoint is never used**: for the Labour category it returns each worker's hourly rate and labour cost (G44). Recent spending comes from the transactions list (the latest 10, with "See all N costs" opening the full list).
- **The directory reads only** names, email, phone, active state and role names from `GET /users`; pay, ID numbers and employment records live on the employee record and are not touched. Only active people are listed.
- **Profile update** sets the three fields it is sent (a blank phone clears it), so after an uncertain failure it is sent once more; the signed-in profile is then reloaded. The email cannot be changed.

## Endpoints used in the final Phase 5 batch
| Feature | Endpoint | Permission(s) |
|---|---|---|
| A project's documents | `GET /projects/:id/documents` | `projects.*`, `projects.view` |
| Add a document | `POST /projects/:id/documents` (multipart `file`, `type`, `name?`) | `projects.*` |
| Send a draft invoice / quote | `PUT /invoices/:id/send`, `PUT /quotes/:id/send` `{sendEmail}` | `invoices.send` / `quotes.send` (or `.*`) |
| Record where you are when clocking | `gpsInLat/gpsInLng` on `POST /time-tracking/clock-in`, `gpsOutLat/gpsOutLng` on `PUT …/clock-out` | `timesheets.*`, `timesheets.view_own` |
| Add / change equipment | `POST /equipment`, `PATCH /equipment/:id`, `GET /equipment/categories` | `materials.*`, `materials.manage` (categories: `materials.view`) |
| Add / change a client | `POST /crm/clients`, `PUT /crm/clients/:id` | `crm.*`, `crm.manage` |
| Raise and submit a change request | `POST /projects/:id/change-requests`, `POST …/:crId/submit` | `projects.*` (needs B6 deployed) |

Facts that shaped the design:
- **Documents:** the server keeps each file's web address in the `folder` column and writes uploads to its own disk (G5), so opening works only where that storage does, and an upload fails on hosting without a writable disk. The app shows the server's message and never resends an upload: after a timeout it reads the list back for a new document of the user's own with the same name. Photos from the camera or gallery, and PDF, Word and Excel files from the phone's files, can be added. Files open in the browser or a viewer through `url_launcher`.
- **Sending an invoice or quote** sets SENT and, when asked and the client has an address, emails the client. A repeat answers 400 before any email. The app makes the choice explicit (send and email it, or mark as sent without emailing) and shows the address that would be used.
- **Location on clock in/out** is off until the person turns it on (a switch on the Clock screen), asks the phone for permission, rounds to seven decimals as the API requires, and is never required: a missing permission, a switched-off service or a slow fix just means no position, and the clock event goes ahead.
- **Equipment** is added without costs (never sent); a status change is refused while the item is in use (its open assignment has to be closed first). Adding is never resent (read back after a timeout); edits and status are plain sets sent once more after an uncertain failure.
- **Clients:** adding is never resent (read back by name after a timeout); an edit sends every field with null for a blank one, so clearing works.
- **Change requests:** creating one needs the B6 backend fix (the controller read `user.id`, G38). Creating is never resent; submitting is read back after a timeout.

## Endpoints used to review change requests
| Feature | Endpoint | Permission(s) |
|---|---|---|
| Start a review | `POST /projects/:id/change-requests/:crId/review {estimatedCost?, estimatedDays?, reviewNotes?}` | `projects.*` |
| Approve | `POST …/:crId/approve {approvedCost?, approvedDays?, approvalNotes?}` | `projects.*` |
| Reject | `POST …/:crId/reject {rejectionNotes}` | `projects.*` |
| Mark as implemented | `POST …/:crId/implement` | `projects.*` |

Facts that shaped the design:
- **Status path:** DRAFT → SUBMITTED → UNDER_REVIEW → APPROVED → IMPLEMENTED, or REJECTED. Each step answers 400 when the request is not in the status it needs, so none can be repeated. After a timeout the app reads the request back: moved to the expected status just now means it went through; still in the old status means nothing was recorded (try again); any other status means a colleague got there first. Nothing is ever resent.
- **Approving changes the project.** Inside one server transaction an approved cost above zero is added to the project's baseline budget and approved days above zero push its end date later (only when it has one). The approval screen starts empty (so approving changes nothing unless the approver chooses), offers "Use the estimate", shows a live "what approving does" summary, and asks for confirmation that states both effects. After an approval the project, its budget and the company overview are reloaded.
- **Reject is offered only while a request is under review**, with a required reason, as on the web. The API would also accept rejecting an approved request, which leaves the budget changed (G47).
- **Who did it:** the controller read `user.id` (G38), so the reviewer, approver and rejecter are recorded only once B6 is deployed. The four steps themselves work without B6, and the reconcile check accepts an unrecorded person as long as the time matches.
- **Rejected requests** store the rejecter in the approver column (G47), so the screen reads "Rejected" with that name, never "Approved by".
- **Two ways to approve (G48):** the approvals inbox sets APPROVED directly and applies nothing, so its confirmation now says that and points to this screen.

## Endpoints used for documents, costs, offline saving and alerts
| Feature | Endpoint | Permission(s) |
|---|---|---|
| Document files | `POST /projects/:id/documents` (PDF, Word, Excel as well as photos; 20 MB) | `projects.*` |
| A project's cost ledger | `GET /financials/projects/:id/transactions?page&limit` | `financials.*`, `financials.view` |
| Clock events saved offline | `POST /time-tracking/clock-in {clockedInAt}`, `PUT …/:id/clock-out {clockedOutAt}` | `timesheets.*`, `timesheets.view_own` (needs B7) |
| Material saved offline | `POST /materials/usage {usedAt}`; look-up `GET /materials/logs?projectId&materialId` | `materials.*`, `materials.log` |
| Register or remove this phone for alerts | `POST /notifications/devices {token, platform}`, `POST /notifications/devices/unregister {token}` | any signed-in user (needs B8) |
| Notification list | `GET /notifications/me`, `PATCH /notifications/:id/read` | any signed-in user (needs B1) |

Facts that shaped the design:
- **Cost ledger:** only material purchases and manual entries are transactions. Labour is never one, so the list carries no pay. The category ledger stays unused (G44).
- **The server says what it understands** with a `X-Offline-Writes: 1` response header on every reply (B7). The app remembers the last answer and re-reads it from each successful reply; clock events are saved offline only while it is on.
- **What "never delivered" means:** the app treats `offline` and a connection timeout (and 429 or a failed token refresh) as nothing delivered, safe to try later. A timeout after sending, a 5xx and an unreadable reply are "may have been recorded": the write waits 60 seconds, then the server is asked for the exact moment it happened before anything is sent again. A 400, 403 or 404 is an answer: it is shown, never retried by itself.
- **Order:** the clock is one stream in the order things happened. A clock-out saved while its clock-in is still unsent waits for it and takes the entry id the server gives back. One that needs attention holds back what follows.
- **Server checks on a time from the phone:** not in the future (2 minutes of clock difference allowed), at most 7 days ago, a clock-out after its clock-in, no overlap with another of the worker's entries. The same moment again returns what was recorded instead of a new entry.
- **Alerts:** a push carries `notificationId` (the id of the notification row, so it is listed once) and `route` (an in-app path). The sender stays off until `FIREBASE_SERVICE_ACCOUNT` is set. Registering a token that another person had moves it to the person registering. Signing out first asks the server to drop the phone (best effort, 4 seconds at most) and then deletes the phone's own token, which is what actually stops alerts if there was no signal.

## Endpoints used for quotes, invoices and linking tasks to stages
| Feature | Endpoint | Permission(s) |
|---|---|---|
| Create a quote | `POST /quotes {clientId, projectId?, title, issueDate, expiryDate?, taxRate?, discountAmount?, notes?, paymentTerms?, lineItems[{category, description, quantity, unitPrice}]}` | `quotes.*`, `quotes.create` |
| Create an invoice | `POST /invoices {clientId, projectId?, quoteId?, issueDate, dueDate, retentionPct?, notes?, paymentTerms?, lineItems[{description, quantity, unitPrice}]}` | `invoices.*`, `invoices.create` |
| Mark a quote converted | `PUT /quotes/:id/convert` | `quotes.*` |
| A client's recent quotes or invoices (read-back) | `GET /quotes?clientId=`, `GET /invoices?clientId=` | `quotes.view` / `invoices.view` |
| Link a task to a stage | `stageId` on `POST /tasks` and `PUT /tasks/:id` (null unlinks) | `tasks.create` / `tasks.*` |

Facts that shaped the design:
- **Quote totals:** the server takes the discount off the subtotal first (never below zero) and then the tax from what is left. The form shows the same figures live. A quote line needs a category (Labour, Materials, Equipment, Subcontractors, Overheads, Margin, Transport, Permits, Miscellaneous, the web app's presets); an invoice line has none, and the server rejects unknown fields.
- **Invoices carry no tax or discount** (G53). Made from a quote, the form says what the quote's total was and offers to add the tax and discount as lines, so the invoice can total the same.
- **`convert` only flags the quote** (G54). The invoice is made first and the quote flagged after, with `quotes.*`; a failure to flag keeps the invoice and says so.
- **Never created twice:** after a timeout the client's newest quotes (or invoices) are read for one made in the last three minutes with the same title and total (the same total, for an invoice). The server records no creator, so that cannot be narrowed further.
- **Task stages:** a task response has the `stageId` but no stage object, so the name is looked up from the project's stage list. Unlinking sends `stageId: null`, which the server accepts.

## Endpoints used for materials, suppliers, orders and budgets
| Feature | Endpoint | Permission(s) |
|---|---|---|
| Material categories | `GET /materials/categories/list`, `POST /materials/categories {code, name}` | `materials.log` (read), `materials.manage_inventory` |
| Suppliers | `GET /materials/suppliers/list?page&limit`, `POST /materials/suppliers {name, email?, phone?, address?, website?, notes?}` | `materials.log`, `materials.manage_inventory` |
| Add / change a material | `POST /materials {name, unit, unitCost, sku?, categoryId?, supplierId?, reorderAt?, description?, stockOnHand?}`, `PUT /materials/:id` (+ `reason` when the price changes) | `materials.*`, `materials.manage_inventory` |
| Request lines | `materialId`, `unit`, `estimatedUnitCost` on `POST /procurement/purchase-requests` | `materials.*`, `materials.manage` |
| Request to order | `POST /procurement/purchase-orders {supplierId, purchaseRequestId, expectedDelivery?, notes?, items[{description, materialId?, quantity, unitCost}]}` | `materials.*`, `materials.manage` |
| Budget categories | `GET /financials/budget-categories`, `POST /financials/budget-categories {name, code}` | `financials.view`, `financials.*` |
| Set a project's budget | `PUT /financials/projects/:id/budget {lines[{categoryId, plannedAmount, thresholdPct?}]}` | `financials.*` |

| Edit a draft order (needs B9) | `PUT /procurement/purchase-orders/:id {supplierId, expectedDelivery, notes, items[]}` | `materials.*`, `materials.manage` |
| Cancel an order (needs B9) | `POST /procurement/purchase-orders/:id/cancel` | `materials.*`, `materials.manage` |
| Money for a period, per project (needs B10) | `GET /financials/overview?from&to&projectId&utcOffsetMinutes` (`from` inclusive, `to` exclusive, both the exact instants the chosen local days begin and end) | `financials.*`, `financials.view` |
| Payments collected in a period (needs B10) | `GET /financials/collections?from&to&projectId&page&limit` (successful payments on the company's invoices, newest first) | `financials.*`, `financials.view` |
| Rows behind a kind of cost (needs B10) | `GET /financials/costs?source=materials\|recorded\|purchases\|labour&from&to&projectId&page&limit&utcOffsetMinutes` | `financials.*`, `financials.view` |
| Everything behind one budget line | `GET /financials/projects/:id/budget/:categoryId/ledger` (the server includes each worker's rate for Labour; only hours and cost are kept) | `financials.*`, `financials.view` |
| Record a cost against a project's budget | `POST /financials/transactions {projectId, categoryId, description, amount, occurredAt, vendor?, reference?, notes?}` (not repeatable) | `financials.*` |
| The whole company profile | `GET /companies/me` (company, settings, sole-trader profile, sectors, project types, stakeholders, workflows) | `settings.*` |
| Change the profile, business details or settings | `PATCH /companies/me {name? description? website? businessPhone? businessEmail? city? legalName? registrationNumber? taxNumber? companySize? yearsOperating? settings{} individualProfile{}}` (only changed fields; a set, so sent once more after a lost answer) | `settings.*` |
| Change the logo | `POST /companies/me/logo` multipart field `logo` (JPEG, PNG, WebP or GIF, at most 2 MB; replaces the logo, so sent once more after a lost answer) | `settings.*` |
| What the chat server can do (needs B11) | `GET /messaging/capabilities` → `{attachments, voice, replies, mentions, unread}`; a 404 means an older server and plain text only | `messaging.*`, `messaging.view` |
| Upload a chat file (needs B11) | `POST /messaging/attachments` multipart field `file` (JPEG, PNG, WebP, GIF, PDF, Word, Excel, text, CSV, or audio such as `audio/mp4`; at most 20 MB) → `{fileKey, fileName, contentType, sizeBytes, url}`; safe to repeat | `messaging.*`, `messaging.send` |
| Send a message | `POST /messaging/messages {conversationId, body?, attachments?[{fileKey, fileName, contentType, sizeBytes, durationMs?}], replyToId?, mentionedUserIds?}` (not repeatable; the last two only when capabilities say so). Messages come back with `attachments[{url, durationMs}]`, `replyTo`, `mentionedUserIds` | `messaging.*`, `messaging.send` |
| Start a chat | `POST /messaging/conversations {type: DIRECT\|PROJECT, participantIds, projectId?, title?}`; a direct chat with someone already chatted with returns the existing one (B11) | `messaging.*`, `messaging.send` |
| People with a portal login for a client | `GET /crm/clients/:id/portal-users` | `crm.*` |
| Everyone's time on a project | `GET /time-tracking?projectId&page&limit=100` (paged to 30 pages; pay fields are never read) | `timesheets.*`, `timesheets.view_all` |
| Notifications list and unread count (needs B12 for the new parts) | `GET /notifications/me?page&limit&unread&category`, `GET /notifications/unread-count` → `{count}`; each item has `metadata{route, webRoute, event, category, entityType, entityId, projectId, actorName}` | any signed-in user (own rows) |
| Read state | `PATCH /notifications/:id/read {isRead}`, `PATCH /notifications/read-all?category`, `DELETE /notifications/:id` → `{count, unreadCount}` | own rows |
| Notification switches (needs B12 and the optional SQL) | `GET /notifications/preferences` → `{supported, categories[{category,label,inApp,push}]}`, `PUT /notifications/preferences {preferences[{category,inApp,push}]}` | own rows |
| Phone alerts | `POST /notifications/devices`, `POST /notifications/devices/unregister` (B8); a push carries `data{notificationId, route, category, event}` on Android channel `ownit2buildit_alerts` | any signed-in user |
| Web live alerts (not used by the phone) | Socket.IO namespace `/notifications` at the API origin, `auth{token, tenantSlug}`, room per user; events `notification`, `notification-read`, `notifications-read-all`, `notification-deleted`; the server closes the socket when the token expires | any signed-in user |
| Record a purchase with no order | `POST /materials/purchases {supplierId, projectId?, purchaseNumber?, purchasedAt, notes?, items[{materialId, quantity, unitCost}]}` | `materials.*`, `materials.manage_inventory` |
| List purchases | `GET /materials/purchases/list?page&limit&supplierId&projectId` | `materials.*`, `materials.log` |
| Read one material | `GET /materials/:id` | `materials.*`, `materials.log` |
| Correct a stock count | `PUT /materials/:id {stockOnHand, reason}` | `materials.*`, `materials.manage_inventory` |

| Change a project's status, details or manager | `PUT /projects/:id {status? name? description? projectType? siteAddress? startDate? endDate? clientId? projectManagerId?}` (only what changed is sent) | `projects.*` |
| Close a project (Completed) | `POST /projects/:id/close {notes?}` | `projects.*` |
| Read a person's name (the manager) | `GET /users/:id` | `employees.*` or `settings.*` |
| Choose the manager from everyone | `GET /users?page&limit&isActive&search` | `employees.*` or `settings.*` |

Facts that shaped the design:
- **Project changes are checked against the server first and read back after a lost answer.** The status, manager and details are sets, so they are safe to repeat, but the project is read first and the change refused if the status or manager is no longer what the screen showed, so a stale screen never overwrites a newer change. After a lost answer the project is read back: the new value means it arrived, the old one means it did not (nothing is resent for a status or manager), and anything else means someone else changed it. The details form sends only the fields that changed and is sent once more after a lost answer. Completed goes through the closing call, not the plain status change (G65).
- **Order edit sets the whole order; cancel is read back.** The update replaces the supplier, date, notes and every line with what is sent, so it is safe to send twice (it is sent once more after a lost answer). It is refused for anything but a draft, and the app reads the order first so a sent or cancelled one is not overwritten. Cancel answers 400 on a repeat, so after a lost answer the order is read back: cancelled means it is done. Cancelling returns the request to Approved.
- **A direct purchase is never resent.** The server cannot tell a repeat from a second purchase. The purchase carries its exact moment (to the millisecond) in `purchasedAt`; after a lost answer the supplier's purchases are read for one at that moment with the same total. Found means it arrived; not there, with the list read past that moment, means it did not; anything else is reported as unknown and the person is told to look at Purchases before trying again.
- **A stock count is an absolute set with a reason, never `stock-adjust`** (which adds a quantity with no reason, G61). The stock is read first and the correction refused if it has moved since the screen opened. After a lost answer the stock is read back, not resent: the counted figure means it arrived, the old figure means it did not.
- **The category lists are the web app's.** The server adds its standard categories (material and budget) the first time they are read, and a new one made on the phone is the same record the web app shows. Units are free text on the server, so the app offers a construction list and keeps any unit already stored.
- **A price change needs a reason.** The server refuses a changed `unitCost` or `stockOnHand` without one and keeps an audit entry, so the edit form asks. Stock is not edited here: it moves with deliveries and use.
- **Creating an order:** the request must be APPROVED and becomes ORDERED, so a repeat answers 400 and nothing is resent; after a timeout the request is read back and ORDERED with an order on it means it went through. Lines carry the catalog `materialId`, which is what makes a delivery add to stock (a line with none changes no stock, and the form says so).
- **A budget is set, not added to.** Saving sets the planned amount of each category given (an upsert), so it is safe to send twice. A category left blank that has no line is not sent; one that has a line and is blanked is sent as zero. Spending (`actualAmount`) is never typed: the server adds it up as material is used and bought.

## Payload facts
- Clock-in: `{projectId, taskId?, gpsInLat?, gpsInLng?}`; duplicate open entry → 400 "Open time entry already exists. Clock out first." Server stamps time; **no client timestamp/idempotency key**.
- Clock-out: `{breakMinutes?, gpsOutLat?, gpsOutLng?}`.
- Weekly summary: the server does `new Date(weekStart)` and sums a 7-day window. The app sends the worker's **local Monday 00:00 as an ISO instant** (e.g. `2026-10-25T22:00:00.000Z` for Harare), not a bare date: a bare date is read as UTC midnight and shifts early-morning shifts into the previous week. Invalid values give 500; omitted means *today*, not Monday.
- Time entries list: users with `timesheets.*`/`view_all` receive every worker's entries unless `workerId` is sent, so the app always sends its own `workerId`.
- Material usage: `{projectId, materialId, quantity (≤3dp), unitCost (≤2dp, REQUIRED), supplierId?, notes?, usedAt?}`; stock may go negative.
- Task status values: `TODO, IN_PROGRESS, BLOCKED, REVIEW, DONE`; the server accepts any transition.
- Attachments: ≤20 MB, jpeg/png/webp/pdf/doc/docx. **HEIC is rejected.** Content-Type of the part must be correct.
- Messages: page 1 = newest page, oldest→newest within it. `GET /messaging/conversations` returns **every PROJECT channel of the company** plus the user's direct chats. There is no unread count and DIRECT conversations have no participant names. `PUT …/:id/read` upserts one receipt per message (call once per open).
- Material logs have **no user column**; `GET /materials/logs` is company-wide, so the app does not offer a "my logs" list.

## Error mapping (client)
`AppException.kind`: offline, timeout (not delivered), **uncertain** (send/receive timeout — may have been saved), unauthorized, forbidden, notFound, validation, conflict, subscription, rateLimited, server, malformed.
- 403 text is replaced by a safe generic message.
- `outcomeUnknown` writes are reconciled by reading server state before any retry.
