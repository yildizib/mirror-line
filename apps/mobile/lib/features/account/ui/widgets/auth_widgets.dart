import 'package:flutter/material.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/l10n/app_localizations.dart';

class AuthTextField extends StatefulWidget {
  const AuthTextField({
    required this.controller,
    required this.label,
    this.errorText,
    this.enabled = true,
    this.password = false,
    this.autofillHints,
    this.keyboardType,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? errorText;
  final bool enabled;
  final bool password;
  final Iterable<String>? autofillHints;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final showPassword = widget.password && _obscured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        TextField(
          controller: widget.controller,
          enabled: widget.enabled,
          obscureText: widget.password && _obscured,
          keyboardType: widget.keyboardType,
          autofillHints: widget.autofillHints,
          onChanged: widget.onChanged,
          minLines: 1,
          maxLines: 1,
          decoration: InputDecoration(
            errorText: widget.errorText,
            suffixIcon: widget.password
                ? IconButton(
                    tooltip: showPassword
                        ? l10n.authShowPassword
                        : l10n.authHidePassword,
                    onPressed: widget.enabled
                        ? () => setState(() => _obscured = !_obscured)
                        : null,
                    icon: Icon(
                      showPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

class PasswordRequirements extends StatelessWidget {
  const PasswordRequirements({required this.password, super.key});

  final String password;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PasswordRule(
          label: l10n.passwordLength,
          satisfied: password.length >= 12,
        ),
        _PasswordRule(
          label: l10n.passwordUppercase,
          satisfied: password.contains(RegExp(r'[A-Z]')),
        ),
        _PasswordRule(
          label: l10n.passwordLowercase,
          satisfied: password.contains(RegExp(r'[a-z]')),
        ),
        _PasswordRule(
          label: l10n.passwordNumber,
          satisfied: password.contains(RegExp(r'[0-9]')),
        ),
      ],
    );
  }
}

class _PasswordRule extends StatelessWidget {
  const _PasswordRule({required this.label, required this.satisfied});

  final String label;
  final bool satisfied;

  @override
  Widget build(BuildContext context) {
    final color = satisfied
        ? Theme.of(context).extension<AppStatusColors>()!.success
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      checked: satisfied,
      label: label,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Icon(
              satisfied ? Icons.check_circle : Icons.circle_outlined,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}

enum MessageTone { error, warning, success, neutral }

class InlineMessage extends StatelessWidget {
  const InlineMessage({
    required this.message,
    this.tone = MessageTone.error,
    super.key,
  });

  final String message;
  final MessageTone tone;

  @override
  Widget build(BuildContext context) {
    final status = Theme.of(context).extension<AppStatusColors>()!;
    final (background, foreground, icon) = switch (tone) {
      MessageTone.error => (
        Theme.of(context).colorScheme.errorContainer,
        Theme.of(context).colorScheme.onErrorContainer,
        Icons.error_outline,
      ),
      MessageTone.warning => (
        status.warningContainer,
        status.onWarningContainer,
        Icons.info_outline,
      ),
      MessageTone.success => (
        status.successContainer,
        status.onSuccessContainer,
        Icons.check_circle_outline,
      ),
      MessageTone.neutral => (
        Theme.of(context).colorScheme.surfaceContainerHighest,
        Theme.of(context).colorScheme.onSurfaceVariant,
        Icons.info_outline,
      ),
    };
    return Semantics(
      liveRegion: true,
      label: message,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: TextStyle(color: foreground)),
            ),
          ],
        ),
      ),
    );
  }
}

class FormSkeleton extends StatelessWidget {
  const FormSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: AppLocalizations.of(context).stateLoading,
    child: ExcludeSemantics(
      child: Column(
        children: List.generate(
          3,
          (_) => Container(
            height: 52,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    ),
  );
}
