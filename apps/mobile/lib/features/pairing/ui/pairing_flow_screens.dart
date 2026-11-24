import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:qr_flutter/qr_flutter.dart';

enum PairingRole { main, source }

enum PairingPhase {
  checking,
  failed,
  active,
  expiring,
  expired,
  refreshing,
  denied,
  unavailable,
  invalid,
  submitting,
  connected,
  mainUnavailable,
  genericFailure,
  rejected,
  timedOut,
  quotaChanged,
  waitingProof,
  comparisonRequired,
  verified,
  securityFailed,
}

class PairingCopy {
  const PairingCopy(this.tr);
  factory PairingCopy.of(BuildContext context) =>
      PairingCopy(Localizations.localeOf(context).languageCode == 'tr');
  final bool tr;
  String get devices => tr ? 'Cihazlar' : 'Devices';
  String get add => tr ? 'Kaynak Telefon ekle' : 'Add Source Phone';
  String count(int c, int m) =>
      tr ? '$c / $m Kaynak Telefon' : '$c / $m Source Phones';
  String get checking => tr
      ? 'Eşleştirme uygunluğu kontrol ediliyor…'
      : 'Checking pairing availability…';
  String get unavailable => tr
      ? 'Eşleştirme şu anda başlatılamıyor.'
      : 'Pairing can’t be started right now.';
  String get limitTitle =>
      tr ? 'Cihaz sınırına ulaştın' : 'You’ve reached the device limit';
  String get limitBody => tr
      ? 'Yeni bir Kaynak eklemek için önce mevcut Kaynaklardan birinin bağlantısını kaldır.'
      : 'Remove an existing Source before adding a new one.';
  String get manage => tr ? 'Cihazları yönet' : 'Manage devices';
  String get introTitle =>
      tr ? 'Kaynak Telefonunu hazırla' : 'Get your Source Phone ready';
  String get introBody => tr
      ? 'Kaynak Telefonda MirrorLine’ı aç, Kaynak Telefon rolünü seç ve bu kodu tara.'
      : 'Open MirrorLine on the Source Phone, choose Source Phone, and scan this code.';
  String get scan => tr ? 'QR kodu tara' : 'Scan QR code';
  String get manual => tr ? 'Kodu elle gir' : 'Enter code manually';
  String expires(String time) =>
      tr ? 'Kod $time içinde sona erecek' : 'Code expires in $time';
  String get refresh => tr ? 'Yeni kod oluştur' : 'Generate new code';
  String get cancel => tr ? 'Vazgeç' : 'Cancel';
  String get back => tr ? 'Geri' : 'Back';
  String get invalid => tr
      ? 'Kod geçersiz veya süresi dolmuş. Ana Telefonda yeni bir kod oluştur.'
      : 'This code is invalid or expired. Generate a new code on the Main Phone.';
  String get compare => tr ? 'Kodları karşılaştır' : 'Compare the codes';
  String get compareBody => tr
      ? 'Her iki telefonda da aynı kodun göründüğünden emin ol.'
      : 'Make sure the same code appears on both phones.';
  String get matches => tr ? 'Kodlar eşleşiyor' : 'Codes match';
  String get mismatch => tr ? 'Kodlar eşleşmiyor' : 'Codes don’t match';
  String get success => tr ? 'Kaynak Telefon eklendi' : 'Source Phone added';
  String get failed =>
      tr ? 'Eşleştirme tamamlanamadı.' : 'Pairing couldn’t be completed.';
  String get retry => tr ? 'Tekrar dene' : 'Try again';
  String get remove =>
      tr ? 'Mevcut bağlantıyı kaldır' : 'Remove current connection';
  String get already => tr
      ? 'Bu Kaynak zaten bir Ana Telefona bağlı'
      : 'This Source is already connected to a Main Phone';
  String get alreadyBody => tr
      ? 'Yeni bir Ana ile eşleştirmeden önce mevcut bağlantıyı kaldır.'
      : 'Remove the current connection before pairing with a new Main.';
  String get password => tr ? 'Parola' : 'Password';
  String get confirm => tr ? 'Onayla' : 'Confirm';
  String get done => tr ? 'Tamam' : 'Done';
  String get security =>
      tr ? 'Eşleştirme güvenlik durumu' : 'Pairing security status';
  String get privacy => tr
      ? 'Eşleştirme sırasında iki telefonu karşılaştırarak doğrularsın.'
      : 'During pairing, you confirm the two phones by comparing them.';
  String get generatingCode =>
      tr ? 'Yeni kod oluşturuluyor…' : 'Generating a new code…';
  String get pairingCode => tr ? 'Eşleştirme kodu' : 'Pairing code';
  String get transferCodeHint => tr
      ? 'Ana Telefonda gösterilen 10 karakterli kodu gir.'
      : 'Enter the 10-character code shown on the Main Phone.';
  String transferProgress(int entered) => tr
      ? '$entered / 10 karakter girildi'
      : '$entered / 10 characters entered';
  String roleContext(PairingRole role) => role == PairingRole.main
      ? (tr ? 'Ana Telefonundaki kod' : 'Code on this Main Phone')
      : (tr ? 'Kaynak Telefonundaki kod' : 'Code on this Source Phone');
}

