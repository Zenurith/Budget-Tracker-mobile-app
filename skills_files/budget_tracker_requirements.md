# Pocketwise: product requirements

Version: 0.2 · Updated: 2026-09-28 · Status: requirements baseline, with confirmed choices and open decisions recorded in [DECISIONS.md](../docs/DECISIONS.md).

## 1. Purpose and terminology

Pocketwise helps individuals understand their daily spending, meet existing commitments, assess debt pressure, and plan purchases without taking money away from essentials or protected savings.

**Required architecture: Model–View–Presenter (MVP).** In these documents, MVP always names the architecture. **Release 1 (R1)** names the first product release. The previous MVC architecture and old first-release scope are superseded by this document.

Stack: Flutter client, Python/FastAPI API and calculation services, Supabase Postgres production database. SQLite remains a development-only repository. The existing code is a prototype, not yet an implementation of the complete R1 requirements or the target MVP architecture.

Confirmed product defaults: country-neutral behavior, explicit user-selected currency, and English UI. The personal DSR estimate is labelled net income basis; DTI is labelled gross income basis. No country-specific tax rules or lender thresholds are inferred. Wishlist readiness uses existing saved money only; forecasts provide target dates. R1 supports explicitly listed two-decimal currencies; currency conversion is outside R1.

## 2. Intended users and outcomes

Users include salaried adults, students with debt commitments, and people with variable income who want a personal planning tool. R1 is for one individual's finances, not household or business accounting.

A user should be able to:

1. Record and understand income and expenses.
2. Plan monthly spending and see upcoming obligations.
3. See how scheduled debt payments compare with gross and take-home income.
4. Reserve money for a wanted purchase while preserving commitments and savings.
5. Understand why a result changed, which inputs it uses, and when those inputs were last reviewed.

## 3. Scope and priority

**R1 required:** account security, core transaction/category/budget features, dashboard/reports, basic recurring commitment planning, savings and emergency reserves, DSR/DTI financial helper, guilt-free wishlist, basic natural-language entry, and core privacy/accessibility/offline requirements.

**R2 planned:** richer automation, push reminders, exports, receipt attachments, feedback learning, preferences and debt payoff projections.

**Optional later:** OCR, anomaly detection, broader conversational assistant, multilingual support and currency conversion.

R1 includes basic savings reservations and bill scheduling because wishlist readiness depends on them. It does not include automatic bank access, money transfers, lending decisions, purchases, or investment recommendations. Merely calculating affordability never authorizes a payment.

## 4. Functional requirements

Existing FR-1–FR-29 identifiers are retained for traceability; priorities below replace the original phase assignments.

