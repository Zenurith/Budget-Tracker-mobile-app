# Notifications and bill reminders

Open **Settings → Notifications** in the Android or iOS app. Enable **Use notifications**, select **Bill reminders**, and explicitly allow device notifications. Choose the due date, 1 day, 3 days or 7 days before.

## Bill delivery

- Pocketwise schedules local reminders around **9 a.m. in the financial profile timezone**. All unpaid bills and debt payments due on the same date share one reminder. Partial payments remain included; fully linked payments remove the paid occurrence.
- The app schedules a rolling **60-day** window, with at most 60 notifications. It refreshes on sign-in, app resume, notification settings changes, planning edits and synchronization. Open Pocketwise regularly to extend the window. The financial profile must have a timezone.
- Bill/debt edits, deletion and payment-link changes cancel the old schedule before fetching a replacement. If that fetch fails, reconnect and refresh. Ordinary refresh failures preserve previously scheduled reminders, which may be stale. Changes made on another device are reflected after a successful refresh here.
- Past reminder times are skipped; there is no catch-up burst. Stable date IDs prevent duplicate pending notifications. A local history of elapsed scheduled times suppresses replay after lead-time changes; it is not proof of delivery.
- Notifications contain the unpaid-item count and due date, without bill names or amounts. Tapping opens Pocketwise. The Settings screen shows scheduled dates, timezone, window end and refresh errors.
- Sign-out, session reauthentication and account deletion await cancellation. If cancellation fails, the session-ending action reports an error so it can be retried. Switching accounts clears the previous account's schedule.

Android uses inexact alarms without exact-alarm permission and includes receivers to restore scheduled notifications after reboot. OS power management, notification channel settings, Focus modes and permission changes may delay or suppress delivery. Scheduling is best effort, not a guaranteed alarm. No push tokens, server delivery jobs or background network refresh are implemented.

## Budget alert delivery

Enable **Use notifications** and **Budget alerts**, then allow device notifications. Pocketwise checks the current month in your financial profile timezone on sign-in, resume, preference changes, budget/transaction changes, payment and wishlist activity, imports/undo, and successful synchronization. **Check budget alerts** provides a manual retry. Checks require a financial-profile timezone and fresh server data; pending, conflicting or offline spending changes defer checks until synchronization succeeds. Browsing a historical report does not change the alert month.

Overall and category budgets use their existing percentage thresholds. Exact integer comparisons avoid rounding a nearly reached threshold upward. Enabling alerts also checks budgets already at or above their threshold. Multiple newly eligible budgets share one generic notification with their count and month; amounts and category names are omitted. Later alerts replace that displayed budget notification, without changing scheduled bill reminders.

Each budget has at most one notification attempt per month per installation/account. Restarting, switching accounts, signing out/in, toggling preferences, changing thresholds or dropping below and crossing again do not reset this history. A new month or newly eligible budget can alert again. The device stores opaque budget IDs and month keys in secure storage, prunes old history on delivery checks, and removes the current account's history when deleting that account. Signing out cancels the displayed alert but retains deduplication history.

To prevent duplicate alerts after a crash or ambiguous native failure, the app records the attempt before asking the OS to display it. A failure in that gap can suppress an alert for the month; history is not proof of delivery. OS permission, channel settings or Focus can also suppress delivery. No background spending checks or remote push occur while the app is closed. Other devices check independently.

### Actionable budget reviews

New budget notifications open a fresh review of the affected budgets and alert month. The same view is available from **Budgets → Budget actions → Review spending**. It shows spent/limit, remaining or overspent amount, threshold status, the top three spending categories, and days remaining in the financial-profile timezone. **Review transactions** opens that month with expense/category filters; **Adjust limit** reuses the existing budget editor and refreshes the review afterwards.

For the current month, the daily guide is `max(0, remaining budget) / days remaining`, rounded down to minor currency units, including today. It is budget headroom, not verified cash; overlapping overall/category guides must not be added together. Historical/future months and missing timezones have no daily guide. The review includes the same recorded monthly expenses as the budget totals, including any future-dated entries in that month.

Reviews fetch fresh owner-scoped server data, without an offline-cache fallback. Figures and actions are hidden during loading, after edits or pending-sync changes, and after the earlier of five minutes and local midnight (the display checks every 30 seconds). Resume and manual refresh fetch again. Deleted budgets show an unavailable message. Older notifications without a review payload open the app normally.

