import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../data/models/peer.dart';
import '../../providers/connection_provider.dart';
import '../../providers/peer_provider.dart';
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

  @override
  void initState() {
    super.initState();
    // Make sure the QR displays the current local IP.
    Future.microtask(() => ref.read(peerProvider.notifier).refreshLocalIp());
  }

  @override
  Widget build(BuildContext context) {
    final peer = ref.watch(peerProvider);

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
            _buildShowQrTab(peer),
            _buildScanTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildShowQrTab(Peer? peer) {
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

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          QrDisplay(data: '${peer.id}|${peer.ip}|${peer.port}|${peer.key}|${peer.deviceName}|${peer.role}'),
          const SizedBox(height: 16),
          const Text('Diğer telefon bu QR kodu taratsın.'),
        ],
      ),
    );
  }

  Widget _buildScanTab() {
    if (_isScanning) {
      return Stack(
        children: [
          MobileScanner(
            onDetect: (BarcodeCapture capture) {
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty && barcodes.first.rawValue != null && !_isProcessing) {
                _handleScannedData(barcodes.first.rawValue!);
              }
            },
          ),
          // Overlay with scan area indicator
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
                    color: Colors.red, // This will be "cut out"
                  ),
                ),
              ],
            ),
          ),
          // Scan frame border
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
          // Cancel button
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
          if (_isProcessing)
            const Center(child: CircularProgressIndicator()),
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

  void _handleScannedData(String data) async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    // Parse scanned QR: id|ip|port|key|deviceName|role(optional)
    final parts = data.split('|');
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
    final scannedRole = hasRole ? parts.last : null;
    final scannedName = hasRole
        ? parts.sublist(4, parts.length - 1).join('|')
        : (parts.length > 4 ? parts.sublist(4).join('|') : 'Bilinmeyen Cihaz');

    // This device takes the OPPOSITE role of the scanned device so that
    // exactly one of the pair ends up as the server, regardless of which
    // phone displayed the QR code.
    final myRole = scannedRole == 'main'
        ? 'source'
        : 'main'; // default: main (client) for old-format QRs

    // Save peer info from scanned QR
    await ref.read(peerProvider.notifier).createPeerFromQr(
      id: scannedId,
      ip: scannedIp,
      port: scannedPort,
      keyBase64: scannedKey,
      role: myRole,
      deviceName: scannedName,
    );

    // Kick off discovery/connection with the newly paired peer.
    await ref.read(connectionProvider.notifier).refresh();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$scannedName ile eşleştirildi!'),
        backgroundColor: Colors.green,
      ),
    );

    // Navigate back to settings after saving
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _isProcessing = false;
      });
      Navigator.pop(context);
    });
  }
}
