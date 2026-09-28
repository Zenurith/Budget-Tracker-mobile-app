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
  Future<bool> authenticate(AuthInput input) async {
    if (state.busy || state.starting || disposed) return false;
    final error = input.mode == 'demo'
        ? null
        : validateEmail(input.email) ??
              validatePassword(input.password, input.mode == 'register') ??
              (input.mode == 'register'
                  ? validateName(input.name) ??
                        (InputRules.currencies.contains(input.currency)
                            ? null
                            : 'Choose your currency')
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
