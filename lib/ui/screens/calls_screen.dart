import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/call_event.dart';
import '../../providers/call_list_provider.dart';
import '../../providers/connection_provider.dart';
import '../widgets/call_card.dart';
import '../widgets/empty_state.dart';

class CallsScreen extends ConsumerWidget {
  const CallsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calls = ref.watch(callListProvider);

    if (calls.isEmpty) {
      return const EmptyState(
        icon: Icons.call_end,
        message: 'Henüz gelen arama yok',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: calls.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final call = calls[index];
        return CallCard(
          event: call,
          onReject: () => _handleReject(context, ref, call),
        );
      },
    );
  }

  void _handleReject(BuildContext context, WidgetRef ref, CallEvent call) {
    ref.read(callListProvider.notifier).updateStatus(call.id, 'rejected');

    // Send reject command to peer device via socket
    ref.read(connectionProvider.notifier).sendCallRejected(call.id);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Arama reddedildi')),
    );
  }
}
