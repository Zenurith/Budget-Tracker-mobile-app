# Target data and API contracts

Status: design for Release 1, not a claim of implemented endpoints. The running prototype's `/docs` describes its current API. See [STATUS.md](STATUS.md) for the gap.

## Implemented onboarding currency contract

`POST /auth/register` requires `currency` alongside name, email and password. The local-only `POST /auth/demo` requires a JSON body such as `{"currency":"USD"}`. Both accept EUR, GBP, MYR, SGD or USD, with no default; omitted, null or unsupported currency values return HTTP 422 before any account/session/sample data is written. Clients using the former implicit MYR default must now send a currency. Login and existing accounts are unchanged.

Demo amounts are illustrative minor-unit values in the chosen currency, not converted amounts or local cost estimates. Demo creation remains disabled in MongoDB mode.

## Shared conventions

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

Funding operations are unavailable offline. A client request timeout is an unknown result, not proof of failure: retry the same key or retrieve its status. A changed request requires a new key. The already-reconciled path uses an explicit reconciled-through marker to avoid reducing cash twice whether it links an existing expense or records a missing one. Test concurrent allocations and all partial-failure points against actual MongoDB transactions before release.
