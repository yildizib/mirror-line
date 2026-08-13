import 'package:flutter/material.dart';
import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/connection/connection_facade.dart';
import 'package:mirrorline/features/settings/diagnostics_facade.dart';
import 'package:mirrorline/shared/widgets/empty_state.dart';

class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final isConnected = ref.watch(connectionFacadeProvider);
    final records = ref.watch(diagnosticsFacadeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.runTestsTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.bug_report_rounded),
                  label: Text(l.runTestsButton),
                  onPressed: isConnected
                      ? () => ref
                            .read(diagnosticsFacadeProvider.notifier)
                            .runTests()
                      : null,
                ),
                if (!isConnected) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l.runTestsNotConnected,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: records.isEmpty
                ? EmptyState(
                    icon: Icons.bug_report_outlined,
                    message: l.runTestsEmpty,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    itemCount: records.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) =>
                        _TestRunTile(record: records[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TestRunTile extends StatelessWidget {
  final TestRunRecord record;

  const _TestRunTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColors = theme.status;
    final l = AppLocalizations.of(context);

    final IconData icon;
    final String label;
    switch (record.type) {
      case TestEventType.call:
        icon = Icons.call_rounded;
        label = l.runTestsCallType;
      case TestEventType.sms:
        icon = Icons.message_rounded;
        label = l.runTestsSmsType;
      case TestEventType.notification:
        icon = Icons.notifications_rounded;
        label = l.runTestsNotificationType;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: colorScheme.primary, size: 20),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(record.timestamp),
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              record.delivered ? l.runTestsSent : l.runTestsQueued,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: record.delivered
                    ? statusColors.success
                    : statusColors.warning,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    final ss = time.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
}
