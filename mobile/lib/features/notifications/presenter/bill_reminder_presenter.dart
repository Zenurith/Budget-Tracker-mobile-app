import '../../../core/model/contracts.dart';
import '../../../core/presentation/presenter.dart';
import '../model/notification_repository.dart';
import '../model/bill_reminder_repository.dart';

class BillReminderState {
  final bool busy;
  final int count;
  final String message;
  final String? error, timezone, windowEnd;
  const BillReminderState({
    this.busy = false,
    this.count = 0,
    this.message = 'Bill reminders are off.',
    this.error,
    this.timezone,
    this.windowEnd,
  });
}

/// Serializes device writes. A stale server response can never outlive logout.
class BillReminderPresenter extends Presenter<BillReminderState> {
  final NotificationRepository preferences;
  final BillReminderSource source;
  final BillReminderScheduler scheduler;
  Account? _account;
  bool _initialized = false;
  int _generation = 0;
  int _invalidation = 0, _clearedInvalidation = 0;
  Future<void> _deviceWrites = Future.value();
  BillReminderPresenter(this.preferences, this.source, this.scheduler)
    : super(const BillReminderState());

  Future<T> _device<T>(Future<T> Function() action) {
    final next = _deviceWrites.then((_) => action());
    _deviceWrites = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return next;
  }

  Future<void> setAccount(Account? account) async {
    if (disposed) return;
    if (_initialized && _account?.id == account?.id) return;
    _initialized = true;
    _account = account;
    final generation = ++_generation;
    emit(
      const BillReminderState(busy: true, message: 'Updating bill reminders…'),
    );
    try {
      await _device(() => scheduler.setOwner(account?.id));
      if (generation != _generation || disposed) return;
      await refresh();
    } catch (_) {
      if (generation == _generation) {
        emit(
          const BillReminderState(
            error:
                'Could not clear reminders from the previous session. Retry before switching accounts.',
          ),
        );
      }
    }
  }

  /// Awaited before tokens/account are cleared; failure prevents silent logout.
  Future<void> endSession() async {
    _account = null;
    ++_generation;
    await _device(() => scheduler.setOwner(null));
    emit(
      const BillReminderState(message: 'Sign in to schedule bill reminders.'),
    );
  }

  Future<void> refresh({bool invalidate = false}) async {
    if (disposed) return;
    if (invalidate) _invalidation++;
    final generation = ++_generation;
    final account = _account;
    bool current() => !disposed && generation == _generation;
    emit(
      const BillReminderState(busy: true, message: 'Updating bill reminders…'),
    );
    try {
      // Mutations cancel the old schedule even if the subsequent fetch fails.
      await _device(() async {
        if (current() && _clearedInvalidation < _invalidation) {
          final version = _invalidation;
          await scheduler.clear();
          _clearedInvalidation = version;
        }
      });
      final settings = await preferences.load();
      final permission = await preferences.permission();
      if (!current()) return;
      final allowed =
          permission == NotificationPermission.granted ||
          permission == NotificationPermission.provisional;
      if (account == null || !settings.enabled || !settings.bills || !allowed) {
        await _device(() async {
          if (current()) await scheduler.clear();
        });
        if (current()) {
          emit(
            BillReminderState(
              message: account == null
                  ? 'Sign in to schedule bill reminders.'
                  : !settings.enabled || !settings.bills
                  ? 'Bill reminders are off.'
                  : 'Allow device notifications to schedule bill reminders.',
            ),
          );
        }
        return;
      }
      final plan = await source.load(settings.billLeadDays);
      if (!current()) return;
      if (plan.ownerId != account.id) throw StateError('Account changed');
      if (!plan.ready) {
        await _device(() async {
          if (current()) await scheduler.clear();
        });
        if (current()) {
          emit(
            BillReminderState(
              message: plan.reason ?? 'Review your financial profile.',
            ),
          );
        }
        return;
      }
      final count = await _device(() async {
        if (!current()) return 0;
        // Also retries cleanup if an earlier owner transition failed.
        await scheduler.setOwner(account.id);
        if (!current()) return 0;
        return scheduler.replace(plan.items);
      });
      if (current()) {
        emit(
          BillReminderState(
            count: count,
            timezone: plan.timezone,
            windowEnd: plan.windowEnd,
            message: count == 0
                ? 'No upcoming bill reminders to schedule.'
                : '$count bill reminder dates scheduled.',
          ),
        );
      }
    } catch (_) {
      if (current()) {
        emit(
          BillReminderState(
            error: invalidate
                ? 'Bill changes could not be refreshed. Retry to update device reminders.'
                : 'Could not refresh bill reminders. Previously scheduled reminders may still arrive. Connect and retry.',
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    super.dispose();
  }
}
