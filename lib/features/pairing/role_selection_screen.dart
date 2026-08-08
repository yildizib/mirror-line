import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/services/permission_service.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/connection/connection_provider.dart';
import 'package:mirrorline/features/pairing/peer_provider.dart';

class RoleSelectionScreen extends ConsumerWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rol Seçimi'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Bu telefon hangi rolde çalışsın?',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Rolü daha sonra ayarlardan değiştirebilirsiniz.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xl),
            _RoleCard(
              title: 'Asıl Telefon',
              subtitle: 'Bildirimleri görür, aramaları reddedebilir, SMS’lere yanıt yazarsınız.',
              icon: Icons.phone_android_rounded,
              onTap: () => _selectRole(context, ref, 'main'),
            ),
            const SizedBox(height: AppSpacing.md),
            _RoleCard(
              title: 'Diğer Telefon',
              subtitle: 'SIM’in bulunduğu, arka planda arama ve SMS eventlerini yakalayan cihaz.',
              icon: Icons.sim_card_rounded,
              onTap: () => _selectRole(context, ref, 'source'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectRole(BuildContext context, WidgetRef ref, String role) async {
    await ref.read(peerProvider.notifier).createPeer(role);
    await ref.read(connectionProvider.notifier).refresh();
    if (!context.mounted) return;

    // The Source device (the one holding the SIM) is the one that must
    // keep running reliably in the background -- ask for the battery
    // optimization exemption right now, while we have the user's
    // attention, instead of leaving it as an easy-to-miss Settings toggle.
    if (role == 'source') {
      await _offerBatteryExemption(context);
    }

    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(role == 'main' ? 'Asıl Telefon seçildi' : 'Diğer Telefon seçildi')),
      );
    }
  }

  Future<void> _offerBatteryExemption(BuildContext context) async {
    if (await PermissionService.isBatteryOptimizationIgnored()) return;
    if (!context.mounted) return;

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.battery_charging_full_rounded),
        title: const Text('Arka planda güvenilir çalışma'),
        content: const Text(
          'Bu cihaz "Diğer Telefon" olduğu için arama/SMS eventlerini yakalayabilmesi '
          'adına ekran kapalıyken de sürekli çalışmalı. Bunun için Android\'in pil '
          'optimizasyonundan bu uygulamayı hariç tutmanız gerekiyor.\n\n'
          'Not: bu, normalden biraz daha fazla pil tüketimi anlamına gelir -- '
          'bağlantıyı canlı tutmanın bilinçli bir bedeli. İstemezseniz daha sonra '
          'Ayarlar\'dan da açabilirsiniz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Daha Sonra'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Şimdi Ayarla'),
          ),
        ],
      ),
    );

    if (proceed == true) {
      await PermissionService.requestIgnoreBatteryOptimizations();
    }
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(icon, color: theme.colorScheme.primary, size: 28),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
