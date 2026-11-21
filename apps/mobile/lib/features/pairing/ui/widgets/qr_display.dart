import 'package:flutter/material.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrDisplay extends StatelessWidget {
  final String data;
  final double size;

  const QrDisplay({required this.data, this.size = 220, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // Always white regardless of theme: QR scanners need high
        // contrast, and a dark-mode-tinted background can break scanning.
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: QrImageView(data: data, size: size, backgroundColor: Colors.white),
    );
  }
}
