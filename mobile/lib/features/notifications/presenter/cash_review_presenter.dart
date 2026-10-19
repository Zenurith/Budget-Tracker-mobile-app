import '../../../core/model/contracts.dart';
import '../../../core/presentation/presenter.dart';
import '../model/notification_repository.dart';
import '../model/cash_review_repository.dart';

class CashReviewState {
  final bool busy;
  final String message;
  final String? error;
  const CashReviewState({
    this.busy = false,
    this.message = 'Cash-review reminders are off.',
    this.error,
  });
}

class CashReviewPresenter extends Presenter<CashReviewState> {
  final NotificationRepository preferences;
  final CashReviewSource source;
  final CashReviewDelivery delivery;
  final bool Function() syncBlocked;
  Account? _account;
  bool _initialized = false;
  int _generation = 0;
  Future<void> _writes = Future.value();
  CashReviewPresenter(
    this.preferences,
    this.source,
    this.delivery, {
    bool Function()? syncBlocked,
  }) : syncBlocked = syncBlocked ?? (() => false),
       super(const CashReviewState());

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
          const CashReviewState(
            error: 'Could not update cash-review reminders. Retry.',
          ),
        );
      }
    }
  }

  Future<void> endSession() async {
    _account = null;
    ++_generation;
    await _device(() => delivery.setOwner(null));
    emit(
      const CashReviewState(message: 'Sign in to check cash-review reminders.'),
    );
  }

  Future<void> forgetOwner(String owner) =>
      _device(() => delivery.forgetOwner(owner));

  Future<void> refresh() async {
    if (disposed) return;
    final generation = ++_generation;
    final account = _account;
    bool current() => !disposed && generation == _generation;
    emit(
      const CashReviewState(
        busy: true,
        message: 'Checking cash-review reminders…',
      ),
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
          !settings.cashReview ||
          !allowed) {
        await _device(() async {
          if (current()) await delivery.clear();
        });
        if (current()) {
          emit(
            CashReviewState(
              message: account == null
                  ? 'Sign in to check cash-review reminders.'
                  : !settings.enabled || !settings.cashReview
                  ? 'Cash-review reminders are off.'
                  : 'Allow device notifications to receive cash-review reminders.',
            ),
          );
        }
        return;
      }
      if (syncBlocked()) {
        emit(
          const CashReviewState(
            message:
                'Sync pending spending changes before checking cash-review reminders.',
          ),
        );
        return;
      }
      final plan = await source.load();
      if (!current()) return;
      if (plan.ownerId != account.id) throw StateError('Account changed');
      if (!plan.needsReview) {
        await _device(() async {
          if (current()) await delivery.clear();
        });
        if (current()) {
          emit(CashReviewState(message: plan.reason));
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
          CashReviewState(
            message: count == null
                ? 'Sync pending spending changes before checking cash-review reminders.'
                : count == 0
                ? 'Checked ${plan.day}. No new cash-review reminder.'
                : 'Cash-review reminder sent. Open Protected Funding to review.',
          ),
        );
      }
    } catch (_) {
      if (current()) {
        emit(
          const CashReviewState(
            error: 'Could not check cash-review reminders. Connect and retry.',
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
