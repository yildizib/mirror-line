import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/daos/sms_message_dao.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';

final smsListProvider = StateNotifierProvider<SmsListNotifier, List<SmsMessage>>((ref) {
  return SmsListNotifier();
});

class SmsListNotifier extends StateNotifier<List<SmsMessage>> {
  final SmsMessageDao _dao = SmsMessageDao();

  SmsListNotifier() : super([]) {
    load();
  }

  Future<void> load() async {
    state = await _dao.getAll();
  }

  Future<void> add(SmsMessage message) async {
    await _dao.insert(message);
    state = [message, ...state];
  }

  Future<void> updateStatus(String id, String status) async {
    await _dao.updateStatus(id, status);
    state = state.map((m) => m.id == id ? m.copyWith(status: status) : m).toList();
  }

  Future<void> remove(String id) async {
    await _dao.delete(id);
    state = state.where((m) => m.id != id).toList();
  }
}
