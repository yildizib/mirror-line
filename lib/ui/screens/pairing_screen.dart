import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../data/models/peer.dart';
import '../../providers/connection_provider.dart';
import '../../providers/pairing_provider.dart';
import '../../providers/peer_provider.dart';
import '../../security/key_store.dart';
import '../theme.dart';
import '../widgets/qr_display.dart';
import 'role_selection_screen.dart';

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
    });
  }

  @override
  Widget build(BuildContext context) {
    final peer = ref.watch(peerProvider);
    final pairingState = ref.watch(pairingProvider);

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
          title: const Text('Cihaz Eşleştir'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'QR Göster', icon: Icon(Icons.qr_code_rounded)),
              Tab(text: 'QR Tara', icon: Icon(Icons.qr_code_scanner_rounded)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildShowQrTab(_cachedPeerForQr, pairingState),
            _buildScanTab(pairingState),
          ],
        ),
      ),
    );
  }

  Widget _buildShowQrTab(Peer? peer, PairingState pairingState) {
    final theme = Theme.of(context);

    if (peer == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Önce rol seçimi yapmalısınız.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
                ),
                child: const Text('Rol Seç'),
              ),
            ],
          ),
        ),
      );
    }

    // QR format: id|ip|port|key|deviceName|role|publicKey
    // publicKey here is THIS device's Ed25519 public key (from KeyStore),
    // NOT the peer's publicKey field (which is the other device's key).
    final myPub = _myPublicKey ?? '';
    final qrData =
        '${peer.id}|${peer.ip}|${peer.port}|${peer.key}|${peer.deviceName}|${peer.role}|$myPub';

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
              'Diğer telefon bu QR kodu taratsın.',
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
                        'Eşleşme isteği alındı!',
                        style: TextStyle(color: theme.status.onSuccessContainer),
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
    return Column(
      children: [
        Text(
          'DOĞRULAMA KODU',
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
    // Show waiting state while handshake is in progress.
    if (pairingState.isWaitingForAccept) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              '${pairingState.remoteDeviceName ?? "Cihaz"} ile eşleşme bekleniyor...',
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (pairingState.verificationCode != null)
              Column(
                children: [
                  _verificationCodeBadge(context, pairingState.verificationCode!),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Kod her iki cihazda aynı olmalı.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: () => ref.read(pairingProvider.notifier).reset(),
              child: const Text('İptal'),
            ),
          ],
        ),
      );
    }

    // Show error if any.
    if (pairingState.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              pairingState.errorMessage!,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () {
                ref.read(pairingProvider.notifier).reset();
                setState(() {});
              },
              child: const Text('Tekrar Dene'),
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
                  decoration: const BoxDecoration(
                    color: Colors.transparent,
                  ),
                ),
                Center(
                  child: Container(
                    height: 250,
                    width: 250,
                    color: Colors.red,
                  ),
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
                child: const Text('İptal'),
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
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.qr_code_scanner_rounded,
              size: 36,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Diğer cihazın QR kodunu tarayın',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: () => setState(() => _isScanning = true),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Taramayı Başlat'),
          ),
        ],
      ),
    );
  }

  void _showIncomingRequestDialog(PairingState pairingState) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Eşleşme İsteği'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${pairingState.remoteDeviceName ?? "Bilinmeyen Cihaz"} cihazı ile eşleşmek istiyor.',
            ),
            const SizedBox(height: AppSpacing.md),
            _verificationCodeBadge(ctx, pairingState.verificationCode ?? ''),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Kod her iki cihazda aynı olmalı.',
              style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final socketManager =
                  ref.read(connectionProvider.notifier).socketManager;
              if (socketManager != null) {
                final notifier = ref.read(pairingProvider.notifier);
                await notifier.rejectRequest(socketManager: socketManager);
              }
              if (mounted) {
                setState(() => _isProcessing = false);
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Reddet'),
          ),
          FilledButton(
            onPressed: () async {
              final socketManager =
                  ref.read(connectionProvider.notifier).socketManager;
              if (socketManager != null) {
                final notifier = ref.read(pairingProvider.notifier);
                final scannerInfo = notifier.pendingScannerInfo ?? {};
                await notifier.acceptRequest(
                  socketManager: socketManager,
                  scannerInfo: scannerInfo,
                );
                await ref.read(connectionProvider.notifier).refresh();
              }
              if (mounted) {
                setState(() => _isProcessing = false);
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        '${pairingState.remoteDeviceName ?? "Cihaz"} ile eşleştirildi!'),
                    backgroundColor: Theme.of(context).status.success,
                  ),
                );
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (mounted) Navigator.of(context).pop();
                });
              }
            },
            child: const Text('Onayla'),
          ),
        ],
      ),
    );
  }

  void _handleScannedData(String data) async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    final parts = data.split('|');
    // QR format: id|ip|port|key|deviceName|role|publicKey (7 parts)
    // Backward compatible: old format had 4-6 parts (no publicKey)
    if (parts.length < 4) {
      setState(() {
        _isProcessing = false;
        _isScanning = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçersiz QR kod formatı')),
      );
      return;
    }

    final scannedId = parts[0];
    final scannedIp = parts[1];
    final scannedPort = int.tryParse(parts[2]) ?? 45678;
    final scannedKey = parts[3];

    final hasRole = parts.length >= 6 && (parts.last == 'source' || parts.last == 'main');
    final hasPublicKey = parts.length >= 7;

    final scannedPublicKey = hasPublicKey ? parts[parts.length - 1] : '';
    final scannedName = hasPublicKey
        ? parts.sublist(4, parts.length - 2).join('|')
        : (hasRole
            ? parts.sublist(4, parts.length - 1).join('|')
            : (parts.length > 4 ? parts.sublist(4).join('|') : 'Bilinmeyen Cihaz'));

    final myPeer = ref.read(peerProvider);
    if (myPeer == null) {
      setState(() {
        _isProcessing = false;
        _isScanning = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce rol seçimi yapmalısınız')),
      );
      return;
    }

    final myRole = myPeer.role; // 'main' or 'source'

    final verificationCode =
        PeerNotifier.generateVerificationCode(scannedKey, scannedId);

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Eşleşmeyi Onayla'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$scannedName cihazı ile eşleşeceksiniz.'),
            const SizedBox(height: AppSpacing.md),
            _verificationCodeBadge(ctx, verificationCode),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Kod her iki cihazda aynı olmalı.',
              style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
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
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Onayla'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    // Send pairing request via PairingNotifier.
    final myPublicKey = await KeyStore.ensureDeviceKeyPair();

    await ref.read(pairingProvider.notifier).sendRequest(
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
        );

    await ref.read(connectionProvider.notifier).refresh();

    if (!mounted) return;
    final pairingState = ref.read(pairingProvider);
    if (pairingState.errorMessage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$scannedName ile eşleştirildi!'),
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