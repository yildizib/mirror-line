import 'package:flutter/material.dart';
import 'package:mirrorline/features/account/ui/widgets/auth_widgets.dart';
import 'package:mirrorline/l10n/app_localizations.dart';

enum AccountRequestState { idle, submitting, offline, failed, success }

enum PhoneRole { main, source }

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    required this.onSignIn,
    required this.onCreateAccount,
    super.key,
  });

  final VoidCallback onSignIn;
  final VoidCallback onCreateAccount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _AccountPage(
      centered: true,
      title: l10n.appTitle,
      children: [
        Text(
          l10n.welcomeTitle,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(l10n.welcomeBody, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 32),
        FilledButton(onPressed: onSignIn, child: Text(l10n.authSignIn)),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: onCreateAccount,
          child: Text(l10n.authCreateAccount),
        ),
      ],
    );
  }
}

class SignInViewModel {
  const SignInViewModel({
    this.email = '',
    this.state = AccountRequestState.idle,
    this.emailError,
    this.passwordError,
  });

  final String email;
  final AccountRequestState state;
  final String? emailError;
  final String? passwordError;
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    required this.viewModel,
    required this.onSubmit,
    required this.onForgotPassword,
    required this.onCreateAccount,
    super.key,
  });

  final SignInViewModel viewModel;
  final void Function(String email, String password) onSubmit;
  final VoidCallback onForgotPassword;
  final VoidCallback onCreateAccount;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  late final TextEditingController _email = TextEditingController(
    text: widget.viewModel.email,
  );
  final TextEditingController _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final submitting = widget.viewModel.state == AccountRequestState.submitting;
    return _AccountPage(
      title: l10n.authSignIn,
      children: [
        if (widget.viewModel.state == AccountRequestState.offline)
          InlineMessage(message: l10n.stateOffline, tone: MessageTone.warning),
        if (widget.viewModel.state == AccountRequestState.failed) ...[
          const SizedBox(height: 16),
          InlineMessage(message: l10n.authWrongCredentials),
        ],
        const SizedBox(height: 20),
        AuthTextField(
          controller: _email,
          label: l10n.authEmail,
          errorText: widget.viewModel.emailError,
          enabled: !submitting,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
        ),
        const SizedBox(height: 16),
        AuthTextField(
          controller: _password,
          label: l10n.authPassword,
          errorText: widget.viewModel.passwordError,
          enabled: !submitting,
          password: true,
          onChanged: (_) => setState(() {}),
          autofillHints: const [AutofillHints.password],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: submitting ? null : widget.onForgotPassword,
            child: Text(l10n.authForgotPassword),
          ),
        ),
        FilledButton(
          onPressed: submitting
              ? null
              : () => widget.onSubmit(_email.text, _password.text),
          child: _ActionLabel(
            loading: submitting,
            label: l10n.authSignIn,
            loadingLabel: l10n.authSigningIn,
          ),
        ),
        const SizedBox(height: 12),
        _LinkRow(
          prefix: l10n.authNoAccount,
          action: l10n.authCreateAccount,
          onPressed: widget.onCreateAccount,
        ),
      ],
    );
  }
}

class CreateAccountViewModel {
  const CreateAccountViewModel({
    this.email = '',
    this.termsAccepted = false,
    this.state = AccountRequestState.idle,
    this.emailError,
    this.passwordError,
    this.confirmPasswordError,
    this.termsError,
  });

