# Product and architecture decisions

Updated 2026-09-28. This file separates confirmed requirements from unresolved implementation choices.

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

## Still unresolved before release

On 2026-09-30 the user deferred password-reset email work. Account recovery remains an R1 requirement; do not select an email provider or claim the recovery flow is complete until that work resumes.

| Question | Current evidence/default | When it must be resolved |
|---|---|---|
| Supported OS floor | Original requirements say Android 8+/iOS 13+; generated iOS project is 15.0 | Before native release/toolchain commitment |
| Production deployment and data region | None selected; Supabase Postgres + FastAPI required, local SQLite only for development | Before collecting production financial data |
| Funding transaction implementation | Requires Postgres transactions or an equivalent proven atomic aggregate | Before reservation/purchase implementation |
| Email reset provider | Not selected | Before completing R1 account recovery |
| Offline store and conflict policy details | Stable operation IDs and visible conflict handling required; technology not selected | Before offline sync implementation |
| Production web support | Web is currently a preview/demo target | Before advertising web as a supported production client |

No remaining item prevents continuing the architecture and core tracking slices. None permits silently weakening a requirement. Registration and demo onboarding require explicit currency selection in the UI and API; neither assumes a country or currency.
