# Target data and API contracts

Status: design for Release 1, not a claim of implemented endpoints. The running prototype's `/docs` describes its current API. See [STATUS.md](STATUS.md) for the gap.

## Implemented planning contract

Implemented: `GET/PUT /financial-profile`, `GET/POST /debts`, `PUT/DELETE /debts/{id}`, equivalent `/commitments` routes, `GET /commitment-occurrences?start=&end=`, `POST /commitment-occurrences/{id}/payments`, and `DELETE /commitment-occurrences/{id}/payments/{transaction_id}`. `GET /planning?start=&end=` returns the plan and occurrences from one aggregate read. The generated API `/docs` is authoritative for field names; the target entity tables below describe later capabilities as well.

The existing private `pocketwise.documents` table stores one `planning` document per owner containing revision, profile, debt/bill schedules, payment links and payment operation results. Occurrences are derived with stable IDs; reading does not post transactions. Mutations require `expected_revision` (query parameter for deletes). Payments also require `operation_id`: same key/body returns the saved result; changed body conflicts. Expense creation/linking, plan changes and operation results commit or roll back together. A link can be removed without deleting its expense; unlink first before editing/deleting that expense. Paid history protects schedule terms and effective dates.

Profile currency matches the account; timezone must be explicitly supplied. Gross/net missing values differ from zero; variable income may use a declared monthly estimate with notes. Debt-list confirmation is unknown, complete or none. Debt changes invalidate review; review age is flagged after 30 days. Required debt payment and optional extra payment remain separate. Credit cards use an explicitly confirmed statement-required payment. DSR/DTI are calculated by the financial-helper endpoints described below. Queries are limited to 367 days and 5,000 occurrences. Before profile setup, due-date status provisionally uses UTC.

Personal JSON export includes planning and calculation snapshots, excluding internal operation replay records/request hashes; account deletion removes both. Multi-record protected funding and cash reconciliation are still future work.

## Implemented financial-helper contract

- `POST /financial-helper/calculate`: `{expected_revision?, effective_date?}`. Defaults to the profile timezone's current day. A supplied stale revision returns 409; incomplete inputs return 200 with structured reasons and null ratios.
- `POST /financial-helper/scenarios`: requires `expected_revision` and `assumptions`; accepts `effective_date`. Assumptions contain account `currency`, optional integer-minor-unit `gross_monthly`/`net_monthly`, `additional_debt_monthly` (default zero), `debt_payments: [{id, monthly_payment}]`, and `notes`. Null/omitted income retains the declared source totals; zero is an explicit override. Foreign debts return 404, inactive overrides and currency mismatches return 422. The response contains baseline and scenario results from the same plan read. Nothing is persisted.
- `POST /financial-helper/snapshots`: requires `name`, `expected_revision`, `effective_date`, and `operation_id`; optional `assumptions` selects a scenario. The server recalculates from the revision-checked plan, preserving inputs/results. Same key and request returns the saved record; a changed request conflicts. Records live in `collection = calculation_snapshots` in the existing private table. Snapshot creation does not increment the planning revision.
- `GET /financial-helper/snapshots?page=1&page_size=20`: owner-scoped history, newest first, with `outdated` and `review_due` flags. Maximum page size 100. Pagination currently happens after the repository owner query, not in SQL.

Results include `formula_version`, `calculated_at`, `source_revision`, `input_hash`, `effective_date`, `currency`, `reviewed_at`, completeness/reasons, warnings, itemized normalized sources/debts and `ratios.dsr`/`ratios.dti`. Ratio `value` and `distance_to_target` are two-decimal strings; normalized monetary values are decimal strings in minor units and can contain fractions. `income_after_debt` has not deducted essentials or savings.

Financial profile writes additionally accept nullable `dsr_target`/`dti_target` percentage strings (0–9999.99, up to two decimals). Targets have no default and are personal preferences. `distance_to_target` is ratio minus target in percentage points. Reports includes `review.debt_ratios` using declared schedules at month end, or today for the current month, with date/basis caveats.

## Implemented onboarding currency contract

`POST /auth/register` requires `currency` alongside name, email and password. The local-only `POST /auth/demo` requires a JSON body such as `{"currency":"USD"}`. Both accept EUR, GBP, MYR, SGD or USD, with no default; omitted, null or unsupported currency values return HTTP 422 before any account/session/sample data is written. Clients using the former implicit MYR default must now send a currency. Login and existing accounts are unchanged.

Demo amounts are illustrative minor-unit values in the chosen currency, not converted amounts or local cost estimates. Demo creation remains disabled in Supabase Postgres mode.

## Shared conventions

