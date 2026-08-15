import 'package:flutter/material.dart';
import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:mirrorline/shared/widgets/date_header.dart';

typedef SelectableItemBuilder<T> =
    Widget Function(
      BuildContext context,
      T item,
      bool isSelecting,
      bool isSelected,
      VoidCallback onTapSelect,
    );

typedef OnDeleteSelected<T> =
    Future<void> Function(BuildContext context, List<T> selected);

class SelectableListScaffold<T> extends StatefulWidget {
  final List<T> items;
  final String Function(T) itemKey;
  final SelectableItemBuilder<T> itemBuilder;
  final OnDeleteSelected<T> onDeleteSelected;
  final String emptyMessage;
  final String selectModeTooltip;
  final String Function(int count) selectedCountLabel;
  final String deleteTooltip;
  final String deleteTitle;

  /// Builds the confirm-dialog body from the currently-selected items --
  /// a builder (not a plain String) because callers may need more than a
  /// live count: e.g. calls_screen.dart's confirm body needs both the
  /// selected-group count and the flattened call count, which only the
  /// caller can derive from the actual selected items.
  final String Function(List<T> selected) deleteConfirm;
  final String deletedMessage;

  /// Overrides the bare `Center(Text(emptyMessage))` fallback -- pass a
  /// screen's existing icon-based empty-state widget to preserve it.
  final Widget Function(BuildContext context)? emptyBuilder;

  /// When true, the AppBar is always shown (never null) and selection mode
  /// is entered via an AppBar action instead of a FloatingActionButton --
  /// for screens whose non-selecting AppBar already carries context (e.g.
  /// a contact name + count) that a FAB-only entry point would hide.
  /// Requires [nonSelectingTitle].
  final bool useAppBarEntryPoint;

  /// Title shown in the AppBar while not selecting, when
  /// [useAppBarEntryPoint] is true. Ignored otherwise.
  final Widget? nonSelectingTitle;

  /// When set, a [DateHeader] is inserted before any item whose calendar
  /// day (per this timestamp) differs from the previous item's -- for
  /// screens showing a chronological history (call/notification detail
  /// lists). [items] must already be sorted by this timestamp, ascending
  /// or descending; this only inserts headers, it never re-sorts.
  final DateTime Function(T item)? dateHeaderOf;

  final Future<void> Function()? onLoadMore;
  final bool isLoadingMore;
  final bool hasReachedEnd;

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
    this.emptyBuilder,
    this.useAppBarEntryPoint = false,
    this.nonSelectingTitle,
    this.dateHeaderOf,
    this.onLoadMore,
    this.isLoadingMore = false,
    this.hasReachedEnd = false,
    super.key,
  }) : assert(
          !useAppBarEntryPoint || nonSelectingTitle != null,
          'nonSelectingTitle is required when useAppBarEntryPoint is true',
        );

  @override
  State<SelectableListScaffold<T>> createState() =>
      _SelectableListScaffoldState<T>();
}

class _SelectableListScaffoldState<T>
    extends State<SelectableListScaffold<T>> {
  bool _selecting = false;
  final Set<String> _selected = {};
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (widget.onLoadMore == null ||
        widget.isLoadingMore ||
        widget.hasReachedEnd) {
      return;
    }
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 500) {
      widget.onLoadMore!();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return widget.emptyBuilder?.call(context) ??
          Center(child: Text(widget.emptyMessage));
    }

    return Scaffold(
      body: _buildList(context),
      appBar: _buildAppBar(),
      floatingActionButton: (_selecting || widget.useAppBarEntryPoint)
          ? null
          : FloatingActionButton(
              heroTag: null,
              tooltip: widget.selectModeTooltip,
              onPressed: () => setState(() => _selecting = true),
              child: const Icon(Icons.checklist_rounded),
            ),
    );
  }

  Widget _buildList(BuildContext context) {
    final dateHeaderOf = widget.dateHeaderOf;
    if (dateHeaderOf == null) {
      return ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: widget.items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _buildItem(context, widget.items[index]),
      );
    }

    final children = <Widget>[];
    DateTime? previousDay;
    for (final item in widget.items) {
      final timestamp = dateHeaderOf(item);
      final day = DateTime(timestamp.year, timestamp.month, timestamp.day);
      if (previousDay == null || day != previousDay) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 8));
        children.add(DateHeader(date: day));
        previousDay = day;
      }
      children.add(const SizedBox(height: 8));
      children.add(_buildItem(context, item));
    }
    if (widget.isLoadingMore) {
      children.add(const SizedBox(height: 16));
      children.add(const _LoadingFooter());
    }
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      children: children,
    );
  }

  Widget _buildItem(BuildContext context, T item) {
    final key = widget.itemKey(item);
    final isSelected = _selected.contains(key);
    return widget.itemBuilder(
      context,
      item,
      _selecting,
      isSelected,
      () => _toggleSelect(key),
    );
  }

  PreferredSizeWidget? _buildAppBar() {
    // AppBar-entry-point screens keep the same persistent title (e.g. a
    // contact name + call count) in both modes -- only the leading/actions
    // change. FAB-entry-point screens swap the title to the live selected
    // count while selecting, and have no AppBar at all otherwise.
    if (widget.useAppBarEntryPoint) {
      return AppBar(
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _exitSelectionMode,
              )
            : null,
        title: widget.nonSelectingTitle,
        actions: [
          if (_selecting)
            IconButton(
              icon: const Icon(Icons.delete_rounded),
              tooltip: widget.deleteTooltip,
              onPressed: _selected.isEmpty
                  ? null
                  : () => _showDeleteDialog(context),
            )
          else
            IconButton(
              icon: const Icon(Icons.checklist_rounded),
              tooltip: widget.selectModeTooltip,
              onPressed: () => setState(() => _selecting = true),
            ),
        ],
      );
    }
    if (_selecting) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _exitSelectionMode,
        ),
        title: Text(widget.selectedCountLabel(_selected.length)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_rounded),
            tooltip: widget.deleteTooltip,
            onPressed: _selected.isEmpty
                ? null
                : () => _showDeleteDialog(context),
          ),
        ],
      );
    }
    return null;
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
        content: Text(widget.deleteConfirm(selectedItems)),
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
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(widget.deletedMessage)));
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

class _LoadingFooter extends StatelessWidget {
  const _LoadingFooter();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
