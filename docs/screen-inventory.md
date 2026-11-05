# Screen inventory

Legend: ✅ built and tested · 🟡 built, partly verified · ⏳ planned (not built) · 🚫 not supported by the API today

## Signed-out and status screens (Phase 1)
| Screen | Route | Status | Notes |
|---|---|---|---|
| Splash / session restore | `/splash` | ✅ | Shown while tokens are verified |
| Login | `/login` | ✅ | Email + password; company code appears only on "multiple accounts"; expired-session banner |
| Forgot / reset password | `/forgot-password` | ✅ | Two steps (email → 6-digit code + new password) |
| Subscription blocked | `/subscription-blocked` | ✅ | Message by 402 `code`; no billing actions; "Check again" + sign out |
| Startup failed | `/startup-failed` | ✅ | Offline with nothing cached; retry |
| Access denied | `/denied` | ✅ | Deep link / permission loss |
| More (account, company, web-only list, sign out) | `/more` | ✅ | Permission-aware |

## Worker experience (Phase 2)
"Tested" = automated widget/logic tests pass. None of these has been run on an emulator or device yet (see `implementation-progress.md`).

| Screen | Route | Status | Notes |
|---|---|---|---|
| Clock | `/clock` | ✅ tested | Clock in/out, break sheet, live timer, today/week, recent time, last-known offline state |
| My Tasks | `/tasks` | ✅ tested | Grouped by due date, status filter, offline copy, queued changes, refused-change card |
| Task detail | `/tasks/:id` | ✅ tested | Status actions; checklist/comments/photos gated by permission (and by backend B2) |
| Materials | `/materials` | ✅ tested | Search, paging, "logged on this phone" list |
| Log material | `/materials/log` | ✅ tested | Confirmation sheet, over-stock warning, project choice |
| Messages | `/messages` | ✅ tested | Project channels + direct chats |
| Thread | `/messages/:id` | ✅ tested | Optimistic send, retry/delete, live push, polling fallback, read-only without `messaging.send` |
| Notifications | `/more/notifications` | ✅ tested | "Not available yet" until backend B1 is deployed |

## Supervisor and manager experience (Phase 3)
"Tested" = automated widget/logic tests pass. Not yet run on an emulator or device.

| Screen | Route | Status | Notes |
|---|---|---|---|
| Today | `/today` | ✅ tested | Time (to approve, working now), tasks (overdue, due today, blocked), own clock. Each section loads and fails on its own and appears only if permitted |
| Projects | `/projects` | ✅ tested | Search, status filter, progress, paging. No money |
| Project detail | `/projects/:id` | ✅ tested | Facts, team, tasks by status (done hidden until asked). No money |
| Approvals | `/approvals` | ✅ tested | Grouped by worker; approve with confirmation, reject with reason, approve all per worker; "working now" list |
| Change who is assigned | sheet on `/tasks/:id` | ✅ tested | Project team as the list; each tap saved at once |

## Finance, requests and task authoring (Phase 4)
"Tested" = automated widget/logic tests pass. Not yet run on an emulator or device.

