# Product and architecture decisions

Updated 2026-10-02. This file separates confirmed requirements from unresolved implementation choices.

## Confirmed

| Decision | Basis | Consequence |
|---|---|---|
| Use Model–View–Presenter architecture | Explicit user request | Preserve feature presenters, repository interfaces and the implemented backend domain/adapter boundaries |
| Include a financial helper for DSR and DTI | Explicit user request | Add financial profile, debt commitments, deterministic formulas, explanations and what-if scenarios |
| Include a guilt-free wishlist | Explicit user request | Add savings reservations, protected obligations and explicit purchase recording |
| Country-neutral defaults | User clarification in this session | No default country, currency, tax deductions, lender thresholds or local loan schemes; user selects currency and enters gross/net values |
| Readiness uses saved money only; forecasts give a target date | User clarification in this session | Future income never counts as funded cash or marks an item ready |
| Clarify Markdown requirements before further implementation | Earlier user request, followed by continuation of implementation | Requirements baseline recorded; initial presenter migration now implemented and verified |

## Product rules selected for this baseline

These are explicit design choices that can be revised through the requirements, not claims about universal financial standards.

- Label the personal DSR calculation **net income basis** and DTI **gross income basis**. Naming conventions vary; always show the denominator. Country-neutral behavior means no lender-specific rules or automatic country inference.
- Support individual personal finances in R1, with one explicitly chosen two-decimal currency per account.
- Use deterministic server arithmetic; an LLM may not supply authoritative ratios or funding decisions.
- Require protected savings, an expense/commitment plan and a confirmed cash snapshot for wishlist readiness.
- Use a 24-hour cash-snapshot freshness window plus invalidation after known changes. This is a planning freshness rule, not bank verification.
- Use a next-income-date planning horizon; when unknown, use a displayed 30-day horizon. Future income never enters current available cash.
- Retain existing English entry parsing and core budgeting scope, and add the minimum bill/savings features needed for a meaningful wishlist.
- No bank sync, automated purchase execution, investment advice, lending decisions or payoff-interest estimates in R1.

## Funding implementation decisions (2026-10-02)

- Use the existing private document table with one owner funding aggregate and separate append-only reservation events, serialized by the existing owner transaction lock. No additional public schema, client grants or SQL migration is needed.
- Protect all scheduled debts and recurring bills, including overdue history and declared extra debt payments. Link each schedule to at most one remaining essential allowance to prevent duplicate protection.
- Reconcile manually entered cash within 24 hours, and re-review the horizon/remaining allowances each local day or after planning/goal changes. All tracked transaction changes conservatively require reconciliation.
- Model a mandatory saving as a dated minimum funded reserve. Only its unfunded difference is an obligation; allocations transfer this protection into emergency/other savings. Automatic recurring saving contributions are deferred.
- Keep external savings outside liquid cash and outside the cash reservation ledger. Targets, future surplus and payday expectations never manufacture funded cash.

## Still unresolved before release

On 2026-09-30 the user deferred password-reset email work. Account recovery remains an R1 requirement; do not select an email provider or claim the recovery flow is complete until that work resumes.

| Question | Current evidence/default | When it must be resolved |
|---|---|---|
| Supported OS floor | Original requirements say Android 8+/iOS 13+; generated iOS project is 15.0 | Before native release/toolchain commitment |
| Production deployment and data region | None selected; Supabase Postgres + FastAPI required, local SQLite only for development | Before collecting production financial data |
| Wishlist purchase transaction implementation | Funding uses an owner aggregate/event ledger with Postgres transactions and advisory locks; concurrent allocation/expense races are verified | Extend and verify the same boundary for purchases and reversals |
| Email reset provider | Not selected | Before completing R1 account recovery |
| Offline store and conflict policy | Existing platform secure storage, bounded owner/server cache, durable transaction queue and explicit version conflict review; see [OFFLINE.md](OFFLINE.md) | Native secure-store acceptance remains |
| Production web support | Web is currently a preview/demo target | Before advertising web as a supported production client |

No remaining item prevents continuing the architecture and core tracking slices. None permits silently weakening a requirement. Registration and demo onboarding require explicit currency selection in the UI and API; neither assumes a country or currency.
