# Notification preferences and device permission

Open **Settings → Notifications** in the Android or iOS app.

- **Use notifications** is off by default. Bill reminders, budget alerts and cash-review reminders are also off until selected.
- Bill reminders have a lead-time preference of the due date, 1 day, 3 days or 7 days before. Budget alerts refer to each budget's existing threshold.
- Preferences save automatically in secure local storage. They apply to this installation across sign-ins, persist through app restarts, and are not account data or synced to other devices. Signing out or deleting an account does not reset device preferences or OS permission. Turning the master preference off preserves the individual choices.
- Preference changes never request OS permission. **Allow notifications** explicitly requests access. **Open system settings** provides a path when access is denied or blocked; permission is checked again when returning to the screen. **Refresh permission** supports manual retry. Permission errors do not overwrite saved preferences.
- Android 13+ uses `POST_NOTIFICATIONS`; earlier supported Android versions check app-level notification enablement and use system settings when blocked. Android tracks whether a prior permission choice was made, while dismissed requests do not count as a first denial. iOS uses `UNUserNotificationCenter`, distinguishes provisional authorization, and opens notification settings (app settings on iOS before 16).
- Web and other unsupported platforms show an explicit unsupported message and do not request permission or offer editable device-notification preferences. Existing in-app budget alerts remain available.

This slice **does not schedule or deliver reminders**, register push tokens, add background jobs or send test notifications. The screen states that reminder delivery is coming soon. A subsequent delivery implementation must honor the master preference, each reminder type, current OS permission, sign-in ownership and sign-out cleanup; it must never interpret saved preferences as a permission grant.

## Implementation and verification

The View calls a plain-Dart notification presenter through a repository interface. The device adapter handles secure persistence and a small `pocketwise/notifications` method channel. Android and iOS implement `status`, `request` and `openSettings`; no additional Flutter dependencies or backend/schema changes are needed.

Automated coverage checks persistence across adapter instances, off-by-default behavior, read/write failures, duplicate requests, permission revocation, settings errors, unsupported platforms, explicit permission requests, resume refresh, Settings navigation and a 390-pixel phone layout at 200% text size.

Validation on 2026-10-13: all 100 Flutter tests passed and analysis was clean. Android debug, iOS simulator debug and web release builds succeeded, including the Wasm compatibility dry run.

Before shipping, verify on devices: first-run allow/deny/dismiss; repeated denial and system-settings recovery; permission revocation while backgrounded; restart persistence; Android before/after API 33; iOS authorization and return from settings. Builds and mocked permission tests do not establish those real OS journeys.

Platform references: [Android notification permission](https://developer.android.com/develop/ui/compose/notifications/notification-permission), [Apple notification settings](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getnotificationsettings(completionhandler:)), and [Apple notification-settings link](https://developer.apple.com/documentation/uikit/uiapplication/opennotificationsettingsurlstring).
