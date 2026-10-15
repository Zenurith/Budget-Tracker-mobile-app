import '../../../core/model/contracts.dart';
import '../../../core/presentation/presenter.dart';
import '../model/notification_repository.dart';
import '../model/budget_alert_repository.dart';

class BudgetAlertState {
  final bool busy;
  final String message;
  final String? error;
  const BudgetAlertState({
    this.busy = false,
    this.message = 'Budget alerts are off.',
    this.error,
  });
}

class BudgetAlertPresenter extends Presenter<BudgetAlertState> {
  final NotificationRepository preferences;
  final BudgetAlertSource source;
  final BudgetAlertDelivery delivery;
  final bool Function() syncBlocked;
  Account? _account;
  bool _initialized = false;
  int _generation = 0;
  Future<void> _writes = Future.value();
  BudgetAlertPresenter(
    this.preferences,
    this.source,
    this.delivery, {
    bool Function()? syncBlocked,
  }) : syncBlocked = syncBlocked ?? (() => false),
       super(const BudgetAlertState());

  Future<T> _device<T>(Future<T> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> setAccount(Account? account) async {
    if (disposed || (_initialized && _account?.id == account?.id)) return;
    _initialized = true;
    _account = account;
    final generation = ++_generation;
    try {
      await _device(() => delivery.setOwner(account?.id));
      if (!disposed && generation == _generation) await refresh();
    } catch (_) {
      if (!disposed && generation == _generation) {
        emit(
          const BudgetAlertState(
            error: 'Could not update budget alerts. Retry.',
          ),
        );
      }
    }
  }

  Future<void> endSession() async {
    _account = null;
    ++_generation;
    await _device(() => delivery.setOwner(null));
    emit(const BudgetAlertState(message: 'Sign in to check budget alerts.'));
  }

  Future<void> forgetOwner(String owner) =>
      _device(() => delivery.forgetOwner(owner));

  Future<void> refresh() async {
    if (disposed) return;
    final generation = ++_generation;
    final account = _account;
    bool current() => !disposed && generation == _generation;
    emit(
      const BudgetAlertState(busy: true, message: 'Checking budget alerts…'),
    );
    try {
      final settings = await preferences.load();
      final permission = await preferences.permission();
      if (!current()) return;
      final allowed =
          permission == NotificationPermission.granted ||
          permission == NotificationPermission.provisional;
      if (account == null ||
          !settings.enabled ||
          !settings.budgets ||
          !allowed) {
        await _device(() async {
          if (current()) await delivery.clear();
        });
        if (current()) {
          emit(
            BudgetAlertState(
              message: account == null
                  ? 'Sign in to check budget alerts.'
                  : !settings.enabled || !settings.budgets
                  ? 'Budget alerts are off.'
                  : 'Allow device notifications to receive budget alerts.',
            ),
          );
        }
        return;
      }
      if (syncBlocked()) {
        emit(
          const BudgetAlertState(
            message:
                'Sync pending spending changes before checking budget alerts.',
          ),
        );
        return;
      }
      final plan = await source.load();
      if (!current()) return;
      if (plan.ownerId != account.id) throw StateError('Account changed');
      if (!plan.ready) {
        await _device(() async {
          if (current()) await delivery.clear();
        });
        if (current()) {
          emit(
            BudgetAlertState(
              message: plan.reason ?? 'Review your financial profile.',
            ),
          );
        }
        return;
      }
      final count = await _device(() async {
        if (!current() || syncBlocked()) return null;
        await delivery.setOwner(account.id);
        if (!current() || syncBlocked()) return null;
        return delivery.deliver(plan);
      });
      if (current()) {
        emit(
          BudgetAlertState(
            message: count == null
                ? 'Sync pending spending changes before checking budget alerts.'
                : count == 0
                ? 'Checked ${plan.period}. No new budget alerts.'
                : 'Sent a budget alert for $count budget${count == 1 ? '' : 's'} (${plan.period}).',
          ),
        );
      }
    } catch (_) {
      if (current()) {
        emit(
          const BudgetAlertState(
            error: 'Could not check budget alerts. Connect and retry.',
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
