import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../data/models/peer.dart';
import '../../providers/connection_provider.dart';
import '../../providers/pairing_provider.dart';
import '../../providers/peer_provider.dart';
import '../../security/key_store.dart';
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
              Tab(text: 'QR Göster', icon: Icon(Icons.qr_code)),
              Tab(text: 'QR Tara', icon: Icon(Icons.qr_code_scanner)),
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
    if (peer == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Önce rol seçimi yapmalısınız.'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
              ),
              child: const Text('Rol Seç'),
            ),
          ],
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          QrDisplay(data: qrData),
          const SizedBox(height: 16),
          Text(
            'Doğrulama Kodu: ${peer.verificationCode}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('Diğer telefon bu QR kodu taratsın.'),
          const SizedBox(height: 16),
          if (pairingState.isShowingRequest)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Eşleşme isteği alındı!'),
                  ],
                ),
              ),
            ),
        ],
      ),
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
                  const Text('Doğrulama Kodu:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    pairingState.verificationCode!,
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4),
                  ),
                  const SizedBox(height: 8),
                  const Text('Kod her iki cihazda aynı olmalı.'),
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
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              pairingState.errorMessage!,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
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
          Icon(Icons.qr_code_scanner, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'Diğer cihazın QR kodunu tarayın',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => setState(() => _isScanning = true),
            icon: const Icon(Icons.qr_code_scanner),
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
            const SizedBox(height: 16),
            const Text('Doğrulama Kodu:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              pairingState.verificationCode ?? '',
              style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 4),
            ),
            const SizedBox(height: 8),
            const Text('Kod her iki cihazda aynı olmalı.'),
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
                    backgroundColor: Colors.green,
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
            const SizedBox(height: 16),
            const Text('Doğrulama Kodu:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              verificationCode,
              style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 4),
            ),
            const SizedBox(height: 8),
            const Text('Kod her iki cihazda aynı olmalı.'),
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
          backgroundColor: Colors.green,
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