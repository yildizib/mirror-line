import 'package:flutter/material.dart';
import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/models/peer.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:mirrorline/core/services/locale_service.dart';
import 'package:mirrorline/core/services/permission_service.dart';
import 'package:mirrorline/core/telephony/telephony_channel.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/connection/connection_facade.dart';
import 'package:mirrorline/features/connection/connection_status_provider.dart';
import 'package:mirrorline/features/pairing/pairing_screen.dart';
import 'package:mirrorline/features/pairing/peer_facade.dart';
import 'package:mirrorline/features/pairing/role_selection_screen.dart';
import 'package:mirrorline/features/pairing/widgets/qr_display.dart';
import 'package:mirrorline/features/settings/settings_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _selfDeviceName;
  String? _selfPublicKey;
  bool _hasKnownAutoStartScreen = false;
  bool _hasKnownBatterySaverScreen = false;

  @override
  void initState() {
    super.initState();
    _loadSelfIdentity();
    _loadAutoStartAvailability();
    _loadBatterySaverAvailability();
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

  Future<void> _loadAutoStartAvailability() async {
    final known = await TelephonyChannel.hasKnownAutoStartSettings();
    if (!mounted) return;
    setState(() => _hasKnownAutoStartScreen = known);
  }

  Future<void> _loadBatterySaverAvailability() async {
    final known = await TelephonyChannel.hasKnownBatterySaverSettings();
    if (!mounted) return;
    setState(() => _hasKnownBatterySaverScreen = known);
  }

  @override
  Widget build(BuildContext context) {
    final peer = ref.watch(peerFacadeProvider);
    final pairedPeers = ref.watch(pairedPeersProvider);
    final isConnected = ref.watch(connectionFacadeProvider);
    final isConnecting = ref.watch(connectionConnectingProvider);
    final status = ref.watch(connectionStatusProvider.select((s) => s));
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        // This device's own identity -- always self-scoped (KeyStore +
        // live local IP), never the paired peer's info, regardless of
        // pairing direction.
        _sectionTitle(context, l.settingsThisDevice),
        _sectionCard(
          child: peer == null
              ? Text(l.settingsNoDeviceInfo)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _avatar(
                          theme,
                          icon: peer.role == 'main'
                              ? Icons.phone_android_rounded
                              : Icons.sim_card_rounded,
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
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                peer.role == 'main' ? l.roleMain : l.roleSource,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _infoRow(
                      context,
                      l.settingsIpLabel,
                      status.localIp ?? peer.ip,
                    ),
                    if (_selfPublicKey != null)
                      _infoRow(
                        context,
                        l.settingsPublicKeyLabel,
                        _selfPublicKey!,
                      ),
                    if (peer.publicKey.isEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        l.settingsNotPairedHint,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Center(
                        child: QrDisplay(
                          data:
                              '${peer.id}|${status.localIp ?? 'unknown'}|${peer.port}|${peer.key}|${peer.deviceName}|${peer.role}|${_selfPublicKey ?? ''}',
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
          _sectionTitle(context, l.settingsPairedDevice),
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _avatar(
                      theme,
                      icon: peer.role == 'main'
                          ? Icons.sim_card_rounded
                          : Icons.phone_android_rounded,
                      color: theme.status.success,
                      background: theme.status.successContainer,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        peer.deviceName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _connectionStatusChip(
                      context,
                      isConnected: isConnected,
                      isConnecting: isConnecting,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _infoRow(context, l.settingsIpLabel, '${peer.ip}:${peer.port}'),
                _infoRow(
                  context,
                  l.settingsPort,
                  '${peer.role == 'main' ? l.roleSource : l.roleMain}${l.settingsCounterpartSuffix}',
                ),
                _infoRow(context, l.settingsPublicKeyLabel, peer.publicKey),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: isConnected
                        ? null
                        : () => _showForceConnectDialog(context, ref),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(l.settingsForceReconnect),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Connection diagnostics
        const SizedBox(height: AppSpacing.lg),
        _sectionTitle(context, l.settingsConnectionDiag),
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(
                context,
                l.settingsLocalIp,
                status.localIp ?? l.settingsIpUnknown,
              ),
              _infoRow(context, l.settingsPeerIp, status.peerIp ?? '-'),
              _infoRow(
                context,
                l.settingsServer,
                status.serverRunning
                    ? l.settingsServerRunning(status.serverPort)
                    : l.settingsServerStopped,
              ),
              _infoRow(
                context,
                l.settingsLastBeacon,
                status.lastBeaconIp == null
                    ? l.settingsNoBeacon
                    : '${status.lastBeaconIp} (${_formatTime(status.lastBeaconAt!)})',
              ),
              _infoRow(
                context,
                l.settingsConnectAttempts,
                '${status.connectAttempts}',
              ),
              if (status.lastErrorCode != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  connectionErrorText(
                    l,
                    status.lastErrorCode!,
                    status.lastErrorDetail,
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),

        // Paired devices list
        const SizedBox(height: AppSpacing.lg),
        _sectionTitle(context, l.settingsPairedDevices),
        pairedPeers.when(
          data: (peers) {
            if (peers.isEmpty) {
              return _sectionCard(child: Text(l.settingsNoPairedDevices));
            }
            return Column(
              children: peers
                  .map((p) => _buildPeerCard(context, ref, p))
                  .toList(),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Text(l.commonError(err.toString())),
        ),

        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PairingScreen()),
          ),
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: Text(l.settingsPairDevice),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: peer == null
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RoleSelectionScreen(),
                  ),
                ),
          icon: const Icon(Icons.swap_horiz_rounded),
          label: Text(l.settingsChangeRole),
        ),

        // System
        const SizedBox(height: AppSpacing.lg),
        _sectionTitle(context, l.settingsSystem),
        _sectionCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.language_rounded),
                title: Text(l.settingsLanguage),
                trailing: DropdownButton<Locale?>(
                  value: ref.watch(localeProvider),
                  items: [
                    DropdownMenuItem<Locale?>(
                      value: null,
                      child: Text(l.settingsLanguageSystem),
                    ),
                    ...LocaleNotifier.supportedLocales.map(
                      (loc) => DropdownMenuItem<Locale?>(
                        value: loc,
                        child: Text(_localeDisplayName(loc)),
                      ),
                    ),
                  ],
                  onChanged: (loc) =>
                      ref.read(localeProvider.notifier).set(loc),
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.battery_charging_full_rounded),
                title: Text(l.settingsRemoveBatteryOpt),
                subtitle: Text(l.settingsRemoveBatteryOptDesc),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  await PermissionService.requestIgnoreBatteryOptimizations();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.settingsBatteryOpened)),
                    );
                  }
                },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.notifications_active_rounded),
                title: Text(l.settingsNotifAccess),
                subtitle: Text(l.settingsNotifAccessDesc),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  await TelephonyChannel.openNotificationListenerSettings();
                },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(l.settingsKeepPermissions),
                subtitle: Text(l.settingsKeepPermissionsDesc),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  await PermissionService.openAppInfoSettings();
                },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.rocket_launch_rounded),
                title: Text(l.settingsAutoStart),
                subtitle: Text(
                  _hasKnownAutoStartScreen
                      ? l.settingsAutoStartKnown
                      : l.settingsAutoStartFallback,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  await TelephonyChannel.openAutoStartSettings();
                },
              ),
              if (_hasKnownBatterySaverScreen) ...[
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.battery_saver_rounded),
                  title: Text(l.settingsBatterySaver),
                  subtitle: Text(l.settingsBatterySaverDesc),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    await TelephonyChannel.openBatterySaverSettings();
                  },
                ),
              ],
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: Icon(
                  Icons.delete_forever_rounded,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  l.settingsResetDevice,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                subtitle: Text(l.settingsResetDesc),
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
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _avatar(
    ThemeData theme, {
    required IconData icon,
    required Color color,
    required Color background,
  }) {
    return CircleAvatar(
      radius: 22,
      backgroundColor: background,
      child: Icon(icon, color: color),
    );
  }

  Widget _connectionStatusChip(
    BuildContext context, {
    required bool isConnected,
    required bool isConnecting,
  }) {
    final status = Theme.of(context).status;
    final l = AppLocalizations.of(context);
    final (icon, color, label) = isConnecting
        ? (Icons.sync_rounded, status.warning, l.connStatusConnecting)
        : isConnected
        ? (Icons.check_circle_rounded, status.success, l.connStatusConnected)
        : (Icons.wifi_off_rounded, status.warning, l.connStatusDisconnected);

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
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
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
          SelectableText(
            value,
            style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
          ),
        ],
      ),
    );
  }

  /// Shows a real-time progress dialog while forceReconnect runs. The dialog
  /// watches `connectionStatusProvider` and renders the discovery log +
  /// current state live, so the user sees exactly which IPs/methods are
  /// being tried instead of a silent spinner.
  Future<void> _showForceConnectDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    // Kick off the force reconnect (fire-and-forget -- the dialog tracks
    // progress via the status provider, not via the returned Future).
    ref.read(connectionFacadeProvider.notifier).forceReconnect();

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false, // don't dismiss mid-attempt
      builder: (ctx) {
        return Consumer(
          builder: (ctx, ref, _) {
            final status = ref.watch(connectionStatusProvider);
            final connected = ref.watch(connectionFacadeProvider);
            final l = AppLocalizations.of(ctx);
            final theme = Theme.of(ctx);

            // Auto-close once connected or once forceConnectActive goes false.
            final done = connected || !status.forceConnectActive;

            if (done && ctx.mounted) {
              // Close after a short delay so the user sees the final result.
              Future.delayed(const Duration(milliseconds: 800), () {
                if (ctx.mounted) Navigator.of(ctx).pop();
              });
            }

            return AlertDialog(
              title: Row(
                children: [
                  if (!done)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      connected
                          ? Icons.check_circle_rounded
                          : Icons.error_outline_rounded,
                      color: connected
                          ? theme.status.success
                          : theme.colorScheme.error,
                    ),
                  const SizedBox(width: 12),
                  Text(
                    connected
                        ? l.settingsForceConnectDone
                        : !status.forceConnectActive
                        ? l.settingsForceConnectFailed
                        : l.settingsForceConnectTitle,
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (status.discoveryDetail != null && !done)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          status.discoveryDetail!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    const Divider(height: 1),
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 240),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: status.discoveryLog.length,
                          itemBuilder: (ctx, i) {
                            final entry = status.discoveryLog[i];
                            final time =
                                '${entry.timestamp.hour.toString().padLeft(2, '0')}'
                                ':${entry.timestamp.minute.toString().padLeft(2, '0')}'
                                ':${entry.timestamp.second.toString().padLeft(2, '0')}';
                            final icon = entry.isSuccess
                                ? '✓'
                                : entry.isError
                                ? '✗'
                                : '•';
                            final color = entry.isSuccess
                                ? theme.status.success
                                : entry.isError
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSurfaceVariant;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                '$time $icon ${entry.message}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: color,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (done)
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(l.settingsForceConnectClose),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPeerCard(BuildContext context, WidgetRef ref, Peer p) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _avatar(
          theme,
          icon: p.role == 'main'
              ? Icons.phone_android_rounded
              : Icons.sim_card_rounded,
          color: p.role == 'main'
              ? theme.colorScheme.primary
              : theme.status.success,
          background: p.role == 'main'
              ? theme.colorScheme.primaryContainer
              : theme.status.successContainer,
        ),
        title: Text(
          p.deviceName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${l.settingsIpLabel}: ${p.ip}:${p.port}'),
            Text(
              '${l.settingsRoleLabel}: ${p.role == 'main' ? l.roleSource : l.roleMain}',
            ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(
            Icons.delete_outline_rounded,
            color: theme.colorScheme.error,
          ),
          onPressed: () async {
            await ref.read(settingsControllerProvider).deletePeer(p);
          },
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  void _confirmReset(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.settingsResetConfirmTitle),
        content: Text(l.settingsResetConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(settingsControllerProvider).resetDevice();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(l.settingsResetDone)));
              }
            },
            child: Text(
              l.commonReset,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  String _localeDisplayName(Locale loc) {
    switch (loc.languageCode) {
      case 'tr':
        return 'Türkçe';
      case 'en':
        return 'English';
      default:
        return loc.languageCode;
    }
  }
}