| ID | Requirement | Priority |
|---|---|---|
| FR-1 | Register and log in with email/password; validate inputs and avoid logging credentials. | R1 |
| FR-2 | Use short-lived JWT access tokens, rotating/revocable refresh tokens and secure device storage; support logout. | R1 |
| FR-3 | Reset passwords through expiring, single-use email links; rate limit and avoid account enumeration. | R1 |
| FR-4 | Edit name and preferences. R1 uses calendar months and account currency selected at registration; custom monthly start dates are R2. | R1/R2 |
| FR-5 | Delete the account and all owned data, including debt, wishlist, reservation and snapshot records. | R1 |
| FR-6 | Add/edit/delete/view transactions: exact amount, income/expense type, category, local date, note, payment method and optional links to a commitment or wishlist purchase. | R1 |
| FR-7 | Support income and expenses. Borrowing and transfers must not inflate earned income; where full transfer accounting is unavailable, exclude such entries from income-based calculations. | R1 |
| FR-8 | Schedule daily/weekly/monthly commitments. R1 supports due dates and explicit marking/linking as paid; background posting and advanced recurrence rules are R2. | R1/R2 |
| FR-9 | Search/filter transactions by date range, category, amount and type, with pagination. | R1 |
| FR-10 | Attach optional receipt images with ownership checks and deletion handling. | R2 |
| FR-11 | Provide default income and expense categories. | R1 |
| FR-12 | Create/rename/delete custom categories and select icons/colors; preserve references for categories in use. | R1 |
| FR-13 | Set calendar-month overall and category budgets; upsert each owner/month/category combination. | R1 |
| FR-14 | Show spent, remaining and overspend amounts; distinguish a spending limit from money actually reserved. | R1 |
| FR-15 | Configure budget thresholds and show in-app alerts; remote push delivery is R2. | R1/R2 |
| FR-16 | Create savings goals with target/date and funded reservations; include emergency savings as a protected reserve. | R1 |
| FR-17 | Dashboard: recorded transaction balance, monthly income/expenses, recent activity, upcoming commitments, financial-helper summary and wishlist progress. Do not present incomplete transaction totals as verified bank cash. | R1 |
| FR-18 | Category breakdown, spending trend and monthly comparison charts, with accessible text summaries. | R1 |
| FR-19 | Export reports as CSV/PDF. A basic machine-readable personal-data export is required in R1 independently of report formatting. | R2; data export R1 |
| FR-20 | Parse English natural-language transaction input into amount, category, date, type and note. | R1 |
| FR-21 | Suggest categories from notes or merchants. Deterministic rules suffice for R1. | R1 |
| FR-22 | Show/edit the parsed draft and obtain explicit confirmation before saving; ambiguous amounts must not be silently accepted. | R1 |
| FR-23 | Store corrections, with consent, for later suggestion improvements. | R2 |
| FR-24 | Show factual, explainable summaries from recorded data. Comparative insights beyond basic totals are R2. | R1/R2 |
| FR-25 | Answer conversational spending queries with owner-scoped data and traceable totals. | Later |
| FR-26 | Detect potentially unusual spending with user-controlled alerts. | Optional |
| FR-27 | Extract receipt merchant/date/total using OCR with confirmation. | Optional |
| FR-28 | Deliver push reminders for budgets and recurring commitments. R1 includes in-app upcoming/overdue lists. | R2 |
| FR-29 | Currency/language/theme/notification preferences. R1: one account currency, English, accessible default theme; broader preferences R2. | R1/R2 |
| FR-30 | Maintain a user-confirmed financial profile with separate gross income, net income, income sources, basis/period and review date. Variable-income assumptions must be visible. | R1 |
| FR-31 | Maintain debt commitments with type, required monthly payment, due schedule, optional outstanding balance, status and effective dates; include bank and non-bank debt. | R1 |
| FR-32 | Calculate and explain DSR and DTI using the exact rules in [FINANCIAL_HELPER.md](../docs/FINANCIAL_HELPER.md); handle missing/zero income without a misleading percentage. | R1 |
| FR-33 | Compare unsaved debt-payment/income scenarios against the confirmed baseline without changing actual debts, transactions or savings. | R1 |
| FR-34 | Show debt-payment totals, remaining income after debt, calculation basis, missing inputs, review date and optional user-set ratio targets. Do not label ratios as loan approval or universal safety ratings. | R1 |
| FR-35 | Keep reviewable ratio snapshots only on explicit save; version formulas and inputs. | R1 |
| FR-36 | Create/edit/archive wishlist items with total target cost, priority, optional target date, notes and optional URL. A URL is a reference only; no checkout or price scraping in R1. | R1 |
| FR-37 | Allocate existing money to wishlist items using a reservation ledger; support partial funding, withdrawal and explicit reallocation without double-counting funds. | R1 |
| FR-38 | Determine wishlist readiness using confirmed liquid funds, unpaid commitments, protected savings, other reservations and a cash buffer, per [WISHLIST.md](../docs/WISHLIST.md). | R1 |
| FR-39 | Show funding shortfall, readiness reasons and a user-controlled savings forecast; forecast income never becomes existing money. | R1 |
| FR-40 | Record a wishlist purchase only after confirmation; link exactly one expense and consume the relevant reservation atomically and idempotently. This records a purchase the user made; it does not buy anything. | R1 |
| FR-41 | Let users pause/archive a wishlist item without shame-based messages; money is released only by an explicit confirmed action. | R1 |
| FR-42 | Maintain a confirmed liquid-funds snapshot and a planning horizon, with explicit included accounts and freshness status. It is separate from the dashboard's recorded balance. | R1 |
| FR-43 | Show a bill/commitment calendar with due, paid, partially paid and overdue states; link payments so an obligation is reserved once. | R1 |
| FR-44 | Show a monthly review of actual spending, budget variance, debt ratios and goal/wishlist progress; identify incomplete periods. | R1 |
| FR-45 | Cache recent records offline and queue supported transaction edits with stable operation IDs. Offline financial/wishlist calculations are labelled estimates; final funding/purchase operations require online server validation. | R1 |
| FR-46 | Allow machine-readable export of personal data and deletion; capture consent before sending data to an external AI provider if one is introduced. | R1 |
| FR-47 | Future payoff planner may compare repayment strategies using explicit rates, fees and interest assumptions. It must remain separate from simple DSR/DTI calculations. | R2 |