  final String email;
  final bool termsAccepted;
  final AccountRequestState state;
  final String? emailError;
  final String? passwordError;
  final String? confirmPasswordError;
  final String? termsError;
}

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({
    required this.viewModel,
    required this.onSubmit,
    required this.onSignIn,
    super.key,
  });

  final CreateAccountViewModel viewModel;
  final void Function(
    String email,
    String password,
    String confirmation,
    bool termsAccepted,
  )
  onSubmit;
  final VoidCallback onSignIn;

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  late final TextEditingController _email = TextEditingController(
    text: widget.viewModel.email,
  );
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirmation = TextEditingController();
  late bool _termsAccepted = widget.viewModel.termsAccepted;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final submitting = widget.viewModel.state == AccountRequestState.submitting;
    return _AccountPage(
      title: l10n.authCreateAccount,
      children: [
        if (widget.viewModel.state == AccountRequestState.offline)
          InlineMessage(message: l10n.stateOffline, tone: MessageTone.warning),
        if (widget.viewModel.state == AccountRequestState.failed) ...[
          const SizedBox(height: 16),
          InlineMessage(message: l10n.authEmailExists),
        ],
        const SizedBox(height: 20),
        AuthTextField(
          controller: _email,
          label: l10n.authEmail,
          errorText: widget.viewModel.emailError,
          enabled: !submitting,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 16),
        AuthTextField(
          controller: _password,
          label: l10n.authPassword,
          errorText: widget.viewModel.passwordError,
          enabled: !submitting,
          password: true,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        PasswordRequirements(password: _password.text),
        const SizedBox(height: 16),
        AuthTextField(
          controller: _confirmation,
          label: l10n.authConfirmPassword,
          errorText: widget.viewModel.confirmPasswordError,
          enabled: !submitting,
          password: true,
        ),
        const SizedBox(height: 12),
        Semantics(
          checked: _termsAccepted,
          label: l10n.authTerms,
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _termsAccepted,
            onChanged: submitting
                ? null
                : (value) => setState(() => _termsAccepted = value ?? false),
            title: Text(l10n.authTerms),
          ),
        ),
        if (widget.viewModel.termsError != null)
          Text(
            widget.viewModel.termsError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: submitting
              ? null
              : () => widget.onSubmit(
                  _email.text,
                  _password.text,
                  _confirmation.text,
                  _termsAccepted,
                ),
          child: _ActionLabel(
            loading: submitting,
            label: l10n.authCreateAccount,
            loadingLabel: l10n.authCreating,
          ),
        ),
        const SizedBox(height: 12),
        _LinkRow(
          prefix: l10n.authHaveAccount,
          action: l10n.authSignIn,
          onPressed: widget.onSignIn,
        ),
      ],
    );
  }
}

enum VerificationState {
  pending,
  checking,
  sent,
  cooldown,
  expired,
  verified,
  resendFailed,
}

class VerifyEmailScreen extends StatelessWidget {
  const VerifyEmailScreen({
    required this.email,
    required this.state,
    required this.onCheckAgain,
    required this.onResend,
    required this.onChangeEmail,
    required this.onSignOut,
    this.cooldownSeconds = 0,
    super.key,
  });

  final String email;
  final VerificationState state;
  final VoidCallback onCheckAgain;
  final VoidCallback onResend;
  final VoidCallback onChangeEmail;
  final VoidCallback onSignOut;
  final int cooldownSeconds;

  @override
  Widget build(BuildContext context) => _AccountPage(
    title: AppLocalizations.of(context).verifyTitle,
    children: [
      VerificationPanel(
        email: email,
        state: state,
        cooldownSeconds: cooldownSeconds,
        onCheckAgain: onCheckAgain,
        onResend: onResend,
        onChangeEmail: onChangeEmail,
      ),
      const SizedBox(height: 12),
      TextButton(
        onPressed: onSignOut,
        child: Text(AppLocalizations.of(context).actionSignOut),
      ),
    ],
  );
}