| Screen | Route | Status | Notes |
|---|---|---|---|
| Finance overview | `/finance` | ✅ tested | Money owed (aging buckets, most overdue) and money in and out; each section only if permitted; failures are per section |
| Invoices | `/invoices` | ✅ tested | Status filter, paging; read-only |
| Invoice detail | `/invoices/:id` | ✅ tested | Lines, totals, balance due, payments; no gateway data; "Record a payment" with `invoices.mark_paid` on an open invoice. Sending an invoice and PayNow / EcoCash payments are web only |
| Record a payment | `/invoices/:id/pay` | ✅ tested | Cash or bank transfer, amount (up to the balance, "the full balance" shortcut), confirmation with the new balance; never sent twice |
| Quotes | `/quotes` | ✅ tested | Status filter, paging; read-only |
| Quote detail | `/quotes/:id` | ✅ tested | Lines, discount, tax, rejection reason |
| Requests | `/requests` | ✅ tested | Approvals waiting for you; approve (confirmation) / reject (reason). Purchase requests and orders show what is being asked for (Phase 5); other kinds say plainly that amounts and items are not shown, and every kind says what approving actually does (a change request's cost and days are not applied; stages, documents and budgets are not changed at all) |
| New task | `/projects/:id/new-task` | ✅ tested | Title, description, priority, due date, estimate, assignees |
| Edit task | `/tasks/:id/edit` | ✅ tested | Same form; says that a due date / estimate cannot be removed |

## Purchasing (Phase 5, first part)
"Tested" = automated widget/logic tests pass. Not yet run on an emulator or device.

| Screen | Route | Status | Notes |
|---|---|---|---|
| Purchasing | `/purchasing` | ✅ tested | Requests / Orders chips, status filter, paging; "New purchase request" only with `materials.manage` |
| Purchase request | `/purchasing/requests/:id` | ✅ tested | Items with estimates and an estimated total ("at least" when incomplete), linked orders, Submit (draft), Approve / Reject (submitted) by permission |
| New purchase request | `/purchasing/new` | ✅ tested | Project (optional), notes, one or more items; "Submit for approval" or "Save as draft"; never created twice |
| Purchase order | `/purchasing/orders/:id` | ✅ tested | Supplier, items, total, deliveries recorded (date, by you / a colleague, quantities), "Record a delivery" with `materials.manage`. Sending the order to the supplier is on the web app |
| Record a delivery | `/purchasing/orders/:id/receive` | ✅ tested | Date, what arrived per item (ordered / received so far / outstanding), "everything outstanding arrived", notes; confirms the stock effect; never sent twice |

## Equipment (Phase 5, second part)
"Tested" = automated widget/logic tests pass. Not yet run on an emulator or device.

| Screen | Route | Status | Notes |
|---|---|---|---|
| Equipment | `/equipment` | ✅ tested | Status filter (All, Available, In use, Maintenance, Retired), paging; name, category, serial. No costs |
| Equipment detail | `/equipment/:id` | ✅ tested | Where it is (project, dates, who assigned), recent assignments; "Assign to a project" (available) and "Mark returned" (one open assignment) with `materials.manage` |
| Assign equipment | `/equipment/:id/assign` | ✅ tested | Project (required), start date (today), return-by date (optional), note; never sent twice |

## Project stages (Phase 5, third part)
"Tested" = automated widget/logic tests pass. Not yet run on an emulator or device.

| Screen | Route | Status | Notes |
|---|---|---|---|
| Stages section | on `/projects/:id` | ✅ tested | Stages by workflow with status, planned / actual dates, "needs approval", approver and notes; Start, Skip, Complete (with confirmation) and Approve stage by permission; hidden when the project has no stages |

## Company overview (Phase 5)
"Tested" = automated widget/logic tests pass. Not yet run on an emulator or device.

| Screen | Route | Status | Notes |
|---|---|---|---|
| Company section | on Today (`/today`) | ✅ tested | Active projects, what is owed and how much is overdue, and the projects whose budget has reached its alert level (percentage only). Each part by permission and loads / fails separately; tiles open Projects and Finance when the role has them |

## More of Phase 5 (built, not yet covered by tests)
These screens compile and follow the same patterns as the tested ones, but have no automated tests yet (tests were skipped on request): treat them as unverified.

| Screen | Route | Notes |
|---|---|---|
| Mark as sent | on `/purchasing/orders/:id` | A draft order, with `materials.manage`: a confirmation, then the status is set; says nothing is emailed |
| Change requests | on `/projects/:id`, `/projects/:id/change-requests/:crId` | List and detail (cost, time, lines, notes) for `projects.*`, with the next step for the status: Submit, Start review, Approve / Reject, Mark as implemented |
| Clients | `/clients`, `/clients/:id` | Search, contact details with Call / Email / Copy, projects, and (by permission) quotes and invoices |
| Quote decisions | on `/quotes/:id` | "Mark approved" (says it records the material lines) and "Mark rejected" (optional reason) on a sent quote, with `quotes.approve` |
| Reports | `/reports` | Delays (behind / on track, overdue stages) and Productivity (tasks done, hours) |

### And a further batch (also not yet covered by tests)

| Screen | Route | Notes |
|---|---|---|
| Project budget | on `/projects/:id` | `financials.view` only: spent against planned with a progress line, per-category status, the latest 10 expenses with a button for all of them. The pay-bearing category ledger is not used |
| Team | `/team` | Searchable directory of active people with Call / Email; needs `employees.*` or `settings.*` |
| Your profile | `/more/profile` | Change your name and phone from the profile card on More |

### The final Phase 5 batch (also not yet covered by tests)

| Screen | Route | Notes |
|---|---|---|
| Project documents | on `/projects/:id` | List with type, size, date and approval; tap opens the stored link; "Add a document" (camera or gallery) with `projects.*` |
| Send to client | on `/invoices/:id`, `/quotes/:id` | On a draft, with `invoices.send` / `quotes.send`: choose "send and email it" (shows the address) or "mark as sent" without emailing |
| Record my location | on `/clock` | A switch, off by default; asks the phone for permission; never blocks clocking |
| Add / edit equipment | `/equipment/new`, `/equipment/:id/edit` | Name, serial, notes, category; status buttons (maintenance, available, retire, return to service) when not in use |
| Add / edit client | `/clients/new`, `/clients/:id/edit` | Name, type, contact, phone, email, address, notes |
| Start review / Approve | `/projects/:id/change-requests/:crId/review`, `…/approve` | Optional cost, days and notes. Approving shows what it will do to the budget and end date as the numbers are typed, and asks first. Reject (reason required) and Mark as implemented are confirmations on the detail page |
| New change request | `/projects/:id/new-change-request` | Title, type, description, optional cost lines; submit or save as draft; "Submit for review" on a draft's page |

### Documents, costs, offline saving and alerts (also not yet covered by tests)

| Screen | Route | Notes |
|---|---|---|
| Add a document: file | on `/projects/:id` | A third choice, "Choose a PDF, Word or Excel file"; type and size checked first |
| Project costs | `/projects/:id/costs` | Every transaction, newest first, "Show more", receipt links; `financials.view`; a note says labour is not itemised |
| Saved on this phone | on `/clock` and `/materials` | What is waiting, checked after no answer, or refused with Try again / Discard |
| Clock without a connection | `/clock` | Buttons stay on; a saved shift shows "Saved on this phone"; the banner says what will happen |
| Materials without a connection | `/materials`, `/materials/log` | The materials seen before are listed with a note; logging says it is saved and will be sent |
| Notifications | `/more/notifications` | "Turn on alerts" (off, on, blocked), the server's list together with alerts kept on the phone, tap to open |
| Sign out | More | With unsent entries it says how many and that signing out discards them |

### Quotes, invoices, the bell and task stages (also not yet covered by tests)

| Screen | Route | Notes |
|---|---|---|
| New quote | `/quotes/new` | Client search, project, title, dates, lines with category, discount and tax, live total, notes and terms; saved as a draft |
| New invoice | `/invoices/new` | Client, project, dates, retention, lines (a credit line may be negative), total, notes and terms; saved as a draft |
| Invoice from a quote | `/invoices/new?quoteId=` | The approved quote's details copied in; says what the quote's total was and offers its tax and discount as lines; confirms before saving |
| Notification bell | top right of Today, Clock, My Tasks and Finance | Unread count; opens `/more/notifications` |
| Timeline stage | on `/projects/:id/new-task` and the task's edit form | Link or unlink one of the project's stages; shown on the task's page |

### Materials, suppliers, orders, budgets and the project page (also not yet covered by tests)

| Screen | Route | Notes |
|---|---|---|
| New / edit material | `/materials/new`, `/materials/edit` | Category, unit dropdown, price (reason when it changes), supplier, code, reorder level, opening stock |
| Suppliers | `/materials/suppliers`, `/materials/suppliers/new` | List with call and email, add a supplier |
| Pickers | sheets | Material (searched, or create), supplier (or add), category (or add), unit (grouped) |
| New purchase order | `/purchasing/requests/:id/order` | From an approved request: supplier, delivery date, quantities and prices, total, confirmation |
| Project budget | `/projects/:id/budget` | A planned amount per category, spent so far beside each, add a category, total |
| Edit order | `/purchasing/orders/:id/edit` | A draft only: supplier, delivery date, notes, each item's quantity and price, remove or add an item, total, confirmation |
| Record a purchase | `/materials/purchases/new` | Supplier, date, optional project, invoice number, items with quantity and price paid, total, confirmation |
| Purchases | `/materials/purchases` | Newest first: supplier, date, project, total and the items |
| Correct the stock count | `/materials/count` | Opened from a material: counted quantity, reason, the difference, confirmation |
| Gantt chart | `/tasks` and a project's Tasks tab | Tiles / Gantt switch; Week, Month, Quarter; arrows and Today; a full-width row per task (name, status, dates) with its bar underneath, each bar in its own colour, a tick when done and a red edge when overdue; the period always fits the screen, no sideways scroll; tasks with no dates listed below |
| Money detail | `/finance/detail/:tab` (`collected`, `costs`, `profit`, `budget`; optional `?project=`) | Opened from the four Finance figures or a project's Budget tab. Filters: all time, a day, a month or a range of dates, and all projects or one. The four figures at the top are the tabs |
| Budget item sheet | sheet on a project's Budget tab | Every item behind a budget line, with what it counts, what was planned and what is left fixed at the bottom |
| Budget variance | card on a project's Overview | Spent against planned, under or over, flags, and the lines closest to their limit; opens the Budget tab |
| Record a cost | `/projects/:id/costs/new` (optional `?category=`) | Category, what it was for, amount, date, payee, reference, notes; shows what it does to the budget before saving |
| Budget alerts | section on the Finance page | Projects at or over their alert level, worst first |
| Company profile | `/more/company` | The Company tile on More. Full profile for `settings.*` (tabs: Profile, Business, Sectors & types, Team roles, Workflows, Settings; change the logo); the sign-in's own name, currency, time zone and country for everyone else |
| Edit company | `/more/company/edit/:section` (`profile`, `business`, `settings`) | Only what was changed is sent; settings ask for a confirmation listing each change |
| Appearance | card at the top of Your profile (`/more/profile`) | System, Light or Dark; applies at once and is kept on the phone |
| Messages | `/messages` | Search, All / Direct / Groups / Unread, a row per chat with unread badge, a new-chat button for `messaging.send` |
| New chat | `/messages/new` | A direct message (pick one person) or a group (a project, an optional name, people or the project team) |
| Chat thread | `/messages/:id` | Bubbles, replies, photos, documents, voice messages, @ tags in groups, a message box with attach, record and send; long-press a message for Reply and Copy |
| Photo viewer | `/messages/image` | Full screen, swipe between a message's photos, pinch to zoom, open outside the app |
| Project Time tab | a tab on `/projects/:id` (`timesheets.view_all`) | Total hours, days worked, average per day, this week, on site now, last 14 days, per person |
| Notifications | `/more/notifications` | Filters (All, Unread, one per category), grouped by day with a category icon and who did it, mark all as read, remove with undo, load more, the alerts on/off card, and a row to the settings |
| Notification settings | `/more/notifications/settings` | One card per category with "In the app" and "On this phone" switches; explains when the server cannot save them yet |
| Edit project | `/projects/:id/edit` | Name, about, type, site address, start and end dates, client; only changes are sent |
| Change the status | sheet on a project | The status badge opens it; each status with its meaning, then a confirmation (Completed asks for optional closing notes) |
| Assign the manager | sheet on a project | The "no project manager yet" banner or Details; search the company's people, or the project team only |
| Project page | `/projects/:id` | Header with Details and Team sheets; pinned tabs: Overview (glance tiles), Tasks, Timeline, Budget, Changes, Documents |

## Planned (not built)
Emailing purchase orders to suppliers, over-deliveries and corrections to a recorded delivery, company settings and payroll, and offline saving for writes other than clock in, clock out and material used (payments, deliveries, approvals and creating records are online-only on purpose).

## Not supported by the API today 🚫
Message attachments, authorised/signed file downloads, "my material logs" (no user on the log), starting new conversations (no user directory for field roles). Push alerts and offline clock events need the backend changes B8 and B7. See `backend-gaps.md`.

