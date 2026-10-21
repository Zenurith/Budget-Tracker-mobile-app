# Accounts and transfers

Open **Settings → Accounts & transfers** to add up to 30 named accounts in your existing account currency. Enter the opening balance at the start of the opening date. Zero and negative balances are supported. Opening dates cannot be in the future.

In the ordinary transaction editor, choose **Account**. Existing records remain **Unassigned**; payment method is not treated as an account. Assign only transactions on or after that account's opening date. If starting with today's real balance, avoid assigning earlier activity already included in that balance. Account opening amounts are independent of the existing budget-wide opening balance configuration and do not create income or alter Protected Funding cash.

Account balance = account opening amount + assigned income − assigned expenses + incoming transfers − outgoing transfers, through today in the financial profile timezone (UTC without a profile). Future-dated transactions are excluded until their date arrives. Unassigned activity is excluded from individual balances and is counted visibly; it remains in reports and budgets. Account balances may be negative and do not authorize spending.

**Record transfer** records a transfer already made between two different owned accounts, with date, amount and note. It does not execute a bank transfer. Both sides are derived from one immutable transfer record committed atomically. Transfers never become transaction income/expenses and never affect spending budgets. They invalidate manually reviewed funding cash. To correct an incorrectly recorded transfer, record the opposite transfer and then the correct one; review the resulting history. Fees should be separate expenses assigned to the paying account.

**Check actual balance** saves an immutable observation of actual versus recorded balance through today. Checks do not create balancing adjustments or update Protected Funding. Correct missing or mistaken records, then check again. Review same-day timing and unassigned activity. The screen shows the 30 most recent checks and transfer history.

Account creation, transfers and balance checks require online access and no pending/busy transaction sync. Ordinary account-tagged transaction creation/editing continues through the existing offline queue, using cached account choices. Server validation rejects foreign accounts and dates before account opening. Existing linked bill/wishlist transactions keep their correction guards; those generated expenses and CSV imports remain unassigned unless corrected through the existing transaction flow.

Storage uses the existing encrypted private document repository with `money_accounts`, `account_transfers` and `account_reconciliations` collections. No SQL migration or live-data rewrite is needed. Account IDs are optional on transactions; legacy sync retries without an account ID preserve their prior fingerprint format. Mutations use owner transactions and stable operation IDs. These collections and `account_changes` are included in personal-data export and account deletion.

Use **Edit / archive account** to rename an account, correct its opening amount/date, archive it or restore it. Changes use the revision displayed when the editor opened and an idempotent operation ID. The 30 most recent changes are shown; full changes are included in export. Opening dates cannot move after any existing assigned transaction or transfer. Undo also checks the corrected opening date before restoring older activity.

Archived accounts and their balances/history remain visible. New assignments, transfers and balance checks require restoration first. Existing transactions may still be edited while retaining the same archived account. Duplicating a transaction from an archived account clears that account choice when the archive status is known. Stale cached choices are revalidated by the backend.

Opening corrections change account ledger balances only; immutable reconciliation observations keep the amounts recorded at the time. No balancing transaction is created. Account deletion, automatic bank imports, foreign currency transfers and automatic migration of legacy budget-wide opening balances are not supported.

## Guided balance review

Accounts & transfers → Check actual balance now explains the signed difference
(actual minus recorded), shows the opening/income/expense/transfer breakdown,
and lists the latest 30 assigned activities through today. The account overview
also returns up to 30 recent unassigned entries through today.

Unassigned entries are flagged when their signed amount equals the difference
and their date is on or after the account opening. Repeated date/type/amount/note
combinations in recent activity are possible-duplicate clues, not proof. These
bounded lists cannot rule out older activity or combinations of discrepancies.
Use Transactions for transaction corrections and the existing explicit transfer
correction flow for transfers, then refresh and review again.

Editing actual cash resets confirmation. Saving records the comparison only;
no adjustment, reassignment, deletion or funding update occurs automatically.