class VerificationPanel extends StatelessWidget {
  const VerificationPanel({
    required this.email,
    required this.state,
    required this.cooldownSeconds,
    required this.onCheckAgain,
    required this.onResend,
    required this.onChangeEmail,
    super.key,
  });
  final String email;
  final VerificationState state;
  final int cooldownSeconds;
  final VoidCallback onCheckAgain;
  final VoidCallback onResend;
  final VoidCallback onChangeEmail;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final waiting = state == VerificationState.checking;
    final resendDisabled = waiting || state == VerificationState.cooldown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.verifyBody(email),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        if (state == VerificationState.expired) ...[
          const SizedBox(height: 16),
          InlineMessage(message: l10n.verifyExpired, tone: MessageTone.warning),
        ],
        if (state == VerificationState.sent) ...[
          const SizedBox(height: 16),
          InlineMessage(message: l10n.verifySent, tone: MessageTone.neutral),
        ],
        if (state == VerificationState.verified) ...[
          const SizedBox(height: 16),
          InlineMessage(message: l10n.verifySuccess, tone: MessageTone.success),
        ],
        if (state == VerificationState.resendFailed) ...[
          const SizedBox(height: 16),
          InlineMessage(message: l10n.verifyResendFailed),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: waiting ? null : onCheckAgain,
          child: _ActionLabel(
            loading: waiting,
            label: l10n.verifyCheckAgain,
            loadingLabel: l10n.stateLoading,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: resendDisabled ? null : onResend,
          child: Text(l10n.verifyResend),
        ),
        if (state == VerificationState.cooldown)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(l10n.verifyCooldown(cooldownSeconds)),
          ),
        TextButton(
          onPressed: onChangeEmail,
          child: Text(l10n.verifyChangeEmail),
        ),
      ],
    );
  }
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    required this.state,
    required this.onSubmit,
    this.email = '',
    this.errorText,
    super.key,
  });
  final AccountRequestState state;
  final String email;
  final String? errorText;
  final ValueChanged<String> onSubmit;
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _email = TextEditingController(
    text: widget.email,
  );
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loading = widget.state == AccountRequestState.submitting;
    return _AccountPage(
      title: l10n.resetTitle,
      children: [
        Text(l10n.resetBody),
        if (widget.state == AccountRequestState.offline) ...[
          const SizedBox(height: 16),
          InlineMessage(
            message: l10n.authConnectionFailed,
            tone: MessageTone.warning,
          ),
        ],
        if (widget.state == AccountRequestState.failed) ...[
          const SizedBox(height: 16),
          InlineMessage(message: widget.errorText ?? l10n.authConnectionFailed),
        ],
        const SizedBox(height: 20),
        AuthTextField(
          controller: _email,
          label: l10n.authEmail,
          errorText: widget.errorText,
          enabled: !loading,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: loading ? null : () => widget.onSubmit(_email.text),
          child: _ActionLabel(
            loading: loading,
            label: l10n.resetSend,
            loadingLabel: l10n.stateLoading,
          ),
        ),
      ],
    );
  }
}

class ResetEmailSentScreen extends StatelessWidget {
  const ResetEmailSentScreen({required this.onDone, super.key});
  final VoidCallback onDone;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _AccountPage(
      centered: true,
      title: l10n.resetSentTitle,
      children: [
        Text(l10n.resetSentBody, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 24),
        FilledButton(onPressed: onDone, child: Text(l10n.actionContinue)),
      ],
    );
  }
}

class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({
    required this.state,
    required this.onSubmit,
    this.expired = false,
    this.passwordError,
    this.confirmationError,
    super.key,
  });
  final AccountRequestState state;
  final bool expired;
  final String? passwordError;
  final String? confirmationError;
  final void Function(String, String) onSubmit;
  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loading = widget.state == AccountRequestState.submitting;
    return _AccountPage(
      title: l10n.resetNewPassword,
      children: [
        if (widget.expired)
          InlineMessage(message: l10n.verifyExpired, tone: MessageTone.warning),
        if (widget.state == AccountRequestState.success)
          InlineMessage(message: l10n.resetSuccess, tone: MessageTone.success),
        if (widget.state == AccountRequestState.offline)
          InlineMessage(
            message: l10n.authConnectionFailed,
            tone: MessageTone.warning,
          ),
        if (widget.state == AccountRequestState.failed)
          InlineMessage(message: l10n.authConnectionFailed),
        const SizedBox(height: 16),
        AuthTextField(
          controller: _password,
          label: l10n.authPassword,
          errorText: widget.passwordError,
          password: true,
          enabled: !loading,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        PasswordRequirements(password: _password.text),
        const SizedBox(height: 16),
        AuthTextField(
          controller: _confirmation,
          label: l10n.authConfirmPassword,
          errorText: widget.confirmationError,
          password: true,
          enabled: !loading,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: loading || widget.expired
              ? null
              : () => widget.onSubmit(_password.text, _confirmation.text),
          child: _ActionLabel(
            loading: loading,
            label: l10n.actionContinue,
            loadingLabel: l10n.stateLoading,
          ),
        ),
      ],
    );
  }
}

class ChooseRoleScreen extends StatelessWidget {
  const ChooseRoleScreen({required this.onSelect, super.key});
  final ValueChanged<PhoneRole> onSelect;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _AccountPage(
      title: l10n.roleChooseTitle,
      children: [
        _RoleChoice(
          icon: Icons.devices_outlined,
          title: l10n.roleMainPhone,
          body: l10n.roleMainBody,
          onTap: () => onSelect(PhoneRole.main),
        ),
        const SizedBox(height: 12),
        _RoleChoice(
          icon: Icons.phonelink_outlined,
          title: l10n.roleSourcePhone,
          body: l10n.roleSourceBody,
          onTap: () => onSelect(PhoneRole.source),
        ),
      ],
    );
  }
}

class ConfirmRoleScreen extends StatelessWidget {
  const ConfirmRoleScreen({
    required this.role,
    required this.onConfirm,
    required this.onBack,
    super.key,
  });
  final PhoneRole role;
  final VoidCallback onConfirm;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final main = role == PhoneRole.main;
    return _AccountPage(
      title: l10n.roleConfirmTitle,
      children: [
        Text(
          main ? l10n.roleConfirmMain : l10n.roleConfirmSource,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 28),
        FilledButton(onPressed: onConfirm, child: Text(l10n.actionContinue)),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onBack, child: Text(l10n.actionBack)),
      ],
    );
  }
}

class RegisterDeviceScreen extends StatelessWidget {
  const RegisterDeviceScreen({
    required this.state,
    required this.onRegister,
    super.key,
  });
  final AccountRequestState state;
  final VoidCallback onRegister;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final registering = state == AccountRequestState.submitting;
    return _AccountPage(
      title: l10n.deviceRegisterTitle,
      children: [
        Text(
          l10n.deviceRegisterBody,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        if (state == AccountRequestState.failed) ...[
          const SizedBox(height: 20),
          InlineMessage(message: l10n.deviceRegisterFailed),
        ],
        const SizedBox(height: 28),
        FilledButton(
          onPressed: registering ? null : onRegister,
          child: _ActionLabel(
            loading: registering,
            label: l10n.deviceRegisterAction,
            loadingLabel: l10n.deviceRegistering,
          ),
        ),
      ],
    );
  }
}

class _AccountPage extends StatelessWidget {
  const _AccountPage({
    required this.title,
    required this.children,
    this.centered = false,
  });

  final String title;
  final List<Widget> children;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(20),
              child: Align(
                alignment: centered ? Alignment.center : Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
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
            );
          },
        ),
      ),
    );
  }
}

class _ActionLabel extends StatelessWidget {
  const _ActionLabel({
    required this.loading,
    required this.label,
    required this.loadingLabel,
  });
  final bool loading;
  final String label;
  final String loadingLabel;
  @override
  Widget build(BuildContext context) => loading
      ? Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Flexible(child: Text(loadingLabel)),
          ],
        )
      : Text(label);
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.prefix,
    required this.action,
    required this.onPressed,
  });
  final String prefix;
  final String action;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(prefix),
      TextButton(onPressed: onPressed, child: Text(action)),
    ],
  );
}

class _RoleChoice extends StatelessWidget {
  const _RoleChoice({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: title,
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(body),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    ),
  );
}
