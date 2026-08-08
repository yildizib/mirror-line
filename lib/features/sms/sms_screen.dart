import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/sms/sms_thread_provider.dart';
import 'package:mirrorline/features/sms/sms_thread_screen.dart';
import 'package:mirrorline/features/sms/widgets/sms_thread_tile.dart';
import 'package:mirrorline/shared/widgets/empty_state.dart';

class SmsScreen extends ConsumerWidget {
  const SmsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threads = ref.watch(smsThreadsProvider);

    if (threads.isEmpty) {
      return const EmptyState(
        icon: Icons.message_rounded,
        message: 'Henüz mesaj yok',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: threads.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final thread = threads[index];
        return SmsThreadTile(
          thread: thread,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SmsThreadScreen(address: thread.address)),
          ),
        );
      },
    );
  }
}