class PairingPage extends StatelessWidget {
  const PairingPage({required this.title, required this.children, super.key});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 24),
                ...children,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class PairingMessage extends StatelessWidget {
  const PairingMessage({
    required this.text,
    this.warning = false,
    this.success = false,
    super.key,
  });
  final String text;
  final bool warning;
  final bool success;
  @override
  Widget build(BuildContext context) {
    final status = Theme.of(context).status;
    final scheme = Theme.of(context).colorScheme;
    final bg = success
        ? status.successContainer
        : warning
        ? status.warningContainer
        : scheme.errorContainer;
    final fg = success
        ? status.onSuccessContainer
        : warning
        ? status.onWarningContainer
        : scheme.onErrorContainer;
    final icon = success
        ? Icons.check_circle_outline
        : warning
        ? Icons.info_outline
        : Icons.error_outline;
    return Semantics(
      liveRegion: true,
      label: text,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: TextStyle(color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}

class SourceListScreen extends StatelessWidget {
  const SourceListScreen({
    required this.current,
    required this.maximum,
    required this.phase,
    required this.onAdd,
    required this.onManage,
    super.key,
  });
  final int current;
  final int maximum;
  final PairingPhase phase;
  final VoidCallback onAdd;
  final VoidCallback onManage;
  @override
  Widget build(BuildContext context) {
    final c = PairingCopy.of(context);
    final limited = current >= maximum;
    return PairingPage(
      title: c.devices,
      children: [
        Text(
          c.count(current, maximum),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        if (phase == PairingPhase.unavailable)
          PairingMessage(text: c.unavailable, warning: true),
        if (limited) PairingMessage(text: c.limitBody, warning: true),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: phase == PairingPhase.unavailable || limited
              ? null
              : onAdd,
          child: Text(c.add),
        ),
        TextButton(onPressed: onManage, child: Text(c.manage)),
      ],
    );
  }
}

class PairingEligibilityScreen extends StatelessWidget {
  const PairingEligibilityScreen({
    required this.phase,
    required this.onRetry,
    super.key,
  });
  final PairingPhase phase;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final c = PairingCopy.of(context);
    return PairingPage(
      title: c.devices,
      children: [
        if (phase == PairingPhase.checking)
          ...List.generate(3, (_) => const _Skeleton())
        else ...[
          PairingMessage(text: c.unavailable),
          FilledButton(onPressed: onRetry, child: Text(c.retry)),
        ],
      ],
    );
  }
}

class PairingLimitScreen extends StatelessWidget {
  const PairingLimitScreen({required this.onManage, super.key});
  final VoidCallback onManage;
  @override
  Widget build(BuildContext context) {
    final c = PairingCopy.of(context);
    return PairingPage(
      title: c.limitTitle,
      children: [
        Text(c.limitBody),
        const SizedBox(height: 24),
        FilledButton(onPressed: onManage, child: Text(c.manage)),
      ],
    );
  }
}

class PairingIntroductionScreen extends StatelessWidget {
  const PairingIntroductionScreen({required this.onContinue, super.key});
  final VoidCallback onContinue;
  @override
  Widget build(BuildContext context) {
    final c = PairingCopy.of(context);
    return PairingPage(
      title: c.introTitle,
      children: [
        Text(c.introBody),
        const SizedBox(height: 12),
        Text(c.privacy),
        const SizedBox(height: 24),
        FilledButton(onPressed: onContinue, child: Text(c.confirm)),
      ],
    );
  }
}

class MainPairingCodeScreen extends StatelessWidget {
  const MainPairingCodeScreen({
    required this.payload,
    required this.code,
    required this.remaining,
    required this.phase,
    required this.onRefresh,
    required this.onCancel,
    super.key,
  });
  final String payload;
  final String code;
  final String remaining;
  final PairingPhase phase;
  final VoidCallback onRefresh;
  final VoidCallback onCancel;
  @override
  Widget build(BuildContext context) {
    final c = PairingCopy.of(context);
    final expired = phase == PairingPhase.expired;
    final refreshing = phase == PairingPhase.refreshing;
    return PairingPage(
      title: c.introTitle,
      children: [
        if (expired)
          PairingMessage(text: c.invalid, warning: true)
        else if (refreshing)
          Semantics(
            liveRegion: true,
            label: c.generatingCode,
            child: const _CodeSkeleton(),
          )
        else
          Semantics(
            label: c.scan,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: QrImageView(data: payload, size: 200),
            ),
          ),
        const SizedBox(height: 16),
        if (!expired && !refreshing)
          Semantics(
            label: _formatTransferCode(code),
            child: ExcludeSemantics(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _formatTransferCode(code),
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(letterSpacing: 3),
                ),
              ),
            ),
          ),
        if (!expired && !refreshing) const SizedBox(height: 8),
        if (phase == PairingPhase.expiring)
          PairingMessage(text: c.expires(remaining), warning: true)
        else if (expired || refreshing)
          const SizedBox.shrink()
        else
          Text(c.expires(remaining), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: refreshing ? null : onRefresh,
          child: refreshing
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(c.refresh),
        ),
        TextButton(onPressed: onCancel, child: Text(c.cancel)),
      ],
    );
  }
}

