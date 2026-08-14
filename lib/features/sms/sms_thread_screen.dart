import 'package:flutter/material.dart';
import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/connection/connection_facade.dart';
import 'package:mirrorline/features/sms/sms_facade.dart';
import 'package:mirrorline/features/sms/widgets/sms_bubble.dart';
import 'package:mirrorline/shared/widgets/date_grouped_list.dart';

/// Full conversation with one address: every message exchanged with them,
/// oldest first, chat-bubble style, with the reply composer inline at the
/// bottom -- makes it visually obvious a reply belongs to this thread,
/// unlike the old flat global list + popup dialog.
class SmsThreadScreen extends ConsumerStatefulWidget {
  final String address;

  const SmsThreadScreen({required this.address, super.key});

  @override
  ConsumerState<SmsThreadScreen> createState() => _SmsThreadScreenState();
}

class _SmsThreadScreenState extends ConsumerState<SmsThreadScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  static const _pageSize = 25;
  int _visibleFromBottom = _pageSize;
  bool _isLoadingOlder = false;
  double? _prevMaxScroll;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScrollChanged);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToBottom(animate: false),
    );
  }

 void _onScrollChanged() {
 if (!_scrollController.hasClients) return;
 final pos = _scrollController.position;
 if (pos.pixels <= 200) {
 final messages = ref
 .read(smsFacadeProvider)
 .where((m) => m.address == widget.address)
 .toList();
 _maybeLoadOlder(messages);
 }
 }

 @override
 void didUpdateWidget(covariant SmsThreadScreen oldWidget) {
 super.didUpdateWidget(oldWidget);
 final messages = ref
 .read(smsFacadeProvider)
 .where((m) => m.address == widget.address)
 .toList();
 if (_visibleFromBottom > messages.length) {
 _visibleFromBottom = messages.length;
 }
 }

  @override
  void dispose() {
    _scrollController.removeListener(_onScrollChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeLoadOlder(List messages) {
    if (!_scrollController.hasClients || _isLoadingOlder) return;
    if (_visibleFromBottom >= messages.length) return;
    final pos = _scrollController.position;
    if (pos.pixels <= 200) {
      _loadOlder(messages);
    }
  }

  void _loadOlder(List messages) {
    if (_isLoadingOlder || _visibleFromBottom >= messages.length) return;
    _prevMaxScroll = _scrollController.position.maxScrollExtent;
    setState(() => _isLoadingOlder = true);
    Future.microtask(() {
      if (!mounted) return;
      setState(() {
        _visibleFromBottom = (_visibleFromBottom + _pageSize).clamp(0, messages.length);
        _isLoadingOlder = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients || _prevMaxScroll == null) return;
        final newMax = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(newMax - _prevMaxScroll!);
        _prevMaxScroll = null;
      });
    });
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  void _send(SmsMessage lastMessage) {
    if (!ref.read(connectionFacadeProvider)) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final reply = SmsMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      threadId: lastMessage.threadId,
      address: widget.address,
      contactName: lastMessage.contactName,
      body: text,
      encrypted: '',
      direction: 'outgoing',
      status: 'pending',
      timestamp: DateTime.now(),
      createdAt: DateTime.now(),
    );
    ref.read(smsFacadeProvider.notifier).add(reply);
    ref
        .read(connectionFacadeProvider.notifier)
        .sendReplySms(
          widget.address,
          text,
          id: reply.id,
          contactName: lastMessage.contactName,
          threadId: lastMessage.threadId,
        );

    _controller.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(connectionFacadeProvider);
    final messages =
        ref
            .watch(smsFacadeProvider)
            .where((m) => m.address == widget.address)
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (messages.isEmpty) {
      // Every message in this thread got removed elsewhere; nothing left
      // to show, so back out instead of rendering an empty conversation.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final displayName = messages.reversed
        .map((m) => m.contactName)
        .firstWhere((name) => name.isNotEmpty, orElse: () => widget.address);

    return Scaffold(
      appBar: AppBar(title: Text(displayName)),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                if (_isLoadingOlder || _visibleFromBottom < messages.length)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                ...buildDateGroupedItems(
                  context: context,
                  items: messages.length > _visibleFromBottom
                      ? messages.sublist(messages.length - _visibleFromBottom)
                      : messages,
                  timestampOf: (message) => message.timestamp,
                  itemBuilder: (context, message) =>
                      SmsBubble(message: message),
                ),
              ],
            ),
          ),
          _ComposeBar(
            controller: _controller,
            onSend: () => _send(messages.last),
            enabled: connected,
          ),
        ],
      ),
    );
  }
}

class _ComposeBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;

  const _ComposeBar({
    required this.controller,
    required this.onSend,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: enabled ? (_) => onSend() : null,
                decoration: InputDecoration(
                  hintText: enabled ? l.smsReplyHint : l.connStatusDisconnected,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filled(
              icon: const Icon(Icons.send_rounded),
              onPressed: enabled ? onSend : null,
              tooltip: enabled ? null : l.connStatusDisconnected,
            ),
          ],
        ),
      ),
    );
  }
}
