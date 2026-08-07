import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/peer.dart';
import '../../providers/peer_provider.dart';
import '../../services/permission_service.dart';
import '../widgets/qr_display.dart';
import 'pairing_screen.dart';
import 'role_selection_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peer = ref.watch(peerProvider);
    final pairedPeers = ref.watch(pairedPeersProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // This device info
        _buildSectionTitle(context, 'Bu Cihaz'),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (peer != null) ...[
                  Text(
                    peer.deviceName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow('IP', '${peer.ip}:${peer.port}'),
                  _buildInfoRow('Rol', peer.role == 'main' ? 'Asıl Telefon' : 'Diğer Telefon'),
                  _buildInfoRow('ID', peer.id),
                  const SizedBox(height: 16),
                  QrDisplay(data: '${peer.id}|${peer.ip}|${peer.port}|${peer.key}|${peer.deviceName}'),
                ] else ...[
                  const Text('Henüz cihaz bilgisi oluşturulmadı. Rol seçin.'),
                ],
              ],
            ),
          ),
        ),

        // Paired devices list
        const SizedBox(height: 24),
        _buildSectionTitle(context, 'Eşleşmiş Cihazlar'),
        pairedPeers.when(
          data: (peers) {
            if (peers.isEmpty) {
              return Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Henüz eşleşmiş cihaz yok.'),
                ),
              );
            }
            return Column(
              children: peers.map((p) => _buildPeerCard(context, ref, p)).toList(),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Text('Hata: $err'),
        ),

        // Actions
        const SizedBox(height: 24),
        _buildSectionTitle(context, 'Eylemler'),
        FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PairingScreen()),
          ),
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Cihaz Eşleştir'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: peer == null
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
                ),
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Rol Değiştir'),
        ),

        // System
        const SizedBox(height: 24),
        _buildSectionTitle(context, 'Sistem'),
        ListTile(
          leading: const Icon(Icons.battery_alert),
          title: const Text('Pil optimizasyonunu kaldır'),
          subtitle: const Text('Uygulamanın arka planda güvenilir çalışması için'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await PermissionService.requestIgnoreBatteryOptimizations();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pil ayarları açıldı')),
              );
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
          title: const Text('Cihazı sıfırla', style: TextStyle(color: Colors.redAccent)),
          subtitle: const Text('Tüm verileri sil ve yeni QR oluştur'),
          onTap: () => _confirmReset(context, ref),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildPeerCard(BuildContext context, WidgetRef ref, Peer p) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: p.role == 'main'
              ? theme.colorScheme.primaryContainer
              : Colors.green[100],
          child: Icon(
            p.role == 'main' ? Icons.phone_android : Icons.sim_card,
            color: p.role == 'main' ? theme.colorScheme.primary : Colors.green,
          ),
        ),
        title: Text(p.deviceName, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('IP: ${p.ip}:${p.port}'),
            Text(
              'Rol: ${p.role == 'main' ? 'Asıl Telefon' : 'Diğer Telefon'}',
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          onPressed: () async {
            await ref.read(peerProvider.notifier).reset();
            ref.invalidate(pairedPeersProvider);
          },
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  void _confirmReset(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cihazı sıfırla'),
        content: const Text(
          'Tüm eşleştirme bilgileri, arama ve SMS geçmişi silinecek. Yeni QR oluşturulacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(peerProvider.notifier).reset();
              ref.invalidate(pairedPeersProvider);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cihaz sıfırlandı')),
                );
              }
            },
            child: const Text('Sıfırla', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}