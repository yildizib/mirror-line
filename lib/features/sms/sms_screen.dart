import 'package:flutter/material.dart';
import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/sms/sms_list_provider.dart';
import 'package:mirrorline/features/sms/sms_thread_provider.dart';
import 'package:mirrorline/features/sms/sms_thread_screen.dart';
import 'package:mirrorline/features/sms/widgets/sms_thread_tile.dart';
import 'package:mirrorline/shared/widgets/empty_state.dart';

class SmsScreen extends ConsumerStatefulWidget {
  const SmsScreen({super.key});

  @override
  ConsumerState<SmsScreen> createState() => _SmsScreenState();
}

class _SmsScreenState extends ConsumerState<SmsScreen> {
  bool _selecting = false;
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final threads = ref.watch(smsThreadsProvider);
    final l = AppLocalizations.of(context);

    if (threads.isEmpty) {
      return EmptyState(
        icon: Icons.message_rounded,
        message: l.smsEmpty,
      );
    }

    return Scaffold(
      body: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: threads.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final thread = threads[index];
          final isSelected = _selected.contains(thread.address);
          return SmsThreadTile(
            thread: thread,
            isSelecting: _selecting,
            isSelected: isSelected,
            onTapSelect: () => _toggleSelect(thread.address),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SmsThreadScreen(address: thread.address)),
            ),
          );
        },
      ),
      appBar: _selecting
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _exitSelectionMode,
              ),
              title: Text(l.smsSelectedCount(_selected.length)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete_rounded),
                  tooltip: l.commonDeleteSelected,
                  onPressed: _selected.isEmpty ? null : () => _deleteSelected(context),
                ),
              ],
            )
          : null,
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton(
              tooltip: l.smsSelectMode,
              onPressed: () => setState(() => _selecting = true),
              child: const Icon(Icons.checklist_rounded),
            ),
    );
  }

  void _toggleSelect(String address) {
    setState(() {
      if (_selected.contains(address)) {
        _selected.remove(address);
      } else {
        _selected.add(address);
      }
      if (_selected.isEmpty) _selecting = false;
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _deleteSelected(BuildContext context) {
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.smsDeleteSelected),
        content: Text(l.smsDeleteConfirmBody(_selected.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () async {
              final notifier = ref.read(smsListProvider.notifier);
              for (final address in _selected.toList()) {
                await notifier.removeThread(address);
              }
              if (context.mounted) {
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l.smsDeleted)),
                );
              }
              _exitSelectionMode();
            },
            child: Text(l.commonDelete, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }
}