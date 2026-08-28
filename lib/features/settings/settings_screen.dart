import 'package:flutter/material.dart';
import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/models/peer.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:mirrorline/core/services/locale_service.dart';
import 'package:mirrorline/core/services/permission_service.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/connection/connection_facade.dart';
import 'package:mirrorline/features/connection/connection_status_provider.dart';
import 'package:mirrorline/features/pairing/pairing_screen.dart';
import 'package:mirrorline/features/pairing/local_pairing_identity.dart';
import 'package:mirrorline/features/pairing/pairing_controller.dart';
import 'package:mirrorline/features/pairing/peer_facade.dart';
import 'package:mirrorline/features/pairing/role_selection_screen.dart';
import 'package:mirrorline/features/pairing/widgets/qr_display.dart';
import 'package:mirrorline/features/settings/diagnostics_screen.dart';
import 'package:mirrorline/features/settings/settings_controller.dart';
import 'package:mirrorline/features/settings/watched_apps_screen.dart';

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
    final known = await ref
        .read(settingsControllerProvider)
        .hasKnownAutoStartSettings();
    if (!mounted) return;
    setState(() => _hasKnownAutoStartScreen = known);
  }

  Future<void> _loadBatterySaverAvailability() async {
    final known = await ref
        .read(settingsControllerProvider)
        .hasKnownBatterySaverSettings();
    if (!mounted) return;
    setState(() => _hasKnownBatterySaverScreen = known);
  }

  @override
  Widget build(BuildContext context) {
    final peer = ref.watch(peerFacadeProvider);
    final pairedPeers = ref.watch(pairedPeersProvider);
    final isConnected = ref.watch(connectionFacadeProvider);
    final isConnecting = ref.watch(connectionConnectingProvider);
    final localIp = ref.watch(
      connectionStatusProvider.select((s) => s.localIp),
    );
    final localPairingIdentity = ref
        .watch(localPairingIdentityProvider(localIp ?? 'unknown'))
        .valueOrNull;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _ThisDeviceSection(
          peer: peer,
          selfDeviceName: _selfDeviceName,
          selfPublicKey: _selfPublicKey,
          localPairingIdentity: localPairingIdentity,
          localIp: localIp,
        ),
        if (peer != null && peer.publicKey.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _PairedDeviceSection(
            peer: peer,
            isConnected: isConnected,
            isConnecting: isConnecting,
            onForceConnect: () => _showForceConnectDialog(context, ref),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _ConnectionDiagnosticsSection(
          localIp: localIp,
          peerIp: ref.watch(connectionStatusProvider.select((s) => s.peerIp)),
          serverRunning: ref.watch(
            connectionStatusProvider.select((s) => s.serverRunning),
          ),
          serverPort: ref.watch(
            connectionStatusProvider.select((s) => s.serverPort),
          ),
          connectAttempts: ref.watch(
            connectionStatusProvider.select((s) => s.connectAttempts),
          ),
          lastBeaconIp: ref.watch(
            connectionStatusProvider.select((s) => s.lastBeaconIp),
          ),
          lastBeaconAt: ref.watch(
            connectionStatusProvider.select((s) => s.lastBeaconAt),
          ),
          lastErrorCode: ref.watch(
            connectionStatusProvider.select((s) => s.lastErrorCode),
          ),
          lastErrorDetail: ref.watch(
            connectionStatusProvider.select((s) => s.lastErrorDetail),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _PairedDevicesSection(pairedPeers: pairedPeers),
        const SizedBox(height: AppSpacing.lg),
        _PairingActionsSection(peer: peer),
        const SizedBox(height: AppSpacing.lg),
        _SystemSection(
          hasKnownAutoStartScreen: _hasKnownAutoStartScreen,
          hasKnownBatterySaverScreen: _hasKnownBatterySaverScreen,
        ),
        const SizedBox(height: AppSpacing.lg),
        _DangerZoneSection(onReset: () => _confirmReset(context, ref)),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Dialogs (still owned by the State: they need ref + context)
  // ---------------------------------------------------------------------

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
      builder: (ctx) => const _ForceConnectDialog(),
    );
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
}

// =====================================================================
// Shared building blocks (still needed by sections)
// =====================================================================

class _SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;

  const _SectionCard({required this.child, this.padding, this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: borderColor != null
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: BorderSide(color: borderColor!, width: 1.2),
            )
          : null,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppSpacing.md),
        child: child,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
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

/// A label/value info row used inside section cards. The value is
/// selectable so long public keys / IPs can be copied.
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  /// When true, long values (>24 chars) are shortened to `prefix…suffix`
  /// and the full value is shown via a Tooltip. Used for public keys.
  final bool shortenLong;

  const _InfoRow({
    required this.label,
    required this.value,
    this.shortenLong = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayed = shortenLong && value.length > 24
        ? _shortKey(value)
        : value;
    final valueWidget = SelectableText(
      displayed,
      style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
    );
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
          if (shortenLong && value.length > 24)
            Tooltip(
              message: value,
              waitDuration: const Duration(milliseconds: 400),
              child: valueWidget,
            )
          else
            valueWidget,
        ],
      ),
    );
  }
}

