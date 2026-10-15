import '../../../core/presentation/presenter.dart';
import '../model/notification_repository.dart';

class NotificationState {
  final NotificationPreferences preferences;
  final NotificationPermission permission;
  final bool loaded, saving, checking;
  final String? error, permissionError;
  const NotificationState({
    this.preferences = const NotificationPreferences(),
    this.permission = NotificationPermission.unknown,
    this.loaded = false,
    this.saving = false,
    this.checking = false,
    this.error,
    this.permissionError,
  });

  NotificationState copy({
    NotificationPreferences? preferences,
    NotificationPermission? permission,
    bool? loaded,
    bool? saving,
    bool? checking,
    String? error,
    String? permissionError,
    bool clearError = false,
    bool clearPermissionError = false,
  }) => NotificationState(
    preferences: preferences ?? this.preferences,
    permission: permission ?? this.permission,
    loaded: loaded ?? this.loaded,
    saving: saving ?? this.saving,
    checking: checking ?? this.checking,
    error: clearError ? null : error ?? this.error,
    permissionError: clearPermissionError
        ? null
        : permissionError ?? this.permissionError,
  );
}

class NotificationPresenter extends Presenter<NotificationState> {
  final NotificationRepository repository;
  Future<void> Function(bool invalidate)? onChanged;
  bool _loading = false;
  NotificationPresenter(this.repository) : super(const NotificationState());

  Future<void> load() async {
    if (_loading || state.saving || disposed) return;
    _loading = true;
    emit(state.copy(loaded: false, clearError: true));
    try {
      final preferences = await repository.load();
      if (!disposed) emit(state.copy(preferences: preferences, loaded: true));
    } catch (_) {
      emit(
        state.copy(
          error: 'Could not load notification preferences. Please retry.',
        ),
      );
    } finally {
      _loading = false;
    }
    await refreshPermission();
  }

  Future<void> save(NotificationPreferences preferences) async {
    if (!state.loaded || state.saving || disposed) return;
    if (!const [0, 1, 3, 7].contains(preferences.billLeadDays)) return;
    emit(state.copy(saving: true, clearError: true));
    try {
      await repository.save(preferences);
      if (!disposed && onChanged != null) await onChanged!(true);
      if (!disposed) emit(state.copy(preferences: preferences, saving: false));
    } catch (_) {
      emit(
        state.copy(
          saving: false,
          error:
              'Could not save your changes. Your previous preferences are still selected.',
        ),
      );
    }
  }

  Future<void> refreshPermission() => _permission(repository.permission);
  Future<void> requestPermission() async {
    if (!const [
      NotificationPermission.notDetermined,
      NotificationPermission.denied,
    ].contains(state.permission)) {
      return;
    }
    await _permission(repository.requestPermission);
  }

  Future<void> _permission(
    Future<NotificationPermission> Function() action,
  ) async {
    if (state.checking || disposed) return;
    emit(state.copy(checking: true, clearPermissionError: true));
    try {
      final permission = await action();
      if (!disposed && onChanged != null) await onChanged!(false);
      if (!disposed) emit(state.copy(permission: permission, checking: false));
    } catch (_) {
      emit(
        state.copy(
          permission: NotificationPermission.unknown,
          checking: false,
          permissionError:
              'Could not check notification permission. Please retry.',
        ),
      );
    }
  }

  Future<void> openSettings() async {
    if (state.checking ||
        disposed ||
        state.permission == NotificationPermission.unsupported) {
      return;
    }
    emit(state.copy(checking: true, clearPermissionError: true));
    try {
      if (!await repository.openSettings()) {
        throw StateError('Settings unavailable');
      }
      if (!disposed) emit(state.copy(checking: false));
      await refreshPermission();
    } catch (_) {
      emit(
        state.copy(
          checking: false,
          permissionError:
              'Could not open system settings. Open your device Settings and select Pocketwise notifications.',
        ),
      );
    }
  }
}
