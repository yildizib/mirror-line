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

  /// Upsert: replaces the existing entry if [message.id] is already
  /// present instead of appending a duplicate (see CallListNotifier.add
  /// for why this matters -- native events can repeat for what is
  /// logically the same message).
  Future<void> add(SmsMessage message) async {
    await _dao.insert(message);
    final exists = state.any((m) => m.id == message.id);
    state = exists
        ? state.map((m) => m.id == message.id ? message : m).toList()
        : [message, ...state];
  }

  Future<void> updateStatus(String id, String status) async {
    await _dao.updateStatus(id, status);
    state = state.map((m) => m.id == id ? m.copyWith(status: status) : m).toList();
  }

  Future<void> remove(String id) async {
    await _dao.delete(id);
    state = state.where((m) => m.id != id).toList();
  }

  /// Permanently deletes every message in [ids] (used by multi-select clear).
  Future<void> removeMany(Iterable<String> ids) async {
    final idSet = ids.toSet();
    for (final id in idSet) {
      await _dao.delete(id);
    }
    state = state.where((m) => !idSet.contains(m.id)).toList();
  }

  /// Deletes every message exchanged with [address] -- i.e. an entire
  /// thread, used from the SMS list's per-thread swipe-to-delete.
  Future<void> removeThread(String address) async {
    final toRemove = state.where((m) => m.address == address).map((m) => m.id).toSet();
    if (toRemove.isEmpty) return;
    for (final id in toRemove) {
      await _dao.delete(id);
    }
    state = state.where((m) => !toRemove.contains(m.id)).toList();
  }

  /// Permanently deletes all messages (used by "clear all" / device reset).
  Future<void> removeAll() async {
    await _dao.deleteAll();
    state = [];
  }
}
