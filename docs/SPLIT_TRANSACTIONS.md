# Split transactions

In the ordinary transaction editor, enable **Split across categories**. Choose 2–20 distinct categories of the selected income/expense type and enter positive amounts that exactly equal the transaction total. A split remains one record with one account, date, note and payment method. Disable splitting before changing transaction type.

Account and overall cash balances, overall budgets, daily totals and total income/spending count the full payment once. Category budgets, budget alerts/reviews, category charts and three/six-month trends use each portion. Category search/filter matches any portion but returns the single full transaction. Transaction rows show the split breakdown; amount filters apply to the total payment.

Editing and duplicating preserve splits, and disabling splits returns the whole total to the selected single category. Offline sync carries the splits in the existing queue, version checks and stable operation IDs. Export and undo preserve the stored portions. Categories referenced by any portion cannot be deleted or have their type changed.

Bill/payment and wishlist links currently require an unsplit expense. Split transactions are excluded from those candidate lists and rejected by the backend. Existing linked transactions retain the unlink/correction safeguards. CSV import continues creating ordinary unsplit transactions; edit after import to add splits.

Splits are stored inside the existing encrypted transaction document; there is no SQL migration or rewrite of old records. Omitted/empty splits retain previous behavior and legacy sync fingerprints. Server-side validation verifies all categories are accessible to the owner, match the transaction type, are distinct and sum exactly to the total in integer minor units.