The shared native notification initializer handles both warm taps and cold-start launch details without permission prompts. Payloads contain only owner, month and opaque budget IDs; amounts/category names remain inside the app. Navigation waits for authentication, rejects another owner's target, and clears on session end. Tapping a notification does not change a budget or transaction. Physical Android/iOS tap journeys still need device acceptance.

## Cash-review reminders

Enable **Use notifications** and **Cash review reminders** to check a started funding setup on sign-in, resume, relevant record changes, successful synchronization and preference changes. **Check cash review** provides manual retry. Checks are skipped while offline or while transaction synchronization is busy or pending. No background polling, scheduled server jobs or remote push is added.

The read-only `/notifications/cash-review` endpoint reuses funding availability to detect missing or stale inputs: changed cash activity, expired cash snapshots, changed obligations/goals and a funding plan that needs today's review. Accounts without a cash snapshot or funding plan are not reminded to complete onboarding. The response contains only owner, profile-local day, eligibility and a generic status; notification payloads contain only owner and destination.

At most one attempt is made per account per local day on this installation. Secure device storage preserves the last attempted date through restarts, sign-outs and preference changes. Moving the profile timezone back to an earlier date does not allow an extra reminder. Attempts are recorded before native delivery; a crash or ambiguous OS failure may suppress that day's reminder. Account deletion clears its history. Reviewing funding, disabling reminders or ending the session cancels the displayed cash reminder independently of bills and budget alerts.

Tapping a reminder opens Protected Funding and fetches the latest state, where existing missing-input and stale-reason explanations lead into cash reconciliation and plan review. Cold-start taps wait for authentication; another account's payload is ignored. No balances or financial amounts are shown in notifications. Delivery is best effort on Android/iOS and requires OS permission; the app must open or be used for a check to occur. Physical-device delivery remains to be verified.

## Preferences and permission

All choices are off by default. Preferences save automatically in secure local storage, apply to this installation across sign-ins, and are not synced account data. Signing out does not reset preferences or OS permission. Turning the master preference off preserves individual choices while cancelling bill reminders.

Preference changes never prompt for OS permission. **Allow notifications** explicitly requests access; **Open system settings** supports recovery from denial or blocking. Permission is rechecked on resume and can be refreshed manually. iOS provisional authorization is accepted. Web and other unsupported platforms cannot schedule device reminders.

The existing `pocketwise/notifications` native bridge handles permission status, requests and settings. `flutter_local_notifications` handles scheduling, with `timezone` converting the server's UTC instants. The authenticated read-only `/notifications/budgets` endpoint returns current-month eligible budget IDs. The `/notifications/bills` endpoint derives owner-scoped occurrences and timezone-aware dates from the existing planning model. No database migration is required. Secure storage holds the schedule owner and elapsed-time history separately from preferences.

## Verification

Validation on 2026-10-14: 282 backend tests passed, with 9 opt-in integration tests skipped. The full Flutter suite passed 111 tests, followed by all 5 notification widget tests including a newly added schedule-status/error test (112 tests total). Coverage includes grouping, partial/full payments, deletion, ownership, daylight-saving transitions, missed times, duplicate prevention, preference changes, network failures, refresh races and cancellation during logout.

Flutter analysis is clean. Android debug, iOS simulator debug and web release builds succeeded, including the Wasm compatibility dry run. The existing Android Kotlin Gradle migration warning remains.

Before shipping, verify on physical Android and iOS devices: allow/deny/dismiss and settings recovery, actual scheduled delivery, revocation while backgrounded, restart/reboot restoration, account switching and logout cleanup. Builds and mocked native adapters do not establish these real OS journeys.

Budget-alert validation on 2026-10-15: tests cover exact threshold boundaries, category/overall scope, income exclusion, corrections/deletion, timezone month boundaries, owner isolation, duplicate suppression across restart and sign-in, pending sync, permission denial, native errors, logout races, independent bill cancellation, account deletion and large-text status/retry UI. Physical-device delivery remains pending.

Validation results: 286 backend tests passed (9 opt-in integration tests skipped); the full Flutter suite passed 120 tests, then 16 notification regression tests passed including the additional widget test (121 total tests covered). Android debug, iOS simulator debug and web release builds succeeded, including the Wasm dry run.

Actionable-review validation on 2026-10-15: 292 backend tests passed (9 opt-in integration tests skipped), all 127 Flutter tests passed, and analysis was clean. Android debug, iOS simulator debug and web release builds succeeded, including the Wasm dry run. Tests cover cold/warm routing, shared initialization, owner validation, month/category navigation, review expiry, deleted budgets, daily-guide rounding and 200% phone text. Native tap journeys remain unverified on physical devices.
