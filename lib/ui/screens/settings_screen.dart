import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/peer.dart';
import '../../providers/connection_provider.dart';
import '../../providers/connection_status_provider.dart';
import '../../providers/peer_provider.dart';
import '../../services/permission_service.dart';
import '../widgets/qr_display.dart';
import 'pairing_screen.dart';
import 'role_selection_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '45678');

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final peer = ref.watch(peerProvider);
    final pairedPeers = ref.watch(pairedPeersProvider);
    final isConnected = ref.watch(connectionProvider);
    final isConnecting = ref.watch(connectionConnectingProvider);
    final status = ref.watch(connectionStatusProvider);
    final pairingRequest = ref.watch(pairingRequestProvider);

    pairingRequest.whenData((request) {
      if (request != null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showPairingConfirmation(context, ref, request);
        });
      }
    });

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
                  QrDisplay(data: '${peer.id}|${peer.ip}|${peer.port}|${peer.key}|${peer.deviceName}|${peer.role}'),
                ] else ...[
                  const Text('Henüz cihaz bilgisi oluşturulmadı. Rol seçin.'),
                ],
              ],
            ),
          ),
        ),

        // Connection diagnostics
        const SizedBox(height: 24),
        _buildSectionTitle(context, 'Bağlantı Teşhisi'),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('Bu cihaz IP', status.localIp ?? 'belirlenemedi'),
                _buildInfoRow('Eş cihaz IP', status.peerIp ?? '-'),
                _buildInfoRow('Sunucu', status.serverRunning ? 'çalışıyor (port ${status.serverPort})' : 'kapalı'),
                _buildInfoRow(
                  'Son beacon',
                  status.lastBeaconIp == null
                      ? 'henüz yok'
                      : '${status.lastBeaconIp} (${_formatTime(status.lastBeaconAt!)})',
                ),
                _buildInfoRow('Deneme sayısı', '${status.connectAttempts}'),
                if (status.lastError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    status.lastError!,
                    style: TextStyle(fontSize: 12, color: Colors.red[700]),
                  ),
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
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isConnecting ? Icons.wifi_find : (isConnected ? Icons.wifi : Icons.wifi_off),
                      color: isConnecting ? Colors.orange : (isConnected ? Colors.green : Colors.orange),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isConnecting ? 'Bağlanıyor...' : (isConnected ? 'Bağlı' : 'Bağlı değil'),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    if (!isConnected && !isConnecting)
                      TextButton(
                        onPressed: () => ref.read(connectionProvider.notifier).retryNow(),
                        child: const Text('Yeniden Dene'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _ipController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Karşı cihaz IP (manuel)',
                    hintText: 'örn. 192.168.1.20',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => _connectManually(context, ref),
                      child: const Text('Bağlan'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
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
            await ref.read(peerProvider.notifier).deletePeer(p);
            ref.invalidate(pairedPeersProvider);
            await ref.read(connectionProvider.notifier).refresh();
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

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  void _connectManually(BuildContext context, WidgetRef ref) async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 45678;

    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('IP adresi girin')),
      );
      return;
    }

    final ok = await ref.read(connectionProvider.notifier).connectManually(ip, port);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Bağlantı kuruldu' : 'Bağlantı kurulamadı'),
        backgroundColor: ok ? Colors.green : Colors.redAccent,
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
              await ref.read(connectionProvider.notifier).stopAll();
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
void _showPairingConfirmation(BuildContext context, WidgetRef ref, PairingRequest request) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Bağlantı İsteği'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${request.deviceName} cihazı bağlanmak istiyor.'),
          const SizedBox(height: 16),
          const Text('Doğrulama Kodu:', style: TextStyle(fontWeight: FontWeight.bold)),
          Text(
            request.verificationCode,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 4),
          ),
          const SizedBox(height: 8),
          const Text('Kod her iki cihazda aynı olmalı.'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Reddet'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Kabul Et'),
        ),
      ],
    ),
  );

  if (confirmed != true) {
    ref.read(connectionProvider.notifier).stopAll();
  }
}
