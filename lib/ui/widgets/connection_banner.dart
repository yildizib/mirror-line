import 'package:flutter/material.dart';

import '../theme.dart';

class ConnectionBanner extends StatelessWidget {
  final bool isConnected;

  const ConnectionBanner({required this.isConnected, super.key});

  @override
  Widget build(BuildContext context) {
    final status = Theme.of(context).status;

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: isConnected
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: status.warningContainer,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(
                children: [
                  Icon(Icons.wifi_off_rounded, size: 18, color: status.onWarningContainer),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Bağlantı yok. Eş cihaz aranıyor; aynı WiFi ağında olduğunuzdan emin olun.',
                      style: TextStyle(
                        fontSize: 13,
                        color: status.onWarningContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
