# Opening balances, reconciliation, CSV import and undo

Implemented 2026-10-12. These tools are online operations in **Settings**. Pending
offline transaction changes must be synchronized or resolved before opening them.
They use feature presenters and injected repository interfaces; financial decisions
remain in the backend. New records inherit AES-256-GCM encryption from the existing
repository layer and use the existing private document table without schema changes.

## Opening balances and reconciliation

Choose **Settings → Opening balances & reconciliation → Set opening balances**.
Enter an opening date, account names and amounts, then explicitly confirm. Amounts
may be zero or negative and use the account currency. Names must be distinct.

The opening amounts represent the **start** of that date. The recorded total is
their sum plus income minus expenses dated on/after the opening date through the
selected reporting date. Transactions before the opening date stay in history and
spending reports but are not added again to the opening balance. Opening amounts
do not create income, expenses or budget spending. Updating them replaces the
current baseline and preserves a before/after revision in history.

The app currently tracks transactions across one budget, not by bank account.
Names identify the accounts covered by the baseline; they do not add per-account
transaction ledgers or transfers. Include only the accounts whose activity you
record. A recorded total remains distinct from reconciled spendable cash.

**Reconcile cash** opens protected funding. Every new confirmed cash snapshot
saves its previous snapshot, observed balances, recorded expectation, comparison
date/timezone and difference in reconciliation history. Comparisons require the
same named accounts as the opening baseline. Amounts are compared through the
snapshot's local calendar day because transaction dates have no intraday time.
Check same-day timing and missing transactions before interpreting a difference.
No adjustment transaction is posted automatically. Past comparisons are snapshots;
later edits do not silently recalculate them. Earlier cash snapshots overwritten
before this feature cannot be reconstructed.

## CSV import

Choose **Settings → Import CSV transactions**, select a UTF-8 comma-separated file
up to 1 MB / 1,000 rows, inspect the preview and confirm selected rows. Supported
headers are:

```csv
date,type,amount,category,note,payment_method,currency
2026-10-01,expense,12.50,Food,Lunch,Cash,EUR
2026-10-02,income,2500.00,Salary,October pay,Bank,EUR
```

`date`, `type`, `amount` and `category` are required. Use `YYYY-MM-DD`, `income` or
`expense`, a positive major-unit amount with at most two decimal places, and an
existing category name or ID matching the type. Optional `note` and `payment_method`
default to empty and Cash. An omitted currency uses the account currency; a supplied
currency must match. There is no conversion or automatic bank-column mapping.
Quoted commas and a UTF-8 BOM are supported. Invalid rows explain the error and
cannot be selected; valid rows can be imported independently.

Possible duplicates match date, type, exact amount and normalized note, regardless
of category/payment method. Matches already in the database and repeated rows in
the file are deselected. A user can explicitly include a matching row if it really
is a separate transaction. These are candidates, not proof of duplication.

Preview writes nothing. Commit validates everything again under the owner lock;
newly detected duplicates cause a conflict requiring another preview. Stable request
IDs make retrying a lost response safe. Selected rows, their undo history, the cash
invalidation marker and the import receipt commit or roll back together. Import
receipts identify the added transactions; full CSV files are not retained.

## Undo

Choose **Settings → Undo changes & history**. Ordinary transaction additions,
edits and deletions made after this release are recorded with before/after values.
Undo is available for 30 days, including for individual imported transactions.
It updates recorded totals and marks cash for reconciliation; it never moves money.

Undo requires the current transaction to match the saved after-state. Undo newer
changes first. Purchase/payment links cannot be bypassed. Restoring a transaction
whose category no longer exists requires resolving that category first. Repeating
the same undo is harmless. Audit records remain in personal-data export even after
their undo window closes; account deletion removes them. This feature does not undo
account deletion, password changes, budgets, categories, funding allocations or
wishlist operations, which retain their existing correction flows.

## Password recovery and SMTP

Select **Forgot password?** on sign-in. Request an email, then choose **Enter reset
code** and paste the emailed code with a new password. Codes expire in 30 minutes,
are single-use and are stored only as hashes. Responses do not disclose whether
an email belongs to an account. Requests are rate-limited by client address and
existing-account delivery is limited to once per minute.

Reset runs atomically with password hashing, token consumption and deletion of
all access/refresh sessions. The user must sign in again; reset never logs them in
automatically. Pending device transactions are retained for reauthentication.
Existing sessions from before this release may refresh or require sign-in because
access tokens now also require an active server-side session record.

For a locally running backend, start the development inbox from the repository root:

```sh
docker compose -f compose.mail.yaml up -d
```

Put these values in `backend/.env`, then restart the backend:

```dotenv
SMTP_HOST=127.0.0.1
SMTP_PORT=1025
SMTP_SECURITY=local
SMTP_FROM=Pocketwise <noreply@localhost>
```

Open **http://localhost:8025** to read captured messages. Mailpit does not send real
emails. Its ports are bound to loopback. Docker Desktop must be running. When both
API and Mailpit run in Compose, use `SMTP_HOST=mailpit` and run with both files:
`docker compose --env-file backend/.env -f compose.yaml -f compose.mail.yaml up -d`.
The API's existing database/encryption settings remain required.

For real email, set `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` and
an authorized `SMTP_FROM` address from your provider. Use `SMTP_SECURITY=starttls`
(usually port 587) or `tls` (usually 465); certificates are verified. The `local`
mode is restricted to loopback or the Mailpit service name. Secrets stay in the
backend environment. If SMTP is unconfigured, recovery reports that it is unavailable.

Optionally set `PASSWORD_RESET_URL` to the HTTPS URL of the Flutter web app, without
query parameters or fragment. The email then includes a fragment-based reset link;
the code-entry flow works on native apps without a deep-link setup. No reset code
appears in API URLs or application logs. Recovery delivery happens in an in-process
background task; failures are logged without sensitive details. A durable email
queue and production delivery monitoring remain deployment improvements.

## Verification and deployment limits

Local tests cover both plain test repositories and encrypted repositories, including
arithmetic, history immutability, duplicate detection, import/undo rollback, retry
races, owner isolation, reset expiry/replay/concurrency and session revocation.
Flutter tests cover presenter retries/stale responses, explicit import confirmation,
default duplicate exclusion and 200% phone text. Native picker/device journeys and
live SMTP delivery still need acceptance checks. Mailpit was not launched during
implementation because the Docker daemon was unavailable.

The opt-in Supabase suite includes a new encrypted records/recovery journey but was
not run. Live data was not migrated or changed. Configure the existing encryption
key before running the backend; see [ENCRYPTION.md](ENCRYPTION.md).

References: [OWASP password recovery](https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html)
and [Mailpit Docker setup](https://mailpit.axllent.org/docs/install/docker/).
