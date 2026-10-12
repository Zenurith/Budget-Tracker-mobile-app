import '../../../core/model/contracts.dart';
import '../../../core/presentation/presenter.dart';
import '../model/recovery_repository.dart';

class RecoveryState {
  final bool busy, sent, reset;
  final String? error;
  const RecoveryState({
    this.busy = false,
    this.sent = false,
    this.reset = false,
    this.error,
  });
}

class RecoveryPresenter extends Presenter<RecoveryState> {
  final RecoveryRepository repository;
  RecoveryPresenter(this.repository) : super(const RecoveryState());
  void clear() {
    if (!state.busy) emit(const RecoveryState());
  }

  Future<bool> request(String email) async {
    if (disposed || state.busy) return false;
    final error = InputRules.email(email);
    if (error != null) {
      emit(RecoveryState(error: error));
      return false;
    }
    emit(const RecoveryState(busy: true));
    try {
      await repository.requestReset(email.trim());
      emit(const RecoveryState(sent: true));
      return !disposed;
    } catch (error) {
      emit(RecoveryState(error: error.toString()));
      return false;
    }
  }

  Future<bool> reset(String token, String password, String confirm) async {
    if (disposed || state.busy) return false;
    final error =
        InputRules.password(password, register: true) ??
        (password.length > 128 ? 'Use at most 128 characters' : null) ??
        (password != confirm ? 'Passwords do not match' : null) ??
        (token.trim().length < 32
            ? 'Paste the reset code from your email'
            : null);
    if (error != null) {
      emit(RecoveryState(sent: state.sent, error: error));
      return false;
    }
    emit(RecoveryState(busy: true, sent: state.sent));
    try {
      await repository.resetPassword(token.trim(), password);
      emit(const RecoveryState(reset: true));
      return !disposed;
    } catch (error) {
      emit(RecoveryState(sent: state.sent, error: error.toString()));
      return false;
    }
  }
}
