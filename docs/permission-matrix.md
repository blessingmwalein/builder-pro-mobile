# Permission matrix

The app decides what to show from the **effective permission keys** in `GET /auth/me`, never from the role name. Role names below are only the backend's default seeds (`SYSTEM_ROLES` in `builder-pro-back/src/onboarding/onboarding.service.ts`); owners can create custom roles with any combination.

## Matching rule (mirrors `PermissionsGuard`)
- Held key equals required key → allowed.
- Held `module.*` satisfies any required `module.something`, **including** a required `module.*`.
- A *required* `module.*` is **not** satisfied by a specific held key (e.g. holding `tasks.complete` does not satisfy a route that lists only `tasks.*`).
- Lists use OR logic. Empty/unknown fails closed.

## Default roles
| Role | Permissions |
|---|---|
| Owner | `projects.* tasks.* timesheets.* materials.* quotes.* invoices.* financials.* employees.* settings.* crm.* reports.* messaging.* documents.*` |
| Project Manager | Owner minus `settings.*` |
| Site Supervisor | `projects.view tasks.* timesheets.* materials.* messaging.* documents.*` |
| Worker | `projects.view tasks.view tasks.complete timesheets.view_own materials.log messaging.*` |
| Accountant | `invoices.* financials.* quotes.view reports.*` |
| Client | `projects.view quotes.view invoices.view` (external clients; not in the first mobile release) |