class SourceScannerScreen extends StatelessWidget {
  const SourceScannerScreen({
    required this.phase,
    required this.onScan,
    required this.onManual,
    required this.onBack,
    super.key,
  });
  final PairingPhase phase;
  final VoidCallback onScan;
  final VoidCallback onManual;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) {
    final c = PairingCopy.of(context);
    final ready = phase == PairingPhase.active;
    final message = phase == PairingPhase.denied
        ? (c.tr
              ? 'Kameraya izin verilmedi. Kodu elle girebilirsin.'
              : 'Camera permission was not granted. You can enter the code manually.')
        : (c.tr
              ? 'Tarayıcı bu cihazda kullanılamıyor.'
              : 'The scanner is unavailable on this device.');
    return PairingPage(
      title: c.scan,
      children: [
        if (ready)
          Container(
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Semantics(
              label: c.scan,
              child: const Center(child: Icon(Icons.qr_code_scanner, size: 80)),
            ),
          )
        else
          PairingMessage(text: message, warning: true),
        const SizedBox(height: 16),
        FilledButton(onPressed: ready ? onScan : null, child: Text(c.scan)),
        OutlinedButton(onPressed: onManual, child: Text(c.manual)),
        TextButton(onPressed: onBack, child: Text(c.back)),
      ],
    );
  }
}

class ManualCodeScreen extends StatefulWidget {
  const ManualCodeScreen({
    required this.phase,
    required this.onSubmit,
    required this.onBack,
    super.key,
  });
  final PairingPhase phase;
  final ValueChanged<String> onSubmit;
  final VoidCallback onBack;
  @override
  State<ManualCodeScreen> createState() => _ManualCodeScreenState();
}

