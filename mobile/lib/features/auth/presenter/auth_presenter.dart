import 'dart:convert';
import '../../../core/model/contracts.dart';
import '../../../core/presentation/presenter.dart';

class AuthState {
  final Account? account;
  final bool starting, busy;
  final String? error;
  const AuthState({
    this.account,
    this.starting = false,
    this.busy = false,
    this.error,
  });
}

class AuthPresenter extends Presenter<AuthState> {
  final AuthRepository _repository;
  bool _initialized = false;
  AuthPresenter(this._repository) : super(const AuthState(starting: true));
  Future<void> initialize() async {
    if (_initialized || disposed) return;
    _initialized = true;
    try {
      emit(AuthState(account: await _repository.restore()));
    } catch (error) {
      emit(AuthState(error: error.toString()));
    }
  }

  String? validateEmail(String? value) => InputRules.email(value);
  String? validateName(String? value) => InputRules.name(value);
  String? validatePassword(String? value, bool register) =>
      InputRules.password(value, register: register);
  void clearError() => emit(AuthState(account: state.account));
  Future<bool> updateProfile(String name) async {
    if (state.busy || state.account == null || disposed) return false;
    final account = state.account;
    final error =
        validateName(name) ??
        (name.trim().length > 80 ? 'Use at most 80 characters' : null);
    if (error != null) {
      emit(AuthState(account: account, error: error));
      return false;
    }
    emit(AuthState(account: account, busy: true));
    try {
      final updated = await _repository.updateProfile(name.trim());
      emit(AuthState(account: updated));
      return !disposed;
    } catch (error) {
      emit(AuthState(account: account, error: error.toString()));
      return false;
    }
  }

  Future<bool> exportData(ExportDestination destination) async {
    if (state.busy || state.account == null || disposed) return false;
    final account = state.account;
    emit(AuthState(account: account, busy: true));
    try {
      final data = await _repository.exportData();
      if (disposed) return false;
      final saved = await destination.save(
        const JsonEncoder.withIndent('  ').convert(data),
      );
      emit(AuthState(account: account));
      return saved && !disposed;
    } catch (error) {
      emit(AuthState(account: account, error: error.toString()));
      return false;
    }
  }

  Future<bool> authenticate(AuthInput input) async {
    if (state.busy || state.starting || disposed) return false;
    final currencyError = InputRules.currencies.contains(input.currency)
        ? null
        : 'Choose your currency';
    final error = input.mode == 'demo'
        ? currencyError
        : validateEmail(input.email) ??
              validatePassword(input.password, input.mode == 'register') ??
              (input.mode == 'register'
                  ? validateName(input.name) ?? currencyError
                  : null);
    if (error != null) {
      emit(AuthState(error: error));
      return false;
    }
    emit(const AuthState(busy: true));
    try {
      final user = await _repository.authenticate(input);
      emit(AuthState(account: user));
      return !disposed;
    } catch (error) {
      emit(AuthState(error: error.toString()));
      return false;
    }
  }

  Future<bool> logout() async {
    if (state.busy || disposed) return false;
    emit(AuthState(account: state.account, busy: true));
    try {
      await _repository.logout();
      emit(const AuthState());
      return !disposed;
    } catch (error) {
      emit(AuthState(account: state.account, error: error.toString()));
      return false;
    }
  }

  Future<bool> deleteAccount() async {
    if (state.busy || disposed) return false;
    emit(AuthState(account: state.account, busy: true));
    try {
      await _repository.deleteAccount();
      emit(const AuthState());
      return !disposed;
    } catch (error) {
      emit(AuthState(account: state.account, error: error.toString()));
      return false;
    }
  }
}