Implemented tracking additions: `GET /transactions` combines inclusive `start`/`end`, `min_amount`/`max_amount` (integer minor units, zero allowed), category/type, and `q` matching notes or category names. Reversed dates or amount ranges return 422. Results have stable date/created-at/ID ordering and page/page-size metadata; pages are live reads, not a fixed snapshot during concurrent edits. `GET /reports/summary` now includes `review` with period status, entry/day counts, recorded spending change from the prior month, prior entry count and independent budget variances. Coverage is explicitly unknown beyond recorded entries. Debt ratios use declared schedules as described above; goal/wishlist progress remains unimplemented.

The following account endpoints are implemented: `PUT /auth/me` accepts only `{"name":"New name"}` (trimmed, nonblank, maximum 80 characters); extra fields, including currency, email and owner ID, are rejected. `GET /auth/me/export` returns a JSON attachment with `schema_version: 1`, UTC `exported_at`, `money_unit: "minor_units"`, public `account`, all owned `transactions` and `budgets`, and `categories` including default definitions. Exports are not paginated or limited to the selected month. Authentication is required, responses use `Cache-Control: no-store`, and password hashes/session records are excluded. Export reads are not yet a transactionally consistent point-in-time backup when another client writes concurrently.

- Public IDs are opaque strings; database `_id` is internal. Every personal record has `id`, `user_id`, `created_at`, `updated_at` and integer `revision` unless immutable.
- The server derives user_id from the authenticated session and checks ownership of all referenced records.
- Monetary fields are integer minor units plus an ISO currency code. R1 supports only declared two-decimal currencies; no exchange conversion. Do not default an unspecified currency based on country or device location.
- Local civil dates use `YYYY-MM-DD`; instants use UTC ISO 8601. Store user timezone for due-date/horizon interpretation.
- Calculation results expose decimal percentages as strings (for example `"18.33"`) and unavailable values as null with structured reasons.
- Mutations affecting financial inputs increment the user's funding/profile revision. Revision tokens protect against stale writes; timestamps alone are insufficient.
- List endpoints use pagination. Singleton profiles and calculation responses are not artificially paginated.
- Error envelope: `{ "error": { "code": "stale_revision", "message": "Review the updated plan.", "fields": {} } }`. Suggested codes include `validation_error`, `unauthorized`, `not_found`, `incomplete_inputs`, `currency_mismatch`, `insufficient_unallocated_funds`, `stale_revision`, and `linked_purchase_requires_reversal`.
- Use 401 for missing/expired authentication, owner-scoped 404 for missing/foreign resources, 409 for revision/invariant conflicts, 422 for invalid/incomplete calculation input, and 429 for rate limits. A preview may instead return 200 with `complete: false` and unavailable result fields; never return a fabricated zero.
- An incomplete calculation preview returns structured missing fields. A funding/purchase commit with incomplete inputs is rejected.

## Collections/entities

| Entity | Important fields beyond shared metadata | Invariants |
|---|---|---|
| users | email, password_hash, name, currency, timezone, preferences | Unique normalized email; profile responses never expose password hash |
| sessions | token_digest, expires_at, revoked_at | One-time refresh consumption; expiry cleanup |
| transactions | amount, type, category_id, date, note, payment_method, source, commitment_occurrence_id?, wishlist_purchase_id?, client_operation_id | Positive actual amount; valid owner/category; no implicit earned-income classification for borrowing/transfers |
| categories | name, type, icon, color, default flag | Defaults read-only; used categories cannot be silently removed |
| budgets | category_id?, period, limit_amount, alert_threshold | Unique owner/period/category; overall and category limits overlap for reporting, not separate cash reserves |
| financial_profiles | currency, income_sources[], confirmed_no_debt, reviewed_at, input_basis | Gross/net separately declared; basis and completeness preserved |
| debt_commitments | kind, required_payment, frequency, optional outstanding_balance, payment_basis, due_rule, start_date, end_date?, status | Only effective active schedules enter ratio baseline; optional extra payments separate |
| commitments | kind, amount, frequency, due_rule, debt_id?, allowance_id?, protected_saving_goal_id?, essential flag | One source of each required cash obligation; no duplicate debt/bill schedule |
| commitment_occurrences | commitment_id, due_date, expected_amount, paid_amount, linked_payment_ids[], state | Stable occurrence ID; partial/paid state derives from linked payments; remaining amount cannot be negative |
| goals | kind, name, target_amount, target_date?, priority, protected flag | Target is not funded amount; funded amount derives from reservations |
| funding_snapshots | included_accounts[], liquid_total, as_of, reviewed_at, horizon_end, confirmations, reconciled_through_event, revision | Manual confirmed cash; excludes unavailable/expected money; records which events already affect the balance |
| funding_plans | essential_allowances[], buffer_amount, next_income_date?, monthly_forecast_surplus, reviewed_at | No overlap with occurrences/reserves; future surplus is not available cash |
| wishlist_items | name, target_cost, currency, priority, target_date?, monthly_contribution?, next_contribution_date?, notes, reference_url?, lifecycle | Funded amount/readiness derived; purchased state requires linked purchase operation |
| reservations | owner_type (emergency/goal/wishlist), owner_id, amount, funding_revision | Single source of reserved balances; aggregate protected funds never overallocated by a commit |
| reservation_events | operation_id, kind, source/destination reservation, amount, prior/new revision | Append-only contribution/release/reallocation/consume/reversal record |
| wishlist_purchases | wishlist_id, transaction_id, cost, funding_revision, readiness_quote_id?, readiness_assessment, baseline_effect (`subtract_from_prior_snapshot` or `already_reconciled`) | One purchase per active item; explicit existing-expense versus new-expense behavior |
| calculation_snapshots | kind, formula_version, inputs, outputs, source_revision, effective_date | Saved only on request; old snapshots marked outdated rather than silently overwritten |
| idempotency_records | operation_key, route, request_hash, response, owner_id | Same key/body returns same outcome; same key/different body conflicts |
| nlp_feedback | original_text, predicted, corrected, consent_basis | Planned R2; minimize content and respect deletion/export |