## 5. Non-functional acceptance requirements

| Area | R1 acceptance target |
|---|---|
| Architecture | MVP boundaries in [ARCHITECTURE.md](../docs/ARCHITECTURE.md). Views cannot call HTTP/storage or implement financial formulas. Presenter tests run without rendering widgets. |
| Money | Integer minor units for money, decimal/rational arithmetic for ratios, explicit rounding only at presentation. Account currency required; reject mixed-currency calculations. |
| Performance | Proposed benchmark: p95 API reads/calculations and NLP parsing under 2 seconds over 100 requests with 10 concurrent users, 10,000 transactions/user and a documented network/device profile. UI target under 2 seconds after authentication under the same profile. Record measurements before claiming compliance. |
| Security | HTTPS in release; Argon2/bcrypt passwords, validation, owner scoping, bounded uploads, rate limits, rotating sessions and secure token storage. No secrets or personal financial payloads in application logs. |
| Privacy | Production encryption at rest and in transit; data minimization, export and deletion. Provider processing is opt-in. Local development storage is not evidence of production compliance. |
| Reliability | 99% monthly uptime target, daily automated backups and a tested restore. Reservations/purchase recording must survive retries and partial failures. |
| Accessibility | Screen-reader labels, non-color-only statuses, adequate contrast and usable layouts at 200% text scale; validate on target devices. |
| Usability | Common manual transaction path should take no more than three navigation taps, excluding typing, keyboard actions and optional field changes. Financial inputs and estimates must be understandable without implementation terminology. |
| Offline | Cached views identify their last sync. Queue replay must not duplicate transactions or purchases. Conflicts need an explicit resolution path. |
| Testing | At least 70% core logic coverage; all financial edge cases and reservation invariants require deterministic tests. Unit, contract, integration and representative device checks are release gates. |
| NLP | Target 85% exact field extraction and 80% category accuracy on a versioned, labelled, held-out English dataset of at least 200 cases. Document supported expressions and unknown/ambiguous handling. Existing sample tests do not establish these percentages. |
| Compatibility | Original targets: Android 8+ and iOS 13+. Current generated iOS baseline is 15.0. Resolve this incompatibility explicitly before R1 release; do not silently claim the original targets. Web remains a development/demo target unless selected for production. |

## 6. Product rules shared by features

- Transactions represent actual activity; budgets are limits; debts represent scheduled obligations; savings/wishlist allocations reserve money without being expenses. Keep these concepts separate.
- Paying a debt does not remove its scheduled monthly payment from a ratio until the debt's schedule/status changes. Paying a bill does remove its unpaid occurrence from the remaining cash requirement.
- A scheduled bill and its linked paid transaction must never both be subtracted as unpaid cash obligations.
- No recommendation may automatically create borrowing, reduce protected savings, move money, or complete an external purchase.
- Users can override planning preferences, but the app must show the new inputs and recompute rather than bypass accounting invariants.
- First-run empty data is not equivalent to confirmed zero debt or confirmed zero commitments.
- All new records are owned by the authenticated user, and all cross-record IDs must be validated for the same owner.

## 7. Technical specifications and delivery

- [Architecture and migration](../docs/ARCHITECTURE.md): MVP boundaries and the prototype gap.
- [Financial helper](../docs/FINANCIAL_HELPER.md): formulas, assumptions, examples and acceptance cases.
- [Wishlist](../docs/WISHLIST.md): funding model, readiness, lifecycle and acceptance cases.
- [Data and API contracts](../docs/DATA_AND_API.md): target entities and operation semantics.
- [Decisions](../docs/DECISIONS.md): confirmed requirements, explicit design rules and unresolved release choices.
- [Implementation plan](../docs/PLAN.md), [current status](../docs/STATUS.md), and [testing](../docs/TESTING.md).

Conflicts are resolved in this order: latest explicit user decisions, this product baseline, detailed feature specifications, architecture/API specifications, then implementation plans. A planning document or existing code does not turn a proposed feature into an implemented one.
