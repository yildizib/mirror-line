import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/daos/call_event_dao.dart';
import 'package:mirrorline/core/data/models/call_event.dart';

final callListProvider = StateNotifierProvider<CallListNotifier, List<CallEvent>>((ref) {
  return CallListNotifier();
});

class CallListNotifier extends StateNotifier<List<CallEvent>> {
  final CallEventDao _dao = CallEventDao();

  CallListNotifier() : super([]) {
    load();
  }

  Future<void> load() async {
    state = await _dao.getAll();
  }

  /// Upsert: replaces the existing entry if [event.id] is already present
  /// instead of appending a duplicate. Native call events can legitimately
  /// fire more than once for what is logically the same call (see
  /// MirrorLineService's RINGING de-duplication) -- this keeps a stray
  /// repeat from ever showing up as two list entries.
  Future<void> add(CallEvent event) async {
    await _dao.insert(event);
    final exists = state.any((e) => e.id == event.id);
    state = exists ? state.map((e) => e.id == event.id ? event : e).toList() : [...state, event];
  }

  Future<void> updateStatus(String id, String status) async {
    await _dao.updateStatus(id, status);
    state = state.map((e) => e.id == id ? e.copyWith(status: status) : e).toList();
  }

  /// Patches the caller's number/contact name on an already-tracked call
  /// (see RINGING_UPDATE) without treating it as a new event.
  Future<void> updateCallerInfo(String id, {String? number, String? contactName}) async {
    await _dao.updateCallerInfo(id, number: number, contactName: contactName);
    state = state
        .map((e) => e.id == id ? e.copyWith(number: number, contactName: contactName) : e)
        .toList();
  }

  Future<void> remove(String id) async {
    await _dao.delete(id);
    state = state.where((e) => e.id != id).toList();
  }
}
