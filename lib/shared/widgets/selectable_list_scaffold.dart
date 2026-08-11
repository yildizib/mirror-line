import 'package:flutter/material.dart';
import 'package:mirrorline/l10n/app_localizations.dart';

typedef SelectableItemBuilder<T> = Widget Function(
  BuildContext context,
  T item,
  bool isSelecting,
  bool isSelected,
  VoidCallback onTapSelect,
);

typedef OnDeleteSelected<T> = Future<void> Function(BuildContext context, List<T> selected);

class SelectableListScaffold<T> extends StatefulWidget {
  final List<T> items;
  final String Function(T) itemKey;
  final SelectableItemBuilder<T> itemBuilder;
  final OnDeleteSelected<T> onDeleteSelected;
  final String emptyMessage;
  final String selectModeTooltip;
  final String selectedCountLabel;
  final String deleteTooltip;
  final String deleteTitle;
  final String deleteConfirm;
  final String deletedMessage;

  const SelectableListScaffold({
    required this.items,
    required this.itemKey,
    required this.itemBuilder,
    required this.onDeleteSelected,
    required this.emptyMessage,
    required this.selectModeTooltip,
    required this.selectedCountLabel,
    required this.deleteTooltip,
    required this.deleteTitle,
    required this.deleteConfirm,
    required this.deletedMessage,
    super.key,
  });

  @override
  State<SelectableListScaffold<T>> createState() => _SelectableListScaffoldState<T>();
}

class _SelectableListScaffoldState<T> extends State<SelectableListScaffold<T>> {
  bool _selecting = false;
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return Center(
        child: Text(widget.emptyMessage),
      );
    }

    return Scaffold(
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: widget.items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = widget.items[index];
          final key = widget.itemKey(item);
          final isSelected = _selected.contains(key);
          return widget.itemBuilder(
            context,
            item,
            _selecting,
            isSelected,
            () => _toggleSelect(key),
          );
        },
      ),
      appBar: _selecting
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _exitSelectionMode,
              ),
              title: Text(widget.selectedCountLabel),
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete_rounded),
                  tooltip: widget.deleteTooltip,
                  onPressed: _selected.isEmpty ? null : () => _showDeleteDialog(context),
                ),
              ],
            )
          : null,
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton(
              tooltip: widget.selectModeTooltip,
              onPressed: () => setState(() => _selecting = true),
              child: const Icon(Icons.checklist_rounded),
            ),
    );
  }

  void _toggleSelect(String key) {
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        _selected.add(key);
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

  void _showDeleteDialog(BuildContext context) {
    final selectedItems = widget.items
        .where((item) => _selected.contains(widget.itemKey(item)))
        .toList();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.deleteTitle),
        content: Text(widget.deleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppLocalizations.of(context).commonCancel),
          ),
          TextButton(
            onPressed: () async {
              await widget.onDeleteSelected(context, selectedItems);
              if (context.mounted) {
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(widget.deletedMessage)),
                );
              }
              _exitSelectionMode();
            },
            child: Text(
              AppLocalizations.of(context).commonDelete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
