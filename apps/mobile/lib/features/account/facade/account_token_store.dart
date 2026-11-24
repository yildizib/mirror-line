import 'package:mirrorline/features/account/domain/account_models.dart';

abstract interface class AccountTokenStore {
  Future<AccountTokenSet?> read();
  Future<void> write(AccountTokenSet tokens);
  Future<void> clear();
}
