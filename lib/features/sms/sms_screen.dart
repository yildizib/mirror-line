import 'package:flutter/material.dart';
import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/features/sms/sms_facade.dart';
import 'package:mirrorline/features/sms/sms_thread_provider.dart';
import 'package:mirrorline/features/sms/sms_thread_screen.dart';
import 'package:mirrorline/features/sms/widgets/sms_thread_tile.dart';
import 'package:mirrorline/shared/widgets/empty_state.dart';
import 'package:mirrorline/shared/widgets/selectable_list_scaffold.dart';

class SmsScreen extends ConsumerWidget {
  const SmsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threadsState = ref.watch(smsThreadsPaginatedProvider);
    final threads = threadsState.items;
    final l = AppLocalizations.of(context);

    return SelectableListScaffold(
      items: threads,
      itemKey: (thread) => thread.address,
      dateHeaderOf: (thread) => thread.lastMessage.timestamp,
      onLoadMore: ref.read(smsThreadsPaginatedProvider.notifier).loadMore,
      isLoadingMore: threadsState.isLoading,
      hasReachedEnd: threadsState.hasReachedEnd,
      itemBuilder: (context, thread, isSelecting, isSelected, onTapSelect) =>
          SmsThreadTile(
            thread: thread,
            isSelecting: isSelecting,
            isSelected: isSelected,
            onTapSelect: onTapSelect,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SmsThreadScreen(address: thread.address),
              ),
            ),
          ),
      emptyMessage: l.smsEmpty,
      emptyBuilder: (context) =>
          EmptyState(icon: Icons.message_rounded, message: l.smsEmpty),
      selectModeTooltip: l.smsSelectMode,
      selectedCountLabel: (count) => l.smsSelectedCount(count),
      deleteTooltip: l.commonDeleteSelected,
      deleteTitle: l.smsDeleteSelected,
      deleteConfirm: (selected) => l.smsDeleteConfirmBody(selected.length),
      deletedMessage: l.smsDeleted,
      onDeleteSelected: (context, selected) async {
        final notifier = ref.read(smsFacadeProvider.notifier);
        for (final thread in selected) {
          await notifier.removeThread(thread.address);
        }
      },
    );
  }
}
