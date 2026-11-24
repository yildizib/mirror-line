enum AccountFailureCode {
  validation,
  invalidCredentials,
  emailVerificationRequired,
  sessionExpired,
  deviceRevoked,
  deviceNotFound,
  deviceLimitReached,
  forbidden,
  selfRevokeBlocked,
  unavailable,
  network,
  malformedResponse,
}

class AccountFailure {
  const AccountFailure(this.code);

  final AccountFailureCode code;
}

sealed class AccountResult<T> {
  const AccountResult();
}

class AccountSuccess<T> extends AccountResult<T> {
  const AccountSuccess(this.value);

  final T value;
}

class AccountFailureResult<T> extends AccountResult<T> {
  const AccountFailureResult(this.failure);

  final AccountFailure failure;
}
