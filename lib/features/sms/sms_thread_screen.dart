import 'package:flutter/material.dart';
import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/connection/connection_facade.dart';
import 'package:mirrorline/features/sms/sms_facade.dart';
import 'package:mirrorline/features/sms/sms_thread_provider.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToBottom(animate: false),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
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
    final threadState = ref.watch(
      smsThreadDetailPaginatedProvider(widget.address),
    );
    final messages = threadState.items;

    if (messages.isEmpty && !threadState.isLoading) {
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
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollEndNotification &&
                    !threadState.isLoading &&
                    !threadState.hasReachedEnd) {
                  final metrics = notification.metrics;
                  if (metrics.pixels <= metrics.minScrollExtent + 500) {
                    ref
                        .read(
                          smsThreadDetailPaginatedProvider(
                            widget.address,
                          ).notifier,
                        )
                        .loadOlder();
                  }
                }
                return false;
              },
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  if (threadState.isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  ...buildDateGroupedItems(
                    context: context,
                    items: messages,
                    timestampOf: (message) => message.timestamp,
                    itemBuilder: (context, message) =>
                        SmsBubble(message: message),
                  ),
                ],
              ),
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