## Mobile destinations → permission
Each destination lists groups of keys; **every group** needs one satisfied key (AND of ORs). `PermissionEvaluator.satisfies` implements it.
| Destination | Keys |
|---|---|
| Clock (`/clock`) | `timesheets.*`, `timesheets.view_own` |
| My Tasks (`/tasks`) | `tasks.*`, `tasks.view` |
| Materials (`/materials`) | `materials.*`, `materials.log` |
| Messages (`/messages`) | `messaging.*`, `messaging.view` |
| Today (`/today`) | any of `projects.*`, `tasks.*`, `timesheets.*`, `timesheets.approve` ("supervises work") |
| Projects (`/projects`) | (`projects.*` or `projects.view`) **and** supervises work |
| Approvals (`/approvals`) | (`timesheets.*` or `timesheets.approve`) **and** (`timesheets.*` or `timesheets.view_all`) |
| Finance (`/finance`) | `financials.*`, `financials.view`, `invoices.*` or `invoices.view` (each section of the overview needs its own key) |
| Invoices (`/invoices`) | `invoices.*`, `invoices.view` |
| Quotes (`/quotes`) | `quotes.*`, `quotes.view` |
| Requests (`/requests`) | `projects.*`, `materials.*` or `financials.*` (the approvals API accepts any of them) |
| Team (`/team`) | `employees.*`, `settings.*` (the users list accepts these two) |
| Clients (`/clients`) | `crm.*`, `crm.view` |
| Reports (`/reports`) | `reports.*`, `reports.view` |
| Purchasing (`/purchasing`) | `materials.*`, `materials.view` (the procurement API's read key) |
| Equipment (`/equipment`) | `materials.*`, `materials.view` (the equipment API reuses it) |
| More (`/more`) | any signed-in user |

**Navigation order depends on a persona derived from permissions** (never from the role name):
- *manager* (holds a supervisory key): Today, Projects, Approvals, Messages, then My Tasks, Clock, Materials, Purchasing, Equipment, Requests, Finance, Invoices, Quotes under More;
- *finance* (holds a finance key, no supervisory one): Finance, Invoices, Quotes, Messages/Requests, then Purchasing and Equipment under More;
- *field*: Clock, My Tasks, Materials, Messages (Purchasing and Equipment last, if they hold `materials.view`).
An Owner who also holds finance keys is a manager first.

**Why Projects is not simply `projects.view`:** the Worker role holds `projects.view`, and until backend change B4 is deployed `GET /projects` returns every project of the company to anyone who holds it. A Projects tab for workers would widen what they can see on mobile, so the overview screens require a supervisory permission as well.

**Why Approvals needs two groups:** `PUT /time-tracking/:id/approve` accepts `timesheets.approve`, but `GET /time-tracking` returns only the caller's own entries unless they hold `timesheets.*` or `timesheets.view_all`. A role with only `timesheets.approve` could decide but never see anyone else's time.

## What each default role gets in the app today
| Role | Bottom bar | Notes |
|---|---|---|
| Owner / PM / Site Supervisor | Today, Projects, Approvals, Messages, More | Overview first. Clock, My Tasks and Materials are under **More → Also in the app**. Finance, CRM, documents etc. are listed as "on the web app for now". |
| Worker | Clock, My Tasks, Materials, Messages, More | Task comments / checklist toggles / photo attachments are **hidden** because the deployed API requires `tasks.*` for them (backend change B2 pending). |
| Accountant | Finance, Invoices, Quotes, Requests, More | Read-only finance. Reports, settings etc. are listed as "on the web app for now". |
| Custom (e.g. only `tasks.view`+`messaging.view`) | My Tasks, Messages, More | Handled by the same registry; no new code per role. |

## Action-level gating
| Action | Required (any of) |
|---|---|
| Clock in / out | `timesheets.*`, `timesheets.view_own` |
| Change task status | `tasks.*`, `tasks.complete` |
| Comment / checklist / attach photo | `tasks.*` (until B2 deployed) |
| Approve / reject time | `timesheets.*`, or `timesheets.approve` together with `timesheets.view_all` |
| Add a task to a project | `tasks.*` or `tasks.create` |
| Edit a task's title, description, priority, due date, estimate | `tasks.*` only (the API accepts nothing else) |
| Approve / reject a request in the Requests inbox | being the approver named on that step (the server checks); any of `projects.*`, `materials.*`, `financials.*` to open the inbox |
| Change who is assigned to a task | `tasks.*` or `tasks.assign`, **and** `projects.*` or `projects.view` (the project team is the list to choose from) |
| Log material usage | `materials.*`, `materials.log` |
| See purchase requests and orders | `materials.*`, `materials.view` |
| See equipment and where it is | `materials.*`, `materials.view` |
| Assign equipment to a project, mark it returned | `materials.*`, `materials.manage`; assigning also needs `projects.*` or `projects.view` (a project to choose) |
| Raise a purchase request, submit a draft | `materials.*`, `materials.manage` |
| Approve / reject a submitted purchase request | `materials.*`, `materials.approve` |
| Record a delivery against a sent or part-received order | `materials.*`, `materials.manage` |
| Record a payment received (cash or bank transfer) | `invoices.*`, `invoices.mark_paid` |
| See the company overview on Today (active projects, budget alerts) | `financials.*`, `financials.view` (and being on Today: a supervisory key) |
| See what is owed on Today | `invoices.*`, `invoices.view` |
| Mark a draft purchase order as sent | `materials.*`, `materials.manage` |
| See a project's change requests | `projects.*` only |
| See clients (list, detail, call, email) | `crm.*`, `crm.view`; a client's quote and invoice amounts also need `quotes.view` / `invoices.view` |
| Mark a sent quote approved or rejected | `quotes.*`, `quotes.approve` |
| See the delay and productivity reports | `reports.*`, `reports.view` |
| See a project's budget and latest spending | `financials.*`, `financials.view` |
| See the team directory (call, email) | `employees.*`, `settings.*` |
| Change your own name and phone | any signed-in user |
| See a project's documents | `projects.*`, `projects.view` |
| Add a document to a project | `projects.*` |
| Send a draft invoice to the client | `invoices.*`, `invoices.send` |
| Send a draft quote to the client | `quotes.*`, `quotes.send` |
| Add or edit equipment, change its status | `materials.*`, `materials.manage` |
| Add or edit a client | `crm.*`, `crm.manage` |
| Raise and submit a change request | `projects.*` |
| See every cost recorded against a project | `financials.*`, `financials.view` |
| Add a PDF, Word or Excel file to a project | `projects.*` |
| Clock and log material without a connection | the same permissions as clocking and logging online |
| Create a quote | `quotes.*`, `quotes.create` (choosing the client also needs `crm.view`) |
| Create an invoice, or one from an approved quote | `invoices.*`, `invoices.create` (from a quote also needs `quotes.view`) |
| Mark the quote converted after making its invoice | `quotes.*` (without it the invoice is still made) |
| Link a task to a stage | `projects.*`, `projects.view` to see the stages, plus the right to add or edit the task |
| See the notification count on the bell | any signed-in user |
| Add or change a material, add a category or a supplier | `materials.*`, `materials.manage_inventory` |
| See categories and suppliers | `materials.*`, `materials.log` |
| Turn an approved request into a purchase order | `materials.*`, `materials.manage` |
| Set or change a project's budget | `financials.*` only (reading it needs `financials.view`) |
| Edit or cancel a purchase order | `materials.*`, `materials.manage` |
| Record a purchase with no order, correct a stock count | `materials.*`, `materials.manage_inventory` |
| See the purchases list | `materials.*`, `materials.log` |
| Switch tasks between tiles and the Gantt chart | the same as seeing the tasks (nothing extra; the choice is kept on the phone) |
| See a budget line's items, the budget variance and the alert flags | `financials.*` or `financials.view` |
| Open the Collected, Costs, Profit and Budget left detail pages (all dates and projects) | `financials.*` or `financials.view`; opening an invoice from a payment also needs `invoices.view` |
| Record a cost against a project's budget | `financials.*` only (the server accepts nothing else) |
| See the whole company profile, edit it, change the logo | `settings.*` only (the company calls accept nothing else) |
| See the company's name, currency, time zone and country | everyone signed in (they come with the sign-in) |
| Choose light or dark | everyone; it is a setting of the phone, not of the account |
| Read chats, see photos and play voice messages | `messaging.*` or `messaging.view` |
| Send messages, files, voice and replies, start a chat, make a group, tag people | `messaging.*` or `messaging.send`; choosing from the whole company also needs `employees.*` or `settings.*` (without it a group is made from a project's team) |
| A "Message" button on Team, a project's Team sheet or a client | `messaging.send` (and `employees.*`/`settings.*` for the Team tab, `crm.*` for a client's portal logins) |
| The project Time tab | `timesheets.*` or `timesheets.view_all` |
| Read, clear and mute your own alerts | any signed-in user (they only ever see their own) |
| Which alerts you receive | decided on the server by what you hold, never by role name: workers hear about their own tasks, time decisions and projects they join; supervisors also about their projects' tasks and timesheets waiting; people holding `projects.*` and on a project (or its manager) hear what workers and others do on it; `settings.*` holders (owners) hear only big things (a project closed, a change request decided, a budget over its limit, an invoice paid, a quote accepted, an invite accepted); finance holders hear invoices, costs and budgets; clients with a portal login are not alerted yet |
| Change a project's status, edit its details, assign or change its manager | `projects.*` only (the update and closing calls accept nothing else) |
| Choose the manager from everyone in the company | also `employees.*` or `settings.*` (without it only the project team is offered, and the manager's name is shown only when they are on the team) |
| Change a project's client | also `crm.view` (to choose one) |
| Get alerts on this phone | any signed-in user (their own phone, their own alerts) |
| Start a review, approve, reject or mark a change request implemented | `projects.*` |
| Record my location when I clock in or out | any role that can clock in (a personal switch, off by default) |
| See a project's stages | `projects.*`, `projects.view` (shown on the project screen) |
| Start, complete or skip a stage | `projects.*`, `projects.update` |
| Approve a stage that needs approval | `projects.*` only (the API accepts nothing else) |
| Send message | `messaging.*`, `messaging.send` |

**Who gets Purchasing by default.** `materials.view`, `materials.manage` and `materials.approve` are in no default role's list, so only roles that hold the wildcard `materials.*` get it: Owner, Project Manager **and Site Supervisor**. That means a Site Supervisor can raise *and approve* purchase requests, including their own (`backend-gaps.md` G32). Workers hold only `materials.log` and never see Purchasing or Equipment (G10). Equipment uses the same keys, so the same roles can assign equipment and take it back. The Requests inbox also shows what a purchase request or order is about, but only to people who hold `materials.view` (it looks the record up); everyone else gets the old "who asked and any note" card.

**Payments by default role.** Owner, Project Manager and Accountant hold `invoices.*`, so they can record payments; Site Supervisors and Workers hold no invoice key; the Client role holds `invoices.view`, so it sees invoices read-only. The app records cash and bank transfers only, whatever the role.

**Stages by default role.** Owner and Project Manager hold `projects.*`, so they can start, complete, skip and approve stages. Site Supervisors and Workers hold only `projects.view`, so they see the stages and nothing more (and Workers do not get the project screen at all, see above). `projects.update` is in no default role (G9), so a custom role is needed to give someone the three moves without approval rights.

## Deep links
`computeRedirect` applies the same checks to any location (deep link, notification tap, restored route). Forbidden targets open `/denied`. Losing a permission while on a screen redirects away on the next `/auth/me` refresh (on resume, at most once a minute).

## Known backend inconsistencies (see `backend-gaps.md`)
Several keys required by controllers are not in any default role (`tasks.assign`, `timesheets.approve`, `materials.view`, …) so only Owner/PM (via wildcards) or custom roles can use those features.
