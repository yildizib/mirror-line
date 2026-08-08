import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/peer.dart';
import '../../providers/connection_provider.dart';
import '../../providers/connection_status_provider.dart';
import '../../providers/peer_provider.dart';
import '../../security/key_store.dart';
import '../../services/permission_service.dart';
import '../../telephony/telephony_channel.dart';
import '../theme.dart';
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

  String? _selfDeviceName;
  String? _selfPublicKey;

  @override
  void initState() {
    super.initState();
    _loadSelfIdentity();
  }

  Future<void> _loadSelfIdentity() async {
    final name = await KeyStore.getSelfDeviceName();
    final pubKey = await KeyStore.getDevicePublicKey();
    if (!mounted) return;
    setState(() {
      _selfDeviceName = name;
      _selfPublicKey = pubKey;
    });
  }

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
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        // This device's own identity -- always self-scoped (KeyStore +
        // live local IP), never the paired peer's info, regardless of
        // pairing direction.
        _sectionTitle(context, 'Bu Cihaz'),
        _sectionCard(
          child: peer == null
              ? const Text('Henüz cihaz bilgisi oluşturulmadı. Rol seçin.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _avatar(
                          theme,
                          icon: peer.role == 'main' ? Icons.phone_android_rounded : Icons.sim_card_rounded,
                          color: theme.colorScheme.primary,
                          background: theme.colorScheme.primaryContainer,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selfDeviceName ?? peer.deviceName,
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                peer.role == 'main' ? 'Asıl Telefon' : 'Diğer Telefon',
                                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _infoRow(context, 'IP', status.localIp ?? peer.ip),
                    if (_selfPublicKey != null) _infoRow(context, 'Public Key', _selfPublicKey!),
                    if (peer.publicKey.isEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Henüz eşleşmediniz. Karşı cihaza taratmak için:',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Center(
                        child: QrDisplay(
                          data:
                              '${peer.id}|${peer.ip}|${peer.port}|${peer.key}|${peer.deviceName}|${peer.role}|${_selfPublicKey ?? ''}',
                        ),
                      ),
                    ],
                  ],
                ),
        ),

        // The paired other device's identity -- persists here once pairing
        // succeeds, regardless of who scanned whom, until the device is
        // reset (which requires pairing again from scratch).
        if (peer != null && peer.publicKey.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _sectionTitle(context, 'Bağlı Cihaz'),
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _avatar(
                      theme,
                      icon: peer.role == 'main' ? Icons.sim_card_rounded : Icons.phone_android_rounded,
                      color: theme.status.success,
                      background: theme.status.successContainer,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        peer.deviceName,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    _connectionStatusChip(context, isConnected: isConnected, isConnecting: isConnecting),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _infoRow(context, 'IP', '${peer.ip}:${peer.port}'),
                _infoRow(context, 'Rol', peer.role == 'main' ? 'Diğer Telefon (karşı)' : 'Asıl Telefon (karşı)'),
                _infoRow(context, 'Public Key', peer.publicKey),
                _infoRow(context, 'MAC', 'Android bunu başka bir cihazdan okumaya izin vermiyor'),
              ],
            ),
          ),
        ],

        // Connection diagnostics
        const SizedBox(height: AppSpacing.lg),
        _sectionTitle(context, 'Bağlantı Teşhisi'),
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(context, 'Bu cihaz IP', status.localIp ?? 'belirlenemedi'),
              _infoRow(context, 'Eş cihaz IP', status.peerIp ?? '-'),
              _infoRow(
                context,
                'Sunucu',
                status.serverRunning ? 'çalışıyor (port ${status.serverPort})' : 'kapalı',
              ),
              _infoRow(
                context,
                'Son beacon',
                status.lastBeaconIp == null
                    ? 'henüz yok'
                    : '${status.lastBeaconIp} (${_formatTime(status.lastBeaconAt!)})',
              ),
              _infoRow(context, 'Deneme sayısı', '${status.connectAttempts}'),
              if (status.lastError != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  status.lastError!,
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),

        // Paired devices list
        const SizedBox(height: AppSpacing.lg),
        _sectionTitle(context, 'Eşleşmiş Cihazlar'),
        pairedPeers.when(
          data: (peers) {
            if (peers.isEmpty) {
              return _sectionCard(child: const Text('Henüz eşleşmiş cihaz yok.'));
            }
            return Column(
              children: peers.map((p) => _buildPeerCard(context, ref, p)).toList(),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Text('Hata: $err'),
        ),

        // Actions
        const SizedBox(height: AppSpacing.lg),
        _sectionTitle(context, 'Eylemler'),
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _connectionStatusChip(context, isConnected: isConnected, isConnecting: isConnecting),
                  const Spacer(),
                  if (!isConnected && !isConnecting)
                    TextButton(
                      onPressed: () => ref.read(connectionProvider.notifier).retryNow(),
                      child: const Text('Yeniden Dene'),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _ipController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Karşı cihaz IP (manuel)',
                  hintText: 'örn. 192.168.1.20',
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _portController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    onPressed: () => _connectManually(context, ref),
                    child: const Text('Bağlan'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PairingScreen()),
          ),
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Cihaz Eşleştir'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: peer == null
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
                ),
          icon: const Icon(Icons.swap_horiz_rounded),
          label: const Text('Rol Değiştir'),
        ),

        // System
        const SizedBox(height: AppSpacing.lg),
        _sectionTitle(context, 'Sistem'),
        _sectionCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.battery_charging_full_rounded),
                title: const Text('Pil optimizasyonunu kaldır'),
                subtitle: const Text('Uygulamanın arka planda güvenilir çalışması için'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  await PermissionService.requestIgnoreBatteryOptimizations();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Pil ayarları açıldı')),
                    );
                  }
                },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.notifications_active_rounded),
                title: const Text('Bildirim erişimi'),
                subtitle: const Text('Diğer telefondan bildirimleri yansıtmak için gerekli'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  await TelephonyChannel.openNotificationListenerSettings();
                },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Kullanılmıyorsa izinleri kaldırma'),
                subtitle: const Text(
                  'Uygulama Bilgisi\'nde "Kullanılmıyorsa izinleri kaldır" (HyperOS\'ta "Uygulama kullanılmıyorsa") '
                  'seçeneğini kapatın — açık kalırsa Android birkaç ay sonra SMS/arama izinlerini geri alabilir',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  await PermissionService.openAppInfoSettings();
                },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: Icon(Icons.delete_forever_rounded, color: theme.colorScheme.error),
                title: Text('Cihazı sıfırla', style: TextStyle(color: theme.colorScheme.error)),
                subtitle: const Text('Tüm verileri sil ve yeni QR oluştur'),
                onTap: () => _confirmReset(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Shared building blocks
  // ---------------------------------------------------------------------

  Widget _sectionCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Card(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppSpacing.md),
        child: child,
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _avatar(ThemeData theme, {required IconData icon, required Color color, required Color background}) {
    return CircleAvatar(
      radius: 22,
      backgroundColor: background,
      child: Icon(icon, color: color),
    );
  }

  /// Small pill showing live connection status, reused wherever it's shown.
  Widget _connectionStatusChip(BuildContext context, {required bool isConnected, required bool isConnecting}) {
    final status = Theme.of(context).status;
    final (icon, color, label) = isConnecting
        ? (Icons.sync_rounded, status.warning, 'Bağlanıyor...')
        : isConnected
            ? (Icons.check_circle_rounded, status.success, 'Bağlı')
            : (Icons.wifi_off_rounded, status.warning, 'Bağlı değil');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(value, style: TextStyle(fontSize: 14, color: colorScheme.onSurface)),
        ],
      ),
    );
  }

  Widget _buildPeerCard(BuildContext context, WidgetRef ref, Peer p) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _avatar(
          theme,
          icon: p.role == 'main' ? Icons.phone_android_rounded : Icons.sim_card_rounded,
          color: p.role == 'main' ? theme.colorScheme.primary : theme.status.success,
          background: p.role == 'main' ? theme.colorScheme.primaryContainer : theme.status.successContainer,
        ),
        title: Text(p.deviceName, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('IP: ${p.ip}:${p.port}'),
            Text('Rol: ${p.role == 'main' ? 'Asıl Telefon' : 'Diğer Telefon'}'),
          ],
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
          onPressed: () async {
            await ref.read(peerProvider.notifier).deletePeer(p);
            ref.invalidate(pairedPeersProvider);
            await ref.read(connectionProvider.notifier).refresh();
          },
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
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Bağlantı kuruldu' : 'Bağlantı kurulamadı'),
        backgroundColor: ok ? theme.status.success : theme.colorScheme.error,
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
            child: Text('Sıfırla', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }
}
