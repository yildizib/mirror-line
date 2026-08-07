import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/daos/call_event_dao.dart';
import '../data/models/call_event.dart';

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

  Future<void> add(CallEvent event) async {
    await _dao.insert(event);
    state = [...state, event];
  }

  Future<void> updateStatus(String id, String status) async {
    await _dao.updateStatus(id, status);
    state = state.map((e) => e.id == id ? e.copyWith(status: status) : e).toList();
  }

  Future<void> remove(String id) async {
    await _dao.delete(id);
    state = state.where((e) => e.id != id).toList();
  }
}