/// Two-column info row: pairs related diagnostics (Local IP / Peer IP,
/// Server / Attempts, etc.) side by side to cut down the vertical sprawl
/// of the old one-row-per-field diagnostics card.
class _InfoRowPair extends StatelessWidget {
  final String labelA;
  final String valueA;
  final String labelB;
  final String valueB;

  const _InfoRowPair({
    required this.labelA,
    required this.valueA,
    required this.labelB,
    required this.valueB,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _InfoRow(label: labelA, value: valueA),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _InfoRow(label: labelB, value: valueB),
          ),
        ],
      ),
    );
  }
}

/// Shortens a long public key/base64 string to `prefix…suffix` while
/// keeping the full value reachable through a [Tooltip]. Anything short
/// enough to read at a glance is shown verbatim.
String _shortKey(String key) {
  if (key.length <= 24) return key;
  return '${key.substring(0, 10)}…${key.substring(key.length - 10)}';
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

// =====================================================================
// Sections
// =====================================================================

class _ThisDeviceSection extends StatelessWidget {
  final Peer? peer;
  final String? selfDeviceName;
  final String? selfPublicKey;
  final LocalPairingIdentity? localPairingIdentity;
  final String? localIp;

  const _ThisDeviceSection({
    required this.peer,
    required this.selfDeviceName,
    required this.selfPublicKey,
    required this.localPairingIdentity,
    required this.localIp,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          icon: Icons.phone_android_rounded,
          title: l.settingsThisDevice,
        ),
        _SectionCard(
          child: peer == null
              ? Text(l.settingsNoDeviceInfo)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _avatar(
                          theme,
                          icon: peer!.role == 'main'
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
                                selfDeviceName ?? peer!.deviceName,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                peer!.role == 'main'
                                    ? l.roleMain
                                    : l.roleSource,
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
                    _InfoRow(
                      label: l.settingsIpLabel,
                      value: localIp ?? peer!.ip,
                    ),
                    if (selfPublicKey != null)
                      _InfoRow(
                        label: l.settingsPublicKeyLabel,
                        value: selfPublicKey!,
                        shortenLong: true,
                      ),
                    if (peer!.publicKey.isEmpty &&
                        localPairingIdentity != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        l.settingsNotPairedHint,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Center(
                        child: QrDisplay(data: localPairingIdentity!.qrData),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _PairedDeviceSection extends StatelessWidget {
  final Peer peer;
  final bool isConnected;
  final bool isConnecting;
  final Future<void> Function() onForceConnect;

  const _PairedDeviceSection({
    required this.peer,
    required this.isConnected,
    required this.isConnecting,
    required this.onForceConnect,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(icon: Icons.link_rounded, title: l.settingsPairedDevice),
        _SectionCard(
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
                      peer.displayName,
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
              _InfoRow(
                label: l.settingsIpLabel,
                value: '${peer.ip}:${peer.port}',
              ),
              _InfoRow(
                label: l.settingsPort,
                value:
                    '${peer.role == 'main' ? l.roleSource : l.roleMain}${l.settingsCounterpartSuffix}',
              ),
              _InfoRow(
                label: l.settingsPublicKeyLabel,
                value: peer.publicKey,
                shortenLong: true,
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: isConnected ? null : () => onForceConnect(),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(l.settingsForceReconnect),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConnectionDiagnosticsSection extends StatelessWidget {
  final String? localIp;
  final String? peerIp;
  final bool serverRunning;
  final int serverPort;
  final int connectAttempts;
  final String? lastBeaconIp;
  final DateTime? lastBeaconAt;
  final ConnectionErrorCode? lastErrorCode;
  final String? lastErrorDetail;

  const _ConnectionDiagnosticsSection({
    required this.localIp,
    required this.peerIp,
    required this.serverRunning,
    required this.serverPort,
    required this.connectAttempts,
    required this.lastBeaconIp,
    required this.lastBeaconAt,
    required this.lastErrorCode,
    required this.lastErrorDetail,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          icon: Icons.network_check_rounded,
          title: l.settingsConnectionDiag,
        ),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRowPair(
                labelA: l.settingsLocalIp,
                valueA: localIp ?? l.settingsIpUnknown,
                labelB: l.settingsPeerIp,
                valueB: peerIp ?? '-',
              ),
              _InfoRowPair(
                labelA: l.settingsServer,
                valueA: serverRunning
                    ? l.settingsServerRunning(serverPort)
                    : l.settingsServerStopped,
                labelB: l.settingsConnectAttempts,
                valueB: '$connectAttempts',
              ),
              _InfoRow(
                label: l.settingsLastBeacon,
                value: lastBeaconIp == null
                    ? l.settingsNoBeacon
                    : '$lastBeaconIp (${_formatTime(lastBeaconAt!)})',
              ),
              if (lastErrorCode != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  connectionErrorText(l, lastErrorCode!, lastErrorDetail),
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}

class _PairedDevicesSection extends ConsumerWidget {
  final AsyncValue<List<Peer>> pairedPeers;

  const _PairedDevicesSection({required this.pairedPeers});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          icon: Icons.devices_rounded,
          title: l.settingsPairedDevices,
        ),
        pairedPeers.when(
          data: (peers) {
            if (peers.isEmpty) {
              return _SectionCard(child: Text(l.settingsNoPairedDevices));
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
      ],
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
          p.displayName,
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
}

class _PairingActionsSection extends StatelessWidget {
  final Peer? peer;

  const _PairingActionsSection({required this.peer});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(icon: Icons.qr_code_rounded, title: l.settingsPairDevice),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
            ],
          ),
        ),
      ],
    );
  }
}

class _SystemSection extends ConsumerWidget {
  final bool hasKnownAutoStartScreen;
  final bool hasKnownBatterySaverScreen;

  const _SystemSection({
    required this.hasKnownAutoStartScreen,
    required this.hasKnownBatterySaverScreen,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(icon: Icons.tune_rounded, title: l.settingsSystem),
        _SectionCard(
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
                  await ref
                      .read(settingsControllerProvider)
                      .openNotificationListenerSettings();
                },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.apps_rounded),
                title: Text(l.settingsWatchedApps),
                subtitle: Text(l.settingsWatchedAppsDesc),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const WatchedAppsScreen(),
                    ),
                  );
                },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.bug_report_rounded),
                title: Text(l.settingsRunTests),
                subtitle: Text(l.settingsRunTestsDesc),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DiagnosticsScreen(),
                    ),
                  );
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
                  hasKnownAutoStartScreen
                      ? l.settingsAutoStartKnown
                      : l.settingsAutoStartFallback,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  await ref
                      .read(settingsControllerProvider)
                      .openAutoStartSettings();
                },
              ),
              if (hasKnownBatterySaverScreen) ...[
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.battery_saver_rounded),
                  title: Text(l.settingsBatterySaver),
                  subtitle: Text(l.settingsBatterySaverDesc),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    await ref
                        .read(settingsControllerProvider)
                        .openBatterySaverSettings();
                  },
                ),
              ],
            ],
          ),
        ),
      ],
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

