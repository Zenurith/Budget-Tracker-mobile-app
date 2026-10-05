# Offline records and transaction synchronization

Recent transaction pages, categories, budgets and monthly reports are cached on the device. Cached screens show the oldest cached response time and label summaries as estimates. An unseen month/filter/page needs a connection; this is a recent-record cache, not a complete local database. Pending changes are listed separately and excluded from report totals until synchronized.

## User flow

- Sign in online once. With a retained refresh session, the app can reopen the same cached account when the server is unreachable. Authorization failures require signing in again and never authorize cached server requests.
- Add a manual transaction, or edit/delete a previously loaded transaction. The device saves a stable operation ID and the reviewed record version before attempting any network write. Only one pending operation per existing transaction is allowed; resolve it before editing again.
- Open **Settings → Offline & sync** or **Review sync** in the pending/offline banner. Sync runs after saving, sign-in and app resume, and on **Sync now**. There is no background scheduling or continuous connection polling.
- A changed, deleted, linked or invalid server record becomes **Needs review**. Review the current server version, then explicitly discard the rejected local change or apply the local edit/deletion against that reviewed version. A further concurrent change requires another review. Linked purchases and bill payments retain their coordinated correction guards.
- A timeout might mean the server already saved the change. Such an operation must be replayed with its original ID before it can be resolved; it is not silently discarded or sent with a new ID.
- **Sign in again · keep pending changes** locks the UI and permits fresh credentials without deleting queued work. A different owner cannot take over a pending queue. Ordinary sign-out requires resolving pending work, then removes the cached account and data; a confirmed online account deletion removes the device data and server replay records. Personal JSON export includes pending device transactions separately from server records.

Funding, wishlist purchase/refund/correction operations, financial-profile changes, categories, budgets and NLP parsing require the server. Pending transaction work blocks protected-funding reads and mutations so that a server cash quote cannot ignore known local spending. After synchronization, reconcile cash and review the funding plan before using readiness. No offline purchase or allocation is authorized.

## Persistence and API contract

The existing `flutter_secure_storage` adapter stores a single versioned document scoped to the server URL and account. No new package is required. Cache retention is bounded to 40 query responses and 750,000 UTF-8 JSON bytes. The queue is separately capped at 100 operations and is never evicted to make room for cache data. Writes are serialized; failed queue persistence prevents transmission, and account-generation checks suppress late reads after sign-out. Android automatic backup is disabled to keep device-bound encrypted state out of application backups. Platform secure-store behavior and physical-device recovery still require native acceptance testing.

`GET /transactions` and `GET /transactions/{id}` expose a `version` hash of the complete stored record, including commitment/purchase links. The client carries the version displayed in the editor into an offline edit; it does not substitute a newer background-fetched version.

`POST /transactions/sync` accepts:

```json
{
  "operation_id": "stable_random_identifier",
  "action": "update",
  "transaction_id": "owned_transaction_id",
  "expected_version": "64_character_record_hash",
  "transaction": {
    "amount": 1250,
    "type": "expense",
    "category_id": "food",
    "date": "2026-10-05",
    "note": "Lunch",
    "payment_method": "Cash",
    "source": "manual"
  }
}
```

Create omits transaction ID/version; delete omits the transaction body. Responses contain the original action/operation ID and saved transaction (or null after deletion). Reusing an ID with identical input returns the original response, including after later edits/deletion; reusing it with changed input conflicts. Updates/deletions reject an outdated version before mutating anything. Legacy online routes remain compatible; the production Flutter composition uses the sync route for ordinary transaction writes.

The server uses the existing owner transaction lock and private JSONB document table. Transaction writes, cash invalidation and `transaction_operations` replay records commit or roll back together. No SQL migration is needed. Replay records have no automatic expiry, are excluded from personal server exports, and are removed on account deletion. Real Supabase tests cover concurrent retry deduplication, competing edits and rollback of all three records.

## Limits

This does not provide an offline web app shell installation, offline signup, background synchronization, offline category/budget editing, offline NLP, offline bank reconciliation, or offline funding authorization. Web remains a development target. Uncached data, expired-session reauthentication and final server decisions require connectivity. Native builds, physical-device restart/secure-storage tests and production encryption/backup verification remain release gates.
