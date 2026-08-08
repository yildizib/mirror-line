import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/calls/call_group_provider.dart';
import 'package:mirrorline/features/calls/call_list_provider.dart';

/// Shows every individual call in a [CallGroup], each with its own
/// timestamp and status -- opened by tapping a grouped row on the calls
/// list when a caller has called more than once.
///
/// Takes the group's key (not the CallGroup itself) and re-derives the
/// live group from [callGroupsProvider] on every build, so deletes on
/// this screen are reflected immediately instead of showing a stale
/// snapshot until the screen is reopened.
class CallGroupDetailScreen extends ConsumerStatefulWidget {
  final String groupKey;

  const CallGroupDetailScreen({required this.groupKey, super.key});

  @override
  ConsumerState<CallGroupDetailScreen> createState() => _CallGroupDetailScreenState();
}

class _CallGroupDetailScreenState extends ConsumerState<CallGroupDetailScreen> {
  bool _selecting = false;
  final Set<String> _selected = {};

  CallGroup? get _group {
    final groups = ref.watch(callGroupsProvider);
    for (final g in groups) {
      if (g.key == widget.groupKey) return g;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final group = _group;

    // The group can disappear entirely if every call in it was deleted --
    // pop back to the calls list instead of rendering an empty screen.
    if (group == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.maybePop(context);
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      appBar: AppBar(
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _exitSelectionMode,
              )
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(group.displayName, style: const TextStyle(fontSize: 17)),
            Text(
              '${group.count} arama',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: _selecting
            ? [
                IconButton(
                  icon: const Icon(Icons.delete_rounded),
                  tooltip: 'Seçilenleri sil',
                  onPressed: _selected.isEmpty ? null : () => _deleteSelected(context),
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.checklist_rounded),
                  tooltip: 'Seç',
                  onPressed: () => setState(() => _selecting = true),
                ),
              ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: group.calls.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) => _CallDetailTile(
          event: group.calls[index],
          isSelecting: _selecting,
          isSelected: _selected.contains(group.calls[index].id),
          onTapSelect: () => _toggleSelect(group.calls[index].id),
        ),
      ),
    );
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
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
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Seçilen aramaları sil'),
        content: Text('${_selected.length} arama kalıcı olarak silinecek.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(callListProvider.notifier).removeMany(_selected.toList());
              if (context.mounted) {
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Seçilen aramalar silindi')),
                );
              }
              _exitSelectionMode();
            },
            child: Text('Sil', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }
}

class _CallDetailTile extends StatelessWidget {
  final CallEvent event;
  final bool isSelecting;
  final bool isSelected;
  final VoidCallback? onTapSelect;

  const _CallDetailTile({
    required this.event,
    this.isSelecting = false,
    this.isSelected = false,
    this.onTapSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColors = theme.status;

    final statusColor = switch (event.status) {
      'answered' => statusColors.success,
      'missed' => statusColors.warning,
      'rejected' => colorScheme.error,
      'ringing' => statusColors.success,
      _ => colorScheme.onSurfaceVariant,
    };

    final tile = Card(
      color: isSelected ? colorScheme.primaryContainer.withValues(alpha: 0.4) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              event.direction == 'incoming' ? Icons.call_received_rounded : Icons.call_made_rounded,
              color: statusColor,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatFullTime(event.timestamp),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    event.statusLabel,
                    style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (isSelecting)
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: isSelected ? colorScheme.primary : colorScheme.outline,
              ),
          ],
        ),
      ),
    );

    if (!isSelecting) return tile;
    return GestureDetector(
      onTap: onTapSelect,
      behavior: HitTestBehavior.opaque,
      child: tile,
    );
  }

  String _formatFullTime(DateTime time) {
    final now = DateTime.now();
    final sameDay = time.year == now.year && time.month == now.month && time.day == now.day;
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    if (sameDay) return 'Bugün $hh:$mm';
    return '${time.day.toString().padLeft(2, '0')}.${time.month.toString().padLeft(2, '0')}.$time.year $hh:$mm';
  }
}