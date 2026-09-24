# Door Scheduler V2: Functional Specification

**Status:** DRAFT for review · **Date:** 2026-09-24 · **Baseline:** V1 `index.html` v25.5 (commit `5839b23`)

This document defines **what V2 does**, before any code or database is built. Each requirement has an ID (e.g. `SCH-04`) so the database, tests and screens can be traced back to it.

Status tags used throughout:

| Tag | Meaning |
|---|---|
| **KEEP** | Behaves the same as V1 |
| **CHANGE** | Exists in V1 but works differently in V2 |
| **NEW** | Not in V1 |
| **DROP** | Removed in V2 |

> **Build rule (agreed):** Firebase is not touched, neither the live V1 project nor a new V2 project, until the new SQL database has been built, tested locally and signed off. See [§12 Build sequence](#12-build-sequence).

---

## 1. Goals

1. **Easy to update.** The code is split into modules, reference data lives in the database rather than the code, and there are automated tests. Commit history should be readable.
2. **No edit conflicts.** Two people working on different doors, products or jobs never overwrite each other. If they edit the *same* record, the app warns them clearly.
3. **A proper product catalogue.** Every product has a **MAT code**. Search works across products and jobs.
4. **New scheduling modules:** linings, a full ironmongery schedule, and a kickplate calculator. The design leaves room to add more modules later.
5. **A live, locked-down app** under a matrixhardware.co.uk address, which only Matrix staff can sign in to.

## 2. Users and roles

| ID | Requirement | Status |
|---|---|---|
| USR-01 | Only `@matrixhardware.co.uk` accounts can sign in. Other emails are rejected at sign-up. | CHANGE (V1: any account an admin created) |
| USR-02 | **Admin** role: edit the catalogue, rates, categories and users; delete jobs; restore deleted jobs. | NEW |
| USR-03 | **Estimator** role: create and edit jobs, clients and folders; add a product *request* (see CAT-09). | NEW |
| USR-04 | **Viewer** role (optional): read-only access to jobs and the dashboard. | NEW, *to confirm* |
| USR-05 | "Prepared by" on quotes is the signed-in user's name, not the client contact. | CHANGE (V1 bug) |
| USR-06 | Every record shows who created it and who last changed it, and when. | CHANGE |

## 3. Product catalogue (replaces "Rates & Products")

V1 keeps hardware as a list of `{type, cost}` per category. It builds quantities into the name ("ZHSS243RS3 X 2", "2 x FDKL SS") and does not use MAT codes. V2 has a real catalogue.

| ID | Requirement | Status |
|---|---|---|
| CAT-01 | A product has these fields: **MAT code** (unique, required), description, category, supplier, supplier code, finish, unit (each/pair/set/metre), **cost £**, optional list price, active flag, notes and image URL. | NEW |
| CAT-02 | Categories are data, not code. The 16 V1 categories are seeded: hinges, closers, intumescents, lockcases, levers, push/pull, combination locks, escutcheons, flush bolts, kick plates, finger guards, signage, thresholds, dropseals, cylinders and door stops. Admins can add, rename, reorder and deactivate categories. | CHANGE |
| CAT-03 | **Quantity is not part of the product.** "ZHSS243RS3 X 2" becomes the product ZHSS243RS3 at quantity 2 on the door. | CHANGE |
| CAT-04 | A category can have a **default product and quantity** that new doors pick up (this replaces V1's star). | KEEP |
| CAT-05 | **Search** by MAT code, supplier code, description or finish. Results appear as you type, and partial words match (e.g. "9205" finds "TS.9205 EN2-5 SNP"). Filter by category, supplier and active status. | NEW |
| CAT-06 | Deactivating a product hides it from new selections, but jobs that already use it keep their price and description. | CHANGE (V1 shows "(removed)") |
| CAT-07 | **Price history**: each cost change is recorded with the date and user. | NEW |
| CAT-08 | Bulk import and update of products from Excel/CSV, matched on MAT code. It shows a preview of new, changed and unchanged rows before applying. | NEW |
| CAT-09 | Estimators can add a product "on the fly" from the schedule, as in V1's "+ Add New…". It is flagged *unverified* until an admin approves it. | CHANGE |
| CAT-10 | Suppliers list: name, account code and contact. | NEW |

## 4. Door, frame and lining rates

| ID | Requirement | Status |
|---|---|---|
| RAT-01 | **Door rates**: door type or form code (SASL, SALH, SADL, plus any added) × fire rating × finish (primed, laminate, veneer) → price. Spray is priced as primed plus a spray uplift. | KEEP |
| RAT-02 | **Fire rating "S" variants** (FD30S, FD60S) price from their own row if one exists, and otherwise fall back to the base rating (FD30, FD60). | CHANGE (V1 bug: S rows never priced) |
| RAT-03 | **Vision panel rates** per fire rating, with a glass description. | KEEP |
| RAT-04 | **Frame rates**: form code × frame finish. Frame finishes are data (the V1 "custom frame finishes"). | KEEP |
| RAT-05 | **Lining rates**: base price per door type × lining finish, like frames (*base price structure to confirm*). | NEW |
| RAT-05a | **Lining depth**: the estimator enters the lining depth (mm) on each lining door. If the depth is **over the threshold** (an admin setting, value *to confirm*), the app **asks for an uplift cost £** for that line. A line over the threshold with no uplift is flagged as a warning and blocks the PDF quote until it is filled in. | NEW |
| RAT-06 | **Architrave rates**: type → price (optionally per set or per door). | KEEP |
| RAT-07 | **Over panel rates**: form code × fire rating × type (solid or glazed) × finish. | KEEP |
| RAT-08 | Rate edits by different users on different rows never conflict. The same row edited at the same time prompts the user (see §9). | CHANGE |
| RAT-09 | Size-based pricing is possible for any rate. Door and frame prices *can* vary by width and height bands if needed. | NEW, *optional* |

## 5. Jobs (quotes)

| ID | Requirement | Status |
|---|---|---|
| JOB-01 | A job has: a **quote reference** (sequential, e.g. `MH-2026-0001`, assigned on first save and never changed), project name, client, site, contact details, PO number, notes, markup %, status, folder, and created/updated info. | CHANGE (V1: random ref, not saved) |
| JOB-02 | Statuses are Outstanding, Won, Lost and Redundant. The date each status was set is recorded. | KEEP |
| JOB-03 | Nested **folders**, plus "All" and "Unfiled" views. A folder view includes jobs in its sub-folders. | KEEP |
| JOB-04 | Jobs are **always saved to the database**, one door row at a time. Nothing is lost if the browser closes, so there is no autosave that creates stray "New Project" jobs. | CHANGE (V1 bugs 6, 7, 11) |
| JOB-05 | "Save as new" or "Duplicate job" copies a job, with a new reference. | KEEP |
| JOB-06 | **Price snapshots**: each door line stores the costs it was priced at. Opening an old job shows the same totals it was quoted at. **"Reprice to current rates"** is a deliberate action that shows the difference before applying. | CHANGE (V1 embeds all rates in each job, and prices differ between screens) |
| JOB-07 | **Presence**: the job shows who else has it open. Editing is not locked; conflicts are handled per row (§9). | CHANGE (replaces the V1 edit lock) |
| JOB-08 | Deleting a job is a soft delete. Admins can restore it within 90 days. | NEW |
| JOB-09 | Jobs are searched by reference, project name, client, site, door ID, or MAT code used. | NEW |
| JOB-10 | New Project starts with an **empty** client. | CHANGE (V1 bug 10) |

## 6. Door schedule (main grid)

### 6.1 Door line fields

| Field | Values | Status |
|---|---|---|
| Qty | whole number ≥ 1 | KEEP |
| Door ID / mark | text | KEEP |
| Location / room | text | NEW (V1 folded it into door ID on import) |
| Door type | from door rates, or **Manual** (with a free description and cost) | KEEP |
| Width, height, thickness | mm | KEEP (thickness NEW) |
| Handing | LH, RH, N/A (list editable) | KEEP |
| Fire rating | NFR, FD30, FD30S, FD60, FD60S (list editable) | KEEP |
| Vision panels | 0–8 | KEEP |
| Door finish | primed, laminate, veneer, spray | KEEP |
| **Surround** | **Frame** or **Lining** (or none) | NEW |
| Frame finish / lining finish | from rates | KEEP / NEW |
| Lining depth (mm) | number; over the threshold → lining uplift £ required | NEW |
| Lining uplift £ | number, asked for only when depth > threshold | NEW |
| Architrave | from rates | KEEP |
| Over panel | none, solid, glazed | KEEP |
| Ironmongery | one product (and qty) per category column, **or** a full ironmongery set (§7) | CHANGE |
| Added uplift £ | number | KEEP |
| Sell override £ (per unit) | number, or blank | KEEP |
| Complete | tick | KEEP |
| Comments | text | KEEP |

`customerType` and `vpSize` are unused in V1. **DROP** them unless you want them.

### 6.2 Grid behaviour

| ID | Requirement | Status |
|---|---|---|
| SCH-01 | Spreadsheet-style grid: Tab, Enter and arrow keys move between cells; copy and paste a cell or range; frozen Door ID column and cost panel. | KEEP (paste range NEW) |
| SCH-02 | Show, hide, reorder and resize columns; three density settings. Saved **per user**, not per browser. | CHANGE |
| SCH-03 | Excel-style filter on each column, an active-filters bar, and search within the job. | KEEP |
| SCH-04 | Find and replace per column, **including custom categories**. | CHANGE (V1 bug 13) |
| SCH-05 | Add a door, add 10, copy a door, **copy to N doors**, delete, drag to reorder. | KEEP (+ copy to N) |
| SCH-06 | **Bulk edit**: select several rows and set a field on all of them (e.g. set closer on 30 doors). | NEW |
| SCH-07 | Undo and redo within the session (Ctrl+Z / Ctrl+Y), and Ctrl+S. | KEEP |
| SCH-08 | Cost panel per line: door+VP, frame or lining, architrave, over panel, hardware, uplift, unit cost, line cost and sell. Hover for the breakdown. | KEEP (fix the `\n` tooltip) |
| SCH-09 | Summary bar: number of rows, **total doors (sum of qty)**, total cost, total sell and margin %. | KEEP (+ margin) |
| SCH-10 | **Door types / templates**: save a door's full spec, including ironmongery, as a named template (e.g. "FD30 SASL office door"), then apply it to any rows. | NEW |

### 6.3 Warnings (validation)

These are kept from V1:
- A fire door without intumescent, closer or signage.
- SADL or SALH without flush bolts.
- No door type, no door ID, no hinges.
- Neither a lever nor a push/pull.

| ID | Requirement | Status |
|---|---|---|
| WRN-01 | Keep the V1 rules above. | KEEP |
| WRN-02 | Rules become data, so admins can add or turn off rules without changing code. | NEW, *phase 2* |
| WRN-03 | The PDF or export warns (without blocking) if any warnings are still open. | NEW |

## 7. Ironmongery schedule (NEW, **phase 2: built after the doors side is complete**)

**Agreed 2026-09-24:** ironmongery is built after all of the doors side is finished. Until then, doors keep V1-style hardware: **one product + qty per category column** on the door grid, priced from the catalogue (§3). The database stores door hardware as item rows (door, category, product, qty, cost snapshot), so phase 2 extends it without a rebuild.

Phase 2 scope (for reference, not built yet) gives a full hardware specification per door, not just one item per category.

| ID | Requirement | Status |
|---|---|---|
| IRN-01 | Each door can have **any number of ironmongery lines**: product (MAT code), qty and optional note. The per-category columns on the door grid are a quick view of the same data. | NEW |
| IRN-02 | **Ironmongery sets**: named groups of products and quantities (e.g. "Set 3: FD30 office, lever/lock"). A set can be assigned to many doors; changing the set updates every door using it, unless that door has been overridden. | NEW |
| IRN-03 | **Grid view**: products as rows, one column per door, qty in the cells, with totals per product and per door. It matches the Matrix **BLANK SCHEDULE TEMPLATE** layout. | NEW |
| IRN-04 | **Summary / order list**: total quantity per MAT code across the job, with cost and sell. Can be used to pick or order. | NEW |
| IRN-05 | Export IRN-03 and IRN-04 to Excel in the Matrix template layout. | NEW |
| IRN-06 | *(phase 2)* **Kickplate calculator**: kickplate width = door width minus an allowance (default 50 mm, *to confirm*), height from a list (150/200/250/300/400 mm, *to confirm*), sides 1 or 2 (push/pull). The cost is calculated per size from a rate (per m² or per size band, *to confirm*) or picked from a size-matched product. | NEW |

## 7a. Door screens (NEW, **structure only for now**)

**Agreed 2026-09-24:** the database structure for **door screens** (glazed screens around or beside doorsets, e.g. side screens and fan-lights) is built now; they get their own pages and pricing later.

| ID | Requirement | Status |
|---|---|---|
| SCR-01 | A job can have **screen lines** alongside door lines: qty, screen mark, location, width, height, fire rating, glazing description, frame finish, description, **manual unit cost**, sell override, comments. | NEW, structure only |
| SCR-02 | Screen lines are included in job totals, using the same markup. | NEW, structure only |
| SCR-03 | Screen rates and pricing rules are defined later. For now cost is entered by hand. | *later* |

## 8. Clients

| ID | Requirement | Status |
|---|---|---|
| CLI-01 | A **shared** client address book (company, site, contact, phone, email, notes). V1 kept this only in one browser. | CHANGE |
| CLI-02 | Pick a client on a job; editing the job's contact does not change the address book unless you choose to. | KEEP |
| CLI-03 | Search clients; view all jobs for a client with won/lost totals. | NEW |

## 9. Editing at the same time (conflict handling)

| ID | Requirement | Status |
|---|---|---|
| CON-01 | Every door line, product, rate row and job header is saved **separately**. Two users editing different records never affect each other. | CHANGE |
| CON-02 | If two users change the **same** record at the same time, the second save is rejected. That user sees what changed and chooses *keep mine* or *take theirs*. No silent overwrite. | CHANGE |
| CON-03 | Other users' changes appear without a full reload. At minimum, refresh when the job regains focus, or every 30 s. | CHANGE |
| CON-04 | An importing file never pushes rates to all users as a side effect. | CHANGE (V1 bug 9) |

## 10. Import and export

| ID | Requirement | Status |
|---|---|---|
| IMP-01 | Import doors from Excel/CSV: **choose the sheet and header row**; headers matched against the V1 aliases (about 95) *and* matched loosely (e.g. "Fire Rating (mins)" → fire rating). | CHANGE |
| IMP-02 | A **mapping screen** shows each source column → field, lets you fix unmatched ones, and remembers the mapping per client or source. | NEW |
| IMP-03 | Hardware cells are matched to catalogue products by MAT code, supplier code, then description. Unmatched cells are listed for you to resolve. | CHANGE (V1: £0 / "(removed)") |
| IMP-04 | Door type is matched by form code (SASL etc.) or description. | CHANGE |
| IMP-05 | Import as append or replace; preview before applying. | KEEP |
| IMP-06 | **Downloadable import template** with the exact headers and dropdown lists. | NEW |
| EXP-01 | **PDF quote** (A3 landscape): Matrix header, quote ref, client block, visible columns **in the user's order**, totals, T&Cs (editable by admin, not hard-coded), prepared by the user. | CHANGE |
| EXP-02 | **Excel schedule export**: visible columns in order, custom categories, manual descriptions and client details. | CHANGE (V1 bug 13) |
| EXP-03 | **Ironmongery schedule export** (IRN-05). | NEW |
| EXP-04 | Job backup file (JSON) download and restore, for one job. | KEEP |
| EXP-05 | Full database backups are handled by the database (automatic daily backups), not by a browser download. | CHANGE |

## 11. Dashboard

| ID | Requirement | Status |
|---|---|---|
| DSH-01 | Headline figures: pipeline value, won this year, win rate, average quote. Redundant jobs are excluded. | KEEP |
| DSH-02 | Pipeline by age (0–14, 15–30, 31–60, 60+ days), recent wins, and outstanding quotes oldest first, with quick status buttons. Quotes 30+ days old are flagged for follow-up. | KEEP |
| DSH-03 | Filter by estimator (prepared by) and date range. | NEW |
| DSH-04 | Figures come from saved job totals (JOB-06), so the dashboard and the job always agree. | CHANGE (V1 bug 17) |

## 12. Build sequence

1. **This spec:** review and answer the open questions (§14).
2. **SQL database** (Postgres), built and tested **locally only**: schema, seed data from the V1 default rates, key queries, conflict handling and search tests. A data-model document for sign-off.
3. **Pricing engine**: pure code with automated tests that prove V2 totals match V1 for the same inputs.
4. **Only then Firebase:** a new, separate V2 project (Hosting + Auth + Data Connect/Postgres). The live V1 project is not touched.
5. The doors side, in the order: catalogue → schedule (doors, frames, linings) → jobs/clients/dashboard → import/export → roles.
6. **Phase 2:** ironmongery schedule (§7) and kickplate calculator, then door screens pricing (§7a).
7. **Later:** import V1 data (rates, jobs, folders) into V2, then cut over the domain.

## 13. V1 bugs V2 must not repeat (acceptance criteria)

| # | V1 bug | V2 criterion |
|---|---|---|
| 1 | "None" door stop costs £1, so +£1 per door offline | "None" is the absence of a product, never a priced item |
| 2 | Tooltips show a literal `\n`; text not escaped | All user text is escaped by the UI framework |
| 3 | An apostrophe in a door ID breaks the delete button | (covered by 2) |
| 4 | "Prepared by" shows the client contact; quote ref random | USR-05, JOB-01 |
| 5 | Jobs referenced by list position (wrong job deleted) | Everything referenced by a stable ID |
| 6–7 | Duplicated or lost jobs (local ID, imported job files) | JOB-04 |
| 8 | Rates can't be created on a fresh database | Seeded by migration |
| 9 | Loading a project file pushes its rates to everyone | CON-04 |
| 10 | New Project keeps the old client | JOB-10 |
| 11 | Autosave creates stray jobs | JOB-04 |
| 12 | Import gaps (hardware, headers, form codes) | IMP-01..04 |
| 13 | Exports and find/replace ignore custom categories and column order | SCH-04, EXP-01/02 |
| 14 | FD30S/FD60S rows never priced | RAT-02 |
| 17 | Dashboard and job totals differ | JOB-06, DSH-04 |

## 14. Open questions: please answer in this doc or in chat

| # | Question | Why it matters |
|---|---|---|
| ~~Q1~~ | **Answered:** enter a lining depth; if it's over a threshold, ask for an uplift cost. *Still to confirm:* the **threshold value (mm)**, and whether the lining **base price** is per door type × finish like frames. | RAT-05/05a |
| **Q2** | **Ironmongery schedule layout:** please attach the BLANK SCHEDULE TEMPLATE (xlsx) the export must match. | IRN-03/05 |
| Q3 | *(deferred to phase 2)* **Ironmongery sets:** do you want sets (IRN-02), or is per-door enough for now? | Big effect on the data model |
| **Q4** | **Kickplates:** priced per m², per size band, or as fixed products? What width allowance and heights? | IRN-06 |
| **Q5** | **Markup or margin?** V1 applies *markup on cost* (22% default). Keep it, or quote by margin %? Allow a markup per line or per category? | Pricing engine |
| **Q6** | **VAT:** show VAT and a gross total on the quote, or ex VAT only as now? | PDF |
| **Q7** | **"A few more" modules:** door screens are confirmed (§7a). Which others are planned? (e.g. glazing, signage schedule, door furniture only, fire stopping, installation/labour, delivery charges) | Keeps the design open for them |
| **Q8** | **Roles:** who should be admins? Is a read-only Viewer role needed? | USR-02..04 |
| **Q9** | **Sign-in method:** Microsoft 365 work accounts (best if Matrix uses M365), Google, or email + password? | USR-01 |
| **Q10** | **MAT codes:** is there an existing MAT code list (e.g. an OGL export) to seed the catalogue from? What format is the code (e.g. `MAT12345`)? | CAT-01, seed data |
| **Q11** | Do door and frame prices need to vary by **size** (RAT-09), or is price by type × fire × finish enough? | Rates tables |
| **Q12** | Drop the unused V1 fields `customerType` and `vpSize`? | Data model |