class _ManualCodeScreenState extends State<ManualCodeScreen> {
  static const _codeLength = 10;
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PairingCopy.of(context);
    final busy = widget.phase == PairingPhase.submitting;
    final ready = controller.text.length == _codeLength;
    return PairingPage(
      title: c.manual,
      children: [
        if (widget.phase == PairingPhase.invalid ||
            widget.phase == PairingPhase.expired)
          PairingMessage(text: c.invalid, warning: true),
        const SizedBox(height: 12),
        Text(c.pairingCode),
        const SizedBox(height: 4),
        Text(c.transferCodeHint),
        const SizedBox(height: 8),
        Semantics(
          label: c.pairingCode,
          value: c.transferProgress(controller.text.length),
          textField: true,
          child: Stack(
            alignment: Alignment.center,
            children: [
              IgnorePointer(
                child: LayoutBuilder(
                  builder: (context, constraints) => Row(
                    children: [
                      for (var index = 0; index < _codeLength; index++) ...[
                        if (index == 5) const SizedBox(width: 8),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: index == 4 || index == 9 ? 0 : 3,
                            ),
                            child: KeyedSubtree(
                              key: ValueKey('pairing-code-segment-$index'),
                              child: _CodeSegment(
                                value: index < controller.text.length
                                    ? controller.text[index]
                                    : '',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              TextField(
                controller: controller,
                enabled: !busy,
                keyboardType: TextInputType.text,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  const _TransferCodeFormatter(),
                  LengthLimitingTextInputFormatter(_codeLength),
                ],
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.done,
                style: const TextStyle(color: Colors.transparent),
                cursorColor: Colors.transparent,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy || !ready
              ? null
              : () => widget.onSubmit(controller.text),
          child: busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(c.confirm),
        ),
        TextButton(onPressed: widget.onBack, child: Text(c.cancel)),
      ],
    );
  }
}

class InvalidPairingCodeScreen extends StatelessWidget {
  const InvalidPairingCodeScreen({
    required this.phase,
    required this.onNewCode,
    required this.onCancel,
    super.key,
  });
  final PairingPhase phase;
  final VoidCallback onNewCode;
  final VoidCallback onCancel;
  @override
  Widget build(BuildContext context) {
    final c = PairingCopy.of(context);
    return PairingPage(
      title: c.failed,
      children: [
        PairingMessage(
          text: phase == PairingPhase.expired
              ? c.invalid
              : (c.tr ? 'Kod geçersiz.' : 'This code is invalid.'),
          warning: true,
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onNewCode, child: Text(c.refresh)),
        TextButton(onPressed: onCancel, child: Text(c.cancel)),
      ],
    );
  }
}

class VerificationComparisonScreen extends StatelessWidget {
  const VerificationComparisonScreen({
    required this.role,
    required this.code,
    required this.onMatch,
    required this.onMismatch,
    super.key,
  });
  final PairingRole role;
  final String code;
  final VoidCallback onMatch;
  final VoidCallback onMismatch;
  @override
  Widget build(BuildContext context) {
    final c = PairingCopy.of(context);
    final comparisonCode = _formatComparisonCode(code);
    return PairingPage(
      title: c.compare,
      children: [
        Text(c.compareBody),
        const SizedBox(height: 24),
        Semantics(
          container: true,
          label: c.roleContext(role),
          child: Text(
            c.roleContext(role),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 12),
        Semantics(
          container: true,
          label: comparisonCode,
          child: ExcludeSemantics(
            child: Text(
              comparisonCode,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(letterSpacing: 5),
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: onMatch, child: Text(c.matches)),
        OutlinedButton(onPressed: onMismatch, child: Text(c.mismatch)),
      ],
    );
  }
}

class ReviewSourceScreen extends StatelessWidget {
  const ReviewSourceScreen({
    required this.sourceName,
    required this.deviceLabel,
    required this.submitting,
    required this.onConfirm,
    super.key,
  });
  final String sourceName;
  final String deviceLabel;
  final bool submitting;
  final VoidCallback onConfirm;
  @override
  Widget build(BuildContext context) {
    final c = PairingCopy.of(context);
    return PairingPage(
      title: c.tr ? 'Kaynak Telefonu incele' : 'Review Source Phone',
      children: [
        Text(sourceName, style: Theme.of(context).textTheme.titleLarge),
        Text(deviceLabel),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: submitting ? null : onConfirm,
          child: submitting
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(c.confirm),
        ),
      ],
    );
  }
}

class PairingSuccessScreen extends StatelessWidget {
  const PairingSuccessScreen({
    required this.role,
    required this.sourceName,
    required this.onNext,
    super.key,
  });
  final PairingRole role;
  final String sourceName;
  final VoidCallback onNext;
  @override
  Widget build(BuildContext context) {
    final c = PairingCopy.of(context);
    return PairingPage(
      title: c.success,
      children: [
        PairingMessage(text: '$sourceName — ${c.success}', success: true),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: onNext,
          child: Text(
            role == PairingRole.source
                ? (c.tr ? 'İzinleri ayarla' : 'Set up permissions')
                : (c.tr ? 'Cihazları görüntüle' : 'View devices'),
          ),
        ),
      ],
    );
  }
}

class PairingFailureScreen extends StatelessWidget {
  const PairingFailureScreen({
    required this.phase,
    required this.onRetry,
    required this.onCancel,
    required this.onManage,
    super.key,
  });
  final PairingPhase phase;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final VoidCallback onManage;
  @override
  Widget build(BuildContext context) {
    final c = PairingCopy.of(context);
    final quota = phase == PairingPhase.quotaChanged;
    final reason = quota
        ? c.limitBody
        : phase == PairingPhase.rejected
        ? (c.tr ? 'Eşleştirme reddedildi.' : 'Pairing was rejected.')
        : phase == PairingPhase.timedOut
        ? (c.tr ? 'Eşleştirme zaman aşımına uğradı.' : 'Pairing timed out.')
        : c.failed;
    return PairingPage(
      title: c.failed,
      children: [
        PairingMessage(text: reason),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: quota ? onManage : onRetry,
          child: Text(quota ? c.manage : c.retry),
        ),
        TextButton(onPressed: onCancel, child: Text(c.cancel)),
      ],
    );
  }
}

class AlreadyPairedScreen extends StatelessWidget {
  const AlreadyPairedScreen({
    required this.phase,
    required this.onRemove,
    super.key,
  });
  final PairingPhase phase;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) {
    final c = PairingCopy.of(context);
    final body = phase == PairingPhase.mainUnavailable
        ? (c.tr
              ? 'Mevcut Ana Telefon şu anda kullanılamıyor. Yeni eşleştirme başlatılamaz.'
              : 'The current Main Phone is unavailable. A new pairing cannot start.')
        : c.alreadyBody;
    return PairingPage(
      title: c.already,
      children: [
        Text(body),
        const SizedBox(height: 20),
        FilledButton(onPressed: onRemove, child: Text(c.remove)),
      ],
    );
  }
}

class RemoveMainWarningScreen extends StatelessWidget {
  const RemoveMainWarningScreen({
    required this.onContinue,
    required this.onCancel,
    super.key,
  });
  final VoidCallback onContinue;
  final VoidCallback onCancel;
  @override
  Widget build(BuildContext context) {
    final c = PairingCopy.of(context);
    return PairingPage(
      title: c.remove,
      children: [
        Text(
          c.tr
              ? 'Bu bağlantıyı kaldırdıktan sonra yeni bir Ana Telefonla eşleştirebilirsin.'
              : 'After removing this connection, you can pair with a new Main Phone.',
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: onContinue, child: Text(c.remove)),
        TextButton(onPressed: onCancel, child: Text(c.cancel)),
      ],
    );
  }
}

class UnpairReauthenticationScreen extends StatefulWidget {
  const UnpairReauthenticationScreen({
    required this.phase,
    required this.onConfirm,
    super.key,
  });
  final PairingPhase phase;
  final ValueChanged<String> onConfirm;
  @override
  State<UnpairReauthenticationScreen> createState() =>
      _UnpairReauthenticationScreenState();
}

class _UnpairReauthenticationScreenState
    extends State<UnpairReauthenticationScreen> {
  final controller = TextEditingController();
  bool hidden = true;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PairingCopy.of(context);
    final busy = widget.phase == PairingPhase.submitting;
    return PairingPage(
      title: c.remove,
      children: [
        if (widget.phase == PairingPhase.failed) PairingMessage(text: c.failed),
        Text(c.password),
        TextField(
          controller: controller,
          obscureText: hidden,
          decoration: InputDecoration(
            suffixIcon: IconButton(
              tooltip: hidden
                  ? (c.tr ? 'Parolayı göster' : 'Show password')
                  : (c.tr ? 'Parolayı gizle' : 'Hide password'),
              onPressed: () => setState(() => hidden = !hidden),
              icon: Icon(
                hidden
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : () => widget.onConfirm(controller.text),
          child: busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(c.remove),
        ),
      ],
    );
  }
}

class ConnectionRemovedScreen extends StatelessWidget {
  const ConnectionRemovedScreen({required this.onStartNew, super.key});
  final VoidCallback onStartNew;
  @override
  Widget build(BuildContext context) {
    final c = PairingCopy.of(context);
    return PairingPage(
      title: c.tr ? 'Bağlantı kaldırıldı' : 'Connection removed',
      children: [
        PairingMessage(
          text: c.tr
              ? 'Bu Kaynak artık yeni eşleştirmeye hazır.'
              : 'This Source is ready for a new pairing.',
          success: true,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: onStartNew,
          child: Text(c.tr ? 'Yeni eşleştirme başlat' : 'Start new pairing'),
        ),
      ],
    );
  }
}

class PairingSecurityStatusScreen extends StatelessWidget {
  const PairingSecurityStatusScreen({
    required this.phase,
    required this.onContinue,
    required this.onCancel,
    this.onRetry,
    super.key,
  });
  final PairingPhase phase;
  final VoidCallback onContinue;
  final VoidCallback onCancel;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final c = PairingCopy.of(context);
    final text = phase == PairingPhase.waitingProof
        ? (c.tr
              ? 'Telefonların doğrulama bilgileri bekleniyor.'
              : 'Waiting for the phones to provide verification information.')
        : phase == PairingPhase.comparisonRequired
        ? (c.tr
              ? 'Her iki telefondaki kodu karşılaştırman gerekiyor.'
              : 'Compare the code shown on both phones.')
        : phase == PairingPhase.verified
        ? (c.tr ? 'Karşılaştırma doğrulandı.' : 'The comparison was verified.')
        : (c.tr
              ? 'Güvenlik doğrulaması tamamlanamadı.'
              : 'The security check could not be completed.');
    return PairingPage(
      title: c.security,
      children: [
        PairingMessage(
          text: text,
          success: phase == PairingPhase.verified,
          warning: phase == PairingPhase.comparisonRequired,
        ),
        const SizedBox(height: 20),
        if (phase == PairingPhase.comparisonRequired ||
            phase == PairingPhase.verified)
          FilledButton(onPressed: onContinue, child: Text(c.confirm))
        else if (phase == PairingPhase.securityFailed)
          FilledButton(onPressed: onRetry ?? onContinue, child: Text(c.retry)),
        TextButton(onPressed: onCancel, child: Text(c.cancel)),
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) => Semantics(
    label: PairingCopy.of(context).checking,
    child: Container(
      height: 64,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
    ),
  );
}

class _CodeSkeleton extends StatelessWidget {
  const _CodeSkeleton();
  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 232,
    child: Center(child: CircularProgressIndicator()),
  );
}

class _CodeSegment extends StatelessWidget {
  const _CodeSegment({required this.value});
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    height: 56,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outline),
      borderRadius: BorderRadius.circular(10),
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(value, style: Theme.of(context).textTheme.titleLarge),
    ),
  );
}

class _TransferCodeFormatter extends TextInputFormatter {
  const _TransferCodeFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = newValue.text
        .toUpperCase()
        .split('')
        .where(_transferCodeAlphabet.contains)
        .take(10)
        .join();
    return TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }
}

const _transferCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

String _formatTransferCode(String code) {
  final normalized = code
      .toUpperCase()
      .split('')
      .where(_transferCodeAlphabet.contains)
      .take(10)
      .join();
  return normalized.length == 10
      ? '${normalized.substring(0, 5)} ${normalized.substring(5)}'
      : normalized;
}

String _formatComparisonCode(String code) {
  final digits = code.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length == 6
      ? '${digits.substring(0, 3)} ${digits.substring(3)}'
      : digits;
}
