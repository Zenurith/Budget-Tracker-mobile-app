# Financial helper specification

Status: required for Release 1; not implemented in the prototype. Covers FR-30–FR-35 and supports FR-31/FR-43 commitment planning.

## Purpose and terminology

Provide a transparent personal estimate of scheduled debt payments relative to income. This is an educational planning tool, not a credit score, lender assessment or loan-approval promise.

DSR and DTI naming/bases vary by context. Pocketwise deliberately labels its two calculations by their income basis. These are product definitions, not a claim that every lender calculates them this way.

| Display name | Product formula |
|---|---|
| DSR · net income basis | `required_monthly_debt_payments / confirmed_net_monthly_income × 100` |
| DTI · gross income basis | `required_monthly_debt_payments / confirmed_gross_monthly_income × 100` |

Country-neutral product choice: label DSR as a personal net-income estimate, with no default country, statutory-deduction calculation or lender threshold. PIDM provides one public example of a net-income DSR convention that includes bank/non-bank commitments; it is a reference for the formula, not a country setting. [PIDM: What Is Debt Service Ratio](https://www.pidm.gov.my/finlit/manage-your-financial-commitments/what-is-debt-service-ratio).

The gross-income DTI definition follows the CFPB's consumer explanation. [CFPB: What is a debt-to-income ratio?](https://www.consumerfinance.gov/ask-cfpb/what-is-a-debt-to-income-ratio-en-1791/).

Sources reviewed 2026-09-28. The formulas do not use total outstanding debt divided by income and do not use business debt-service coverage ratio (DSCR).

## Inputs and normalization

- Each income source has a name, gross amount, net amount, frequency, currency and effective period. Gross and net amounts are separately supplied; the app does not invent tax deductions.
- Required debts include mortgage, vehicle, personal, education, required credit-card payments, BNPL/installments and other bank/non-bank commitments declared by the user.
- Each debt records required scheduled payment separately from optional extra repayment and outstanding principal. Outstanding principal does not enter these ratio numerators.
- Credit-card input uses a user-confirmed statement-required payment for the baseline. Do not assume a universal percentage of card balance or credit limit. Full statement payoff or extra repayment may be modelled in a scenario/cash plan.
- Living costs such as groceries, utilities and ordinary rent are excluded from this product's debt numerator and included in the cash plan. A mortgage payment belongs in debt and must not also be added as duplicate housing debt.
- R1 is individual-only. For a shared debt, use the user's explicitly entered payment responsibility and disclose that a lender may assess it differently.
- Period conversion: weekly × 52/12; fortnightly × 26/12; twice-monthly × 2; monthly × 1; quarterly ÷ 3; annually ÷ 12. Retain decimal precision during normalization; do not derive monthly debt from whichever transactions happened this month.
- Fixed sources use their confirmed schedule. Variable sources use either an explicit user-entered monthly estimate or an average of complete calendar months (user selects 3, 6 or 12); show selected months and excluded periods. Do not silently extrapolate partial data.
- Loan proceeds, refunds, internal transfers and wishlist withdrawals are not recurring earned income for this profile. A bonus is excluded unless the user explicitly includes it with a disclosed averaging period.
- Require a currency match, nonnegative amounts, a review date and confirmation that the debt list is complete, including an explicit “I have no debt” choice.
- Future-started and closed debts are excluded from the current baseline; the selected effective date and each debt's schedule decide inclusion. Missing mandatory payment data prevents a complete baseline.

## Calculation and output rules

Use one authoritative deterministic server calculation service. The presenter requests it through a model/use-case interface. NLP and an LLM must never calculate authoritative ratios.

The response includes formula version, calculation time, profile revision, effective date, income basis, normalized income totals, itemized monthly debts, ratios, warnings, input-completeness flags and the last user review time. Display ratios to two decimal places with decimal half-up rounding; preserve full calculation precision before display.

- Missing/zero gross income → DTI unavailable. Missing/zero net income → DSR unavailable. The other valid ratio may still be shown.
- Zero confirmed debt and positive income → 0.00%. Unknown debt data → incomplete, not 0%.
- Negative inputs are invalid. Zero income with zero debt still yields an unavailable ratio, not 0% or infinity.
- Net greater than gross requires correction or an explicit explanation of differently defined sources before the profile can become a confirmed baseline; never silently swap values.
- Ratios can exceed 100%; show the actual result instead of capping it.
- Results show `net income minus scheduled debt payments`, labelled **income after debt**, not “spendable money.” Essentials and savings have not been deducted.
- Ratio targets are optional user preferences. Show distance to the target; no default red/green lending bands or assertion that a specific percentage guarantees affordability.
- Any income/debt change marks saved results out of date. A review reminder appears after 30 days as a product freshness rule, not a financial standard.

## What-if workflow

1. Review/confirm current income and debt inputs.
2. View baseline ratios with expandable arithmetic.
3. Change scenario income or add/change a hypothetical monthly debt payment.
4. Show before/after ratios and remaining income after debt, with the scenario assumptions.
5. Discard the scenario or explicitly save a scenario snapshot. Neither action creates a real loan or transaction.

No APR/amortization inference in R1: the scenario accepts a monthly payment directly. A future payoff/loan calculator must specify rates, compounding, fees and repayment timing independently.

## Worked examples and acceptance cases

Amounts below are generic human-readable currency units; APIs use minor units of the user-selected currency.

| Case | Inputs | Expected result |
|---|---|---|
| FH-01 Baseline | Gross 6,000; net 5,000; car 800, study 200, required card payment 100 | Debt 1,100; DSR 22.00%; DTI 18.33%; income after debt 3,900 |
| FH-02 What-if | FH-01 plus hypothetical payment 400 | DSR 30.00%; DTI 25.00%; baseline records unchanged |
| FH-03 No debt | Confirmed no debt; gross 6,000; net 5,000 | Both 0.00% |
| FH-04 Missing denominator | Gross unknown; net 5,000; debt 1,100 | DTI unavailable, DSR 22.00%; missing-input explanation |
| FH-05 Zero denominators | Gross/net 0; debt 0 or positive | Ratios unavailable; no division by zero |
| FH-06 Over 100% | Gross 1,200; net 1,000; debt 1,500 | DTI 125.00%; DSR 150.00% |
| FH-07 Payment already recorded | FH-01 car installment linked as paid this month | Monthly ratios unchanged; corresponding unpaid cash-plan occurrence cleared |
| FH-08 Extra repayment | Required debt 1,100 plus voluntary extra 200 | Baseline numerator remains 1,100; cash plan/scenario includes extra only when explicitly committed |
| FH-09 Normalization | Weekly net income 1,000 | Monthly net income 4,333.333…; round only final display |
| FH-10 Incomplete list | One debt missing its required payment | Result labelled incomplete; no definitive ratio presented as complete |
| FH-11 Isolation/currency | Another user's debt ID or mismatched currency | Reject; no data leakage or implicit conversion |
| FH-12 Future/closed debt | Debt starts next month or is closed before effective date | Excluded now; included only in an applicable future scenario |

Required tests cover every case, decimal rounding, repeatability, source revisions and owner scoping. These tests are not present yet; current parser/transaction coverage does not cover this feature.
