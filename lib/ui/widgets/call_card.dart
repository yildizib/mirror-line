import 'package:flutter/material.dart';

import '../../data/models/call_event.dart';

class CallCard extends StatelessWidget {
  final CallEvent event;
  final VoidCallback onReject;

  const CallCard({
    required this.event,
    required this.onReject,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(Icons.call, color: theme.colorScheme.primary),
        ),
        title: Text(
          event.number,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(_formatTime(event.timestamp)),
        trailing: IconButton(
          icon: const Icon(Icons.block, color: Colors.redAccent),
          onPressed: onReject,
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