class _DangerZoneSection extends StatelessWidget {
  final VoidCallback onReset;

  const _DangerZoneSection({required this.onReset});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final errorColor = theme.colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          icon: Icons.warning_amber_rounded,
          title: l.settingsDangerZone,
        ),
        _SectionCard(
          borderColor: errorColor.withValues(alpha: 0.4),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_forever_rounded, color: errorColor),
            title: Text(
              l.settingsResetDevice,
              style: TextStyle(color: errorColor),
            ),
            subtitle: Text(l.settingsResetDesc),
            trailing: Icon(Icons.chevron_right_rounded, color: errorColor),
            onTap: onReset,
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// Dialogs
// =====================================================================

/// Live progress dialog for forceReconnect. Watches the connection status
/// provider and renders the discovery log as it updates.
class _ForceConnectDialog extends ConsumerWidget {
  const _ForceConnectDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionStatusProvider);
    final connected = ref.watch(connectionFacadeProvider);
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final done = connected || !status.forceConnectActive;

    if (done && context.mounted) {
      // Close after a short delay so the user sees the final result.
      Future.delayed(const Duration(milliseconds: 800), () {
        if (context.mounted) Navigator.of(context).pop();
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
              color: connected ? theme.status.success : theme.colorScheme.error,
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
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.settingsForceConnectClose),
          ),
      ],
    );
  }
}