Reservations may be stored as separate documents or inside a per-user aggregate; implementation must preserve the same invariants. Database-side aggregate design is selected during the funding slice, not inferred from table layout.

Recommended indexes: normalized users.email unique; each public id unique; transactions(owner,date,id); budgets(owner,period,category) unique; occurrences(owner,commitment,due_date) unique; wishlist(owner,lifecycle,priority); reservations(owner,owner_type,owner_id) unique; idempotency(owner,operation_key) unique; TTL on session expiry where supported. Account deletion covers every collection, receipt object and cache namespace.

## Target endpoints by capability

Existing endpoint names are retained where possible. New methods are planned until implemented and tested.

| Capability | Endpoints / semantics |
|---|---|
| Account | `POST /auth/register`, `/auth/login`, `/auth/refresh`, `/auth/logout`; `GET/PATCH/DELETE /auth/me`; `POST /auth/password-reset/request`, `/auth/password-reset/confirm`; `GET /me/export` |
| Transactions | `GET/POST /transactions`, `PUT/DELETE /transactions/{id}`; filters and pagination; link guards for wishlist/commitment records |
| Categories/budgets/reports | Existing categories and budget operations; `GET /reports/summary?month=`; monthly review extends the current report contract |
| Natural entry | `POST /nlp/parse` returns an editable draft, no save; feedback/query endpoints remain later scope |
| Financial profile | `GET/PUT /financial-profile` with revision precondition |
| Debts | `GET/POST /debts`, `PUT/DELETE /debts/{id}`; retain effective history where referenced by saved snapshots |
| Financial helper | `POST /financial-helper/calculate` using confirmed profile/revision; `POST /financial-helper/scenarios` is a non-persisting calculation despite its resource-style name; `GET/POST /financial-helper/snapshots` explicitly lists/saves history |
| Commitments | `GET/POST /commitments`, `PUT/DELETE /commitments/{id}`; `GET /commitment-occurrences?start=&end=`; `POST /commitment-occurrences/{id}/payments` links/records payments idempotently |
| Goals | `GET/POST /goals`, `PUT/DELETE /goals/{id}`; deletion with funds requires explicit release/reallocation |
| Funding | `GET/PUT /funding/snapshot`, `GET/PUT /funding/plan`, `GET /funding/availability`; all outputs include revision/completeness/freshness |
| Wishlist | `GET/POST /wishlist`, `PUT /wishlist/{id}` for item fields and lifecycle changes; money release is a separate explicit operation |
| Reservations | `POST /funding/allocations`, `/funding/releases`, `/funding/reallocations`; require expected revision and idempotency key; cannot overspend unallocated cash |
| Readiness | `POST /wishlist/{id}/readiness` returns derived status, arithmetic, reasons, quote ID and funding revision; no mutation of funds |
| Purchase recording | `POST /wishlist/{id}/purchases` with actual amount/date/category or an existing transaction ID; require idempotency key and expected revision; quote for the prior-snapshot deduction path; explicit reconciliation marker for already-included payments |
| Purchase reversal | `POST /wishlist-purchases/{id}/reversals`; coordinated event, transaction/reservation reconciliation and invalidation, not ordinary transaction deletion |

Public exceptions to bearer auth: health, registration/login, reset request/confirmation and refresh with its own token. Logout can identify the refresh credential itself. A local demo endpoint remains development-only. All financial/helper/wishlist operations require authentication, including previews.

## Concurrency acceptance contract

For new purchase recording, transaction creation, reservation consumption, item transition, snapshot adjustment, revision advancement and idempotency result storage succeed or fail together. Readiness quotes are invalid after any relevant revision change; they are not authorization to bypass a fresh invariant check.

Funding operations are unavailable offline. A client request timeout is an unknown result, not proof of failure: retry the same key or retrieve its status. A changed request requires a new key. The already-reconciled path uses an explicit reconciled-through marker to avoid reducing cash twice whether it links an existing expense or records a missing one. Test concurrent allocations and all partial-failure points against actual Supabase Postgres transactions before release.
