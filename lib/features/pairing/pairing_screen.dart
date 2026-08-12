import 'package:flutter/material.dart';
import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/models/peer.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/connection/connection_facade.dart';
import 'package:mirrorline/features/connection/connection_status_provider.dart';
import 'package:mirrorline/features/pairing/pairing_provider.dart';
import 'package:mirrorline/features/pairing/peer_provider.dart';
import 'package:mirrorline/features/pairing/role_selection_screen.dart';
import 'package:mirrorline/features/pairing/widgets/qr_display.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  bool _isScanning = false;
  bool _isProcessing = false;
  Peer? _cachedPeerForQr;
  String? _myPublicKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final pub = await KeyStore.ensureDeviceKeyPair();
      if (mounted) setState(() => _myPublicKey = pub);
      // The QR encodes this device's current IP. Refresh it into the
      // connection status (never into the peer record -- after pairing that
      // row belongs to the *other* device, and overwriting it with our own
      // address is what made Settings show the same IP for both devices).
      ref.read(connectionFacadeProvider.notifier).updateLocalIp();
    });
  }

  @override
  Widget build(BuildContext context) {
    final peer = ref.watch(peerProvider);
    final pairingState = ref.watch(pairingProvider);
    final status = ref.watch(connectionStatusProvider);
    final l = AppLocalizations.of(context);

    // Re-sync on any identity-relevant change so the QR always reflects the
    // current peer record.
    if (peer != null && _cachedPeerForQr?.id != peer.id) {
      _cachedPeerForQr = peer;
    }

    // Listen for incoming pairing request on the scanned device.
    if (pairingState.isShowingRequest && !_isProcessing) {
      _isProcessing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showIncomingRequestDialog(pairingState);
      });
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.pairingTitle),
          bottom: TabBar(
            tabs: [
              Tab(
                text: l.pairingShowQr,
                icon: const Icon(Icons.qr_code_rounded),
              ),
              Tab(
                text: l.pairingScanQr,
                icon: const Icon(Icons.qr_code_scanner_rounded),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildShowQrTab(_cachedPeerForQr, pairingState, status.localIp),
            _buildScanTab(pairingState),
          ],
        ),
      ),
    );
  }

  Widget _buildShowQrTab(
    Peer? peer,
    PairingState pairingState,
    String? localIp,
  ) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    if (peer == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                l.pairingSelectRoleFirst,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RoleSelectionScreen(),
                  ),
                ),
                child: Text(l.pairingSelectRoleButton),
              ),
            ],
          ),
        ),
      );
    }

    // QR format: id|ip|port|key|deviceName|role|publicKey
    // publicKey here is THIS device's Ed25519 public key (from KeyStore),
    // NOT the peer's publicKey field (which is the other device's key).
    // The encoded ip is THIS device's live local address (from the
    // connection status), never peer.ip -- after pairing that field holds
    // the *other* device's address, and encoding it here would break the
    // scanner's connect attempt.
    final myPub = _myPublicKey ?? '';
    // If localIp is null, don't encode a stale/wrong IP (peer.ip may be
    // this device's own IP after pairing, which would create a loop).
    // Prefer VPN IP (tun0) if available -- it's reachable from any device
    // on the same VPN, unlike a WiFi IP that's only reachable on the same
    // LAN. Fall back to WiFi/local IP, then 'unknown'.
    final qrIp = localIp ?? 'unknown';
    final qrData =
        '${peer.id}|$qrIp|${peer.port}|${peer.key}|${peer.deviceName}|${peer.role}|$myPub';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            QrDisplay(data: qrData),
            const SizedBox(height: AppSpacing.lg),
            _verificationCodeBadge(context, peer.verificationCode),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l.pairingOtherScanHint,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (pairingState.isShowingRequest) ...[
              const SizedBox(height: AppSpacing.md),
              Card(
                color: theme.status.successContainer,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.link_rounded, color: theme.status.success),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        l.pairingRequestReceived,
                        style: TextStyle(
                          color: theme.status.onSuccessContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Shared "6-digit code" display used on the QR tab, the scan-waiting
  /// state, and both confirmation dialogs so it looks the same everywhere.
  Widget _verificationCodeBadge(BuildContext context, String code) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        Text(
          l.verificationCodeLabel,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            code,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScanTab(PairingState pairingState) {
    final l = AppLocalizations.of(context);
    // Show waiting state while handshake is in progress.
    if (pairingState.isWaitingForAccept) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              l.pairingWaiting(
                pairingState.remoteDeviceName ?? l.pairingUnknownDevice,
              ),
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (pairingState.verificationCode != null)
              Column(
                children: [
                  _verificationCodeBadge(
                    context,
                    pairingState.verificationCode!,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l.pairingCodeMatch,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: () => ref.read(pairingProvider.notifier).reset(),
              child: Text(l.pairingCancel),
            ),
          ],
        ),
      );
    }

    // Show error if any.
    if (pairingState.errorCode != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              pairingErrorText(
                l,
                pairingState.errorCode!,
                pairingState.errorDetail,
              ),
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () {
                ref.read(pairingProvider.notifier).reset();
                setState(() {});
              },
              child: Text(l.pairingRetry),
            ),
          ],
        ),
      );
    }

    if (_isScanning) {
      return Stack(
        children: [
          MobileScanner(
            onDetect: (BarcodeCapture capture) {
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty &&
                  barcodes.first.rawValue != null &&
                  !_isProcessing) {
                _handleScannedData(barcodes.first.rawValue!);
              }
            },
          ),
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.4),
              BlendMode.srcOut,
            ),
            child: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(color: Colors.transparent),
                ),
                Center(
                  child: Container(height: 250, width: 250, color: Colors.red),
                ),
              ],
            ),
          ),
          Center(
            child: Container(
              height: 250,
              width: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: FilledButton.tonal(
                onPressed: () => setState(() => _isScanning = false),
                child: Text(l.pairingCancel),
              ),
            ),
          ),
          if (_isProcessing) const Center(child: CircularProgressIndicator()),
        ],
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.qr_code_scanner_rounded,
              size: 36,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(l.pairingScanPrompt, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: () => setState(() => _isScanning = true),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: Text(l.pairingStartScan),
          ),
        ],
      ),
    );
  }

  void _showIncomingRequestDialog(PairingState pairingState) {
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final dl = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l.pairingRequestTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dl.pairingRequestFrom(
                  pairingState.remoteDeviceName ?? dl.pairingUnknownDevice,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _verificationCodeBadge(ctx, pairingState.verificationCode ?? ''),
              const SizedBox(height: AppSpacing.sm),
              Text(
                dl.pairingCodeMatch,
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final socketManager = ref
                    .read(connectionFacadeProvider.notifier)
                    .socketManager;
                if (socketManager != null) {
                  final notifier = ref.read(pairingProvider.notifier);
                  await notifier.rejectRequest(socketManager: socketManager);
                }
                if (mounted) {
                  setState(() => _isProcessing = false);
                }
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
              },
              child: Text(l.pairingReject),
            ),
            FilledButton(
              onPressed: () async {
                final socketManager = ref
                    .read(connectionFacadeProvider.notifier)
                    .socketManager;
                if (socketManager != null) {
                  final notifier = ref.read(pairingProvider.notifier);
                  final scannerInfo = notifier.pendingScannerInfo ?? {};
                  final status = ref.read(connectionStatusProvider);
                  final myIp = status.localIp ?? '';
                  await notifier.acceptRequest(
                    socketManager: socketManager,
                    scannerInfo: scannerInfo,
                    myIp: myIp,
                  );
                  await ref.read(connectionFacadeProvider.notifier).refresh();
                }
                // acceptRequest now waits for the scanner's ack before
                // committing (see pairing_provider.dart) -- it can come back
                // with an errorCode if that ack never arrived, so this can
                // no longer unconditionally claim success.
                final latest = ref.read(pairingProvider);
                final errorCode = latest.errorCode;
                final succeeded = socketManager != null && errorCode == null;
                if (mounted) {
                  setState(() => _isProcessing = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        succeeded
                            ? l.pairingPairedWith(
                                pairingState.remoteDeviceName ??
                                    l.pairingUnknownDevice,
                              )
                            : (errorCode == null
                                  ? l.pairingInvalidQr
                                  : pairingErrorText(
                                      l,
                                      errorCode,
                                      latest.errorDetail,
                                    )),
                      ),
                      backgroundColor: succeeded
                          ? Theme.of(context).status.success
                          : Theme.of(context).colorScheme.error,
                    ),
                  );
                }
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
                if (succeeded) {
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (mounted) Navigator.of(context).pop();
                  });
                }
              },
              child: Text(l.pairingConfirm),
            ),
          ],
        );
      },
    );
  }

  void _handleScannedData(String data) async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);
    final l = AppLocalizations.of(context);

    final parts = data.split('|');
    // QR format: id|ip|port|key|deviceName|role|publicKey (7 parts)
    // Backward compatible: old format had 4-6 parts (no publicKey)
    if (parts.length < 4) {
      setState(() {
        _isProcessing = false;
        _isScanning = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.pairingInvalidQr)));
      return;
    }

    final scannedId = parts[0];
    final scannedIp = parts[1];
    final scannedPort = int.tryParse(parts[2]) ?? 45678;
    final scannedKey = parts[3];

    final hasRole =
        parts.length >= 6 && (parts.last == 'source' || parts.last == 'main');
    final hasPublicKey = parts.length >= 7;

    final scannedPublicKey = hasPublicKey ? parts[parts.length - 1] : '';
    final scannedName = hasPublicKey
        ? parts.sublist(4, parts.length - 2).join('|')
        : (hasRole
              ? parts.sublist(4, parts.length - 1).join('|')
              : (parts.length > 4
                    ? parts.sublist(4).join('|')
                    : l.pairingUnknownDevice));

    final myPeer = ref.read(peerProvider);
    if (myPeer == null) {
      setState(() {
        _isProcessing = false;
        _isScanning = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.pairingSelectRoleFirst)));
      return;
    }

    final myRole = myPeer.role; // 'main' or 'source'

    final verificationCode = PeerNotifier.generateVerificationCode(
      scannedKey,
      scannedId,
    );

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final dl = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(dl.pairingConfirmTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(dl.pairingConfirmBody(scannedName)),
              const SizedBox(height: AppSpacing.md),
              _verificationCodeBadge(ctx, verificationCode),
              const SizedBox(height: AppSpacing.sm),
              Text(
                dl.pairingCodeMatch,
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _isProcessing = false;
                  _isScanning = false;
                });
                Navigator.of(ctx).pop(false);
              },
              child: Text(dl.pairingCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(dl.pairingConfirm),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    // Send pairing request via PairingNotifier.
    final myPublicKey = await KeyStore.ensureDeviceKeyPair();
    final status = ref.read(connectionStatusProvider);
    final myIp = status.localIp ?? '';

    await ref
        .read(pairingProvider.notifier)
        .sendRequest(
          scannedId: scannedId,
          scannedIp: scannedIp,
          scannedPort: scannedPort,
          scannedKeyBase64: scannedKey,
          scannedDeviceName: scannedName,
          scannedPublicKey: scannedPublicKey,
          myDeviceName: myPeer.deviceName,
          myPeerId: myPeer.id,
          myRole: myRole,
          myPublicKey: myPublicKey,
          myIp: myIp,
        );

    await ref.read(connectionFacadeProvider.notifier).refresh();

    if (!mounted) return;
    final pairingState = ref.read(pairingProvider);
    if (pairingState.errorCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.pairingPairedWith(scannedName)),
          backgroundColor: Theme.of(context).status.success,
        ),
      );
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        setState(() {
          _isScanning = false;
          _isProcessing = false;
        });
        Navigator.pop(context);
      });
    } else {
      setState(() {
        _isScanning = false;
        _isProcessing = false;
      });
    }
  }
}
