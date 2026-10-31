// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/features/planner/l10n/planner_l10n.dart';
import 'package:streak/features/planner/widgets/google_logo.dart';
import 'package:streak/features/planner/widgets/planner_widgets.dart';
import 'package:streak/services/cloud_sync_controller.dart';

String cloudStatusText(BuildContext context, CloudSyncController controller) =>
    context.plannerText(
      switch (controller.status) {
        CloudSyncStatus.unconfigured => 'cloudUnconfigured',
        CloudSyncStatus.signedOut => 'cloudSignInHint',
        CloudSyncStatus.restoring => 'cloudRestoring',
        CloudSyncStatus.syncing => 'cloudSyncing',
        CloudSyncStatus.synced => 'cloudSynced',
        CloudSyncStatus.pending => 'cloudPending',
        CloudSyncStatus.offline => 'cloudOffline',
        CloudSyncStatus.conflict => 'cloudConflict',
        CloudSyncStatus.rejected => 'cloudRejected',
        CloudSyncStatus.sessionExpired => 'cloudSessionExpired',
        CloudSyncStatus.localOnly => 'cloudLocalOnly',
      },
      {'count': plannerNumber(context, controller.pendingCount)},
    );

String _cloudError(BuildContext context, String code) =>
    context.plannerText(switch (code) {
      'invalid_credentials' => 'cloudInvalidCredentials',
      'email_exists' => 'cloudEmailExists',
      'invalid_email' => 'cloudInvalidEmail',
      'weak_password' => 'cloudPasswordRule',
      'email_provider_disabled' => 'cloudEmailProviderDisabled',
      'account_disabled' => 'cloudAccountDisabled',
      'firebase_configuration' => 'cloudFirebaseConfiguration',
      'invalid_reset_token' => 'cloudResetInvalid',
      'password_reset_unavailable' => 'cloudResetUnavailable',
      'password_reset_sent' => 'cloudResetSent',
      'password_reset_complete' => 'cloudResetComplete',
      'google_canceled' => 'cloudGoogleCanceled',
      'google_not_configured' ||
      'google_not_supported' => 'cloudGoogleUnavailable',
      'google_configuration' ||
      'google_sign_in_failed' ||
      'invalid_google_token' => 'cloudGoogleConfiguration',
      'google_credential_rejected' => 'cloudGoogleCredentialRejected',
      'google_provider_disabled' => 'cloudGoogleProviderDisabled',
      'google_link_required' => 'cloudGoogleLinkRequired',
      'google_email_mismatch' => 'cloudGoogleEmailMismatch',
      'google_already_linked' => 'cloudGoogleAlreadyLinked',
      'rate_limited' => 'cloudRateLimited',
      'network_error' => 'cloudNetworkError',
      'firestore_unavailable' => 'cloudNetworkError',
      'firestore_permission_denied' => 'cloudFirestorePermissionDenied',
      'firestore_unauthenticated' => 'cloudFirestoreUnauthenticated',
      'firestore_failed_precondition' => 'cloudFirestorePrecondition',
      'service_unavailable' ||
      'https_required' ||
      'invalid_response' ||
      'not_found' => 'cloudServerUnavailable',
      'unauthorized' || 'session_expired' => 'cloudSessionExpired',
      'revision_conflict' => 'cloudConflict',
      'cloud_queue_full' => 'cloudQueueFull',
      'local_storage_error' => 'genericError',
      'unconfigured' || 'invalid_configuration' => 'cloudUnconfigured',
      'invalid_transition' ||
      'history_conflict' ||
      'deadline_passed' ||
      'mutation_reused' ||
      'server_reconciled' ||
      'payload_too_large' => 'cloudRejected',
      _ => 'cloudAuthFailed',
    });

/// Feedback below a form or identity: informational codes use the accent,
/// everything else the error colour.
class _CloudMessage extends StatelessWidget {
  const _CloudMessage({required this.controller, this.center = false});
  final CloudSyncController controller;
  final bool center;
  @override
  Widget build(BuildContext context) {
    final code = controller.errorCode;
    if (code == null) return const SizedBox.shrink();
    final info =
        code == 'password_reset_sent' || code == 'password_reset_complete';
    final color = info ? context.colors.primary : context.colors.error;
    return Semantics(
      liveRegion: true,
      child: Text(
        code == 'password_reset_sent' &&
                controller.passwordResetCompletesInEmail
            ? context.plannerText('cloudResetLinkSent')
            : _cloudError(context, code),
        textAlign: center ? TextAlign.center : TextAlign.start,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: color,
          height: 1.4,
        ),
      ),
    );
  }
}

Color _statusColor(BuildContext context, CloudSyncStatus status) =>
    switch (status) {
      CloudSyncStatus.synced => context.tokens.success,
      CloudSyncStatus.syncing ||
      CloudSyncStatus.restoring => context.colors.primary,
      CloudSyncStatus.pending ||
      CloudSyncStatus.offline ||
      CloudSyncStatus.localOnly => context.tokens.warning,
      _ => context.colors.error,
    };

/// Avatar, email and sync state, centred like the sign-in screen's header.
/// Used at the top of Profile.
class CloudIdentityHeader extends StatelessWidget {
  const CloudIdentityHeader({super.key, required this.controller});
  final CloudSyncController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final user = controller.user;
      final email = user?.email ?? '';
      final text = Theme.of(context).textTheme;
      // Without an account the planner lives only on this device.
      final guest = user == null;
      return Column(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: context.colors.primary.withValues(alpha: .18),
            child: guest
                ? Icon(
                    Icons.person_outline_rounded,
                    size: 34,
                    color: context.colors.primary,
                  )
                : Text(
                    email.isEmpty ? '?' : email.characters.first.toUpperCase(),
                    style: text.headlineSmall?.copyWith(
                      color: context.colors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
          const SizedBox(height: 14),
          Text(
            guest ? context.plannerText('cloudGuest') : email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            textDirection: guest ? null : TextDirection.ltr,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: guest
                        ? context.tokens.muted
                        : _statusColor(context, controller.status),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    guest
                        ? context.plannerText('cloudLocalOnly')
                        : cloudStatusText(context, controller),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(
                      color: context.tokens.muted,
                    ),
                  ),
                ),
                if (user?.hasGoogle == true) ...[
                  const SizedBox(width: 8),
                  const GoogleLogo(size: 13),
                ],
              ],
            ),
          ),
          if (controller.pendingCount > 0 &&
              controller.status != CloudSyncStatus.pending)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                context.plannerText('cloudPending', {
                  'count': plannerNumber(context, controller.pendingCount),
                }),
                style: text.bodySmall?.copyWith(color: context.tokens.muted),
              ),
            ),
          if (controller.busy)
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (controller.errorCode != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _CloudMessage(controller: controller, center: true),
            ),
        ],
      );
    },
  );
}

/// Account actions for a signed-in user. Synchronisation itself is automatic,
/// and backups live in Settings > Data, so only account-specific actions are
/// offered here.
class CloudAccountActions extends StatefulWidget {
  const CloudAccountActions({super.key, required this.controller});
  final CloudSyncController controller;

  @override
  State<CloudAccountActions> createState() => _CloudAccountActionsState();
}

class _CloudAccountActionsState extends State<CloudAccountActions> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final user = controller.user;
        if (user == null) return const SizedBox.shrink();
        final busy = controller.busy;
        final rows = [
          if (controller.canRestore)
            PlannerMenuRow(
              icon: Icons.cloud_download_outlined,
              label: context.plannerText('cloudRestoreCloud'),
              onTap: busy
                  ? null
                  : () async {
                      if (await plannerConfirm(
                        context,
                        title: context.plannerText('cloudRestoreCloud'),
                        message: context.plannerText('cloudRestoreInfo'),
                        action: context.plannerText('cloudRestoreCloud'),
                      )) {
                        await controller.restoreCloud();
                      }
                    },
            ),
          if (!user.hasGoogle)
            PlannerMenuRow(
              leading: const GoogleLogo(size: 20),
              label: context.plannerText('cloudGoogleLink'),
              onTap: busy ? null : controller.linkGoogle,
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (rows.isNotEmpty) ...[
              PlannerGroup(children: rows),
              const SizedBox(height: 16),
            ],
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      if (await plannerConfirm(
                        context,
                        title: context.plannerText('cloudSignOut'),
                        message: context.plannerText('cloudSignOutInfo'),
                        action: context.plannerText('cloudSignOut'),
                      )) {
                        await controller.signOut();
                      }
                    },
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.error,
                iconColor: context.colors.error,
              ),
              icon: const Icon(Icons.logout_rounded, size: 20),
              label: Text(context.plannerText('cloudSignOut')),
            ),
          ],
        );
      },
    );
  }
}

class CloudAccountPage extends StatefulWidget {
  const CloudAccountPage({
    super.key,
    this.controller,
    this.requiredAuthentication = false,
    this.onContinueWithoutAccount,
  });
  final CloudSyncController? controller;
  final bool requiredAuthentication;

  /// When set, the sign-in screen offers using the app on this device only.
  final VoidCallback? onContinueWithoutAccount;
  @override
  State<CloudAccountPage> createState() => _CloudAccountPageState();
}

class _CloudAccountPageState extends State<CloudAccountPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _resetCode = TextEditingController();
  bool _register = false;
  bool _resetMode = false;
  bool _resetSent = false;
  bool _hidePassword = true;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _resetCode.dispose();
    super.dispose();
  }

  Future<void> _submit(CloudSyncController controller) async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await controller.signIn(_email.text, _password.text, register: _register);
    if (mounted &&
        controller.user != null &&
        controller.status != CloudSyncStatus.sessionExpired) {
      _password.clear();
      _confirmPassword.clear();
    }
  }

  Future<void> _reset(CloudSyncController controller) async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    if (_resetSent) {
      if (controller.passwordResetCompletesInEmail) return;
      await controller.completePasswordReset(
        _email.text,
        _resetCode.text,
        _password.text,
      );
      if (mounted && controller.errorCode == 'password_reset_complete') {
        setState(() {
          _resetMode = false;
          _resetSent = false;
          _password.clear();
          _confirmPassword.clear();
          _resetCode.clear();
        });
      }
    } else {
      await _sendResetEmail(controller);
    }
  }

  /// Asks the backend to send its reset email (Firebase's built-in template)
  /// in the app's current language. Also used to resend.
  Future<void> _sendResetEmail(CloudSyncController controller) async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await controller.requestPasswordReset(
      _email.text,
      languageCode: Localizations.localeOf(context).languageCode,
    );
    if (mounted && controller.errorCode == 'password_reset_sent') {
      setState(() => _resetSent = true);
    }
  }

  InputDecoration _input(
    BuildContext context,
    String label,
    IconData icon, {
    String? helper,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      prefixIcon: Icon(icon, size: 20),
      suffixIcon: suffix,
    );
  }

  Widget _visibilityToggle(CloudSyncController controller) => IconButton(
    tooltip: context.plannerText(
      _hidePassword ? 'cloudShowPassword' : 'cloudHidePassword',
    ),
    onPressed: controller.busy
        ? null
        : () => setState(() => _hidePassword = !_hidePassword),
    icon: Icon(
      _hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      size: 20,
    ),
  );

  String? _validateEmail(String? value) =>
      value == null ||
          value.trim().length > 254 ||
          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())
      ? context.plannerText('cloudInvalidEmail')
      : null;

  Widget _emailField(CloudSyncController controller, String hint) =>
      TextFormField(
        key: const ValueKey('cloud-email'),
        enabled: !controller.busy,
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autofillHints: [hint],
        textDirection: TextDirection.ltr,
        decoration: _input(
          context,
          context.plannerText('cloudEmail'),
          Icons.alternate_email_rounded,
        ),
        validator: _validateEmail,
      );

  Widget _confirmField(CloudSyncController controller) => TextFormField(
    key: const ValueKey('cloud-confirm-password'),
    enabled: !controller.busy,
    controller: _confirmPassword,
    obscureText: _hidePassword,
    enableSuggestions: false,
    autocorrect: false,
    autofillHints: const [AutofillHints.newPassword],
    decoration: _input(
      context,
      context.plannerText('cloudConfirmPassword'),
      Icons.lock_outline_rounded,
    ),
    validator: (value) => value != _password.text
        ? context.plannerText('cloudPasswordsDoNotMatch')
        : null,
  );

  Widget _primary(Key key, String label, VoidCallback? onPressed) => SizedBox(
    width: double.infinity,
    height: 52,
    child: FilledButton(
      key: key,
      onPressed: onPressed,
      child: Text(label),
    ),
  );

  List<Widget> _resetForm(CloudSyncController controller) {
    final busy = controller.busy;
    final linkFlow = controller.passwordResetCompletesInEmail;
    final emailOnly = !_resetSent || linkFlow;
    final linkSent = _resetSent && linkFlow;
    return [
      Icon(
        linkSent ? Icons.mark_email_read_outlined : Icons.lock_reset_rounded,
        size: 40,
        color: context.colors.primary,
      ),
      const SizedBox(height: 16),
      Text(
        context.plannerText(
          _resetSent
              ? linkFlow
                    ? 'cloudResetLinkInfo'
                    : 'cloudResetCodeInfo'
              : linkFlow
              ? 'cloudResetLinkRequestInfo'
              : 'cloudResetRequestInfo',
        ),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: context.tokens.muted,
        ),
      ),
      const SizedBox(height: 24),
      Form(
        key: _form,
        child: Column(
          children: [
            _emailField(controller, AutofillHints.email),
            if (!emailOnly) ...[
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('cloud-reset-code'),
                enabled: !busy,
                controller: _resetCode,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                enableSuggestions: false,
                decoration: _input(
                  context,
                  context.plannerText('cloudResetCode'),
                  Icons.password_rounded,
                ),
                validator: (value) => value == null || value.trim().length < 32
                    ? context.plannerText('cloudResetInvalid')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('cloud-password'),
                enabled: !busy,
                controller: _password,
                obscureText: _hidePassword,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.newPassword],
                decoration: _input(
                  context,
                  context.plannerText('cloudPassword'),
                  Icons.lock_outline_rounded,
                  helper: context.plannerText('cloudPasswordRule'),
                  suffix: _visibilityToggle(controller),
                ),
                validator: (value) =>
                    value == null ||
                        value.runes.length < 12 ||
                        utf8.encode(value).length > 72
                    ? context.plannerText('cloudPasswordRule')
                    : null,
              ),
              const SizedBox(height: 12),
              _confirmField(controller),
            ],
            const SizedBox(height: 20),
            if (linkSent) ...[
              _primary(
                const ValueKey('cloud-reset-return'),
                context.plannerText('cloudReturnToSignIn'),
                busy
                    ? null
                    : () => setState(() {
                        _resetMode = false;
                        _resetSent = false;
                      }),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('cloud-reset-resend'),
                  onPressed: busy ? null : () => _sendResetEmail(controller),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: Text(context.plannerText('cloudResendLink')),
                ),
              ),
            ] else ...[
              _primary(
                const ValueKey('cloud-reset-submit'),
                context.plannerText('cloudResetPassword'),
                busy ? null : () => _reset(controller),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        _resetMode = false;
                        _resetSent = false;
                        _resetCode.clear();
                      }),
                child: Text(context.plannerText('cloudSignIn')),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  List<Widget> _signInForm(CloudSyncController controller) {
    final busy = controller.busy;
    final muted = context.tokens.muted;
    return [
      SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton(
          key: const ValueKey('cloud-google-submit'),
          onPressed: busy ? null : controller.signInWithGoogle,
          style: OutlinedButton.styleFrom(
            foregroundColor: context.colors.onSurface,
            backgroundColor: context.colors.surfaceContainerHigh,
            side: BorderSide(color: context.colors.outlineVariant),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            textStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const GoogleLogo(size: 20),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  context.plannerText('cloudGoogleSignIn'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(
          children: [
            Expanded(child: Divider(color: context.colors.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                context.plannerText('authOr'),
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: muted),
              ),
            ),
            Expanded(child: Divider(color: context.colors.outlineVariant)),
          ],
        ),
      ),
      Form(
        key: _form,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _emailField(controller, AutofillHints.username),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('cloud-password'),
                enabled: !busy,
                controller: _password,
                obscureText: _hidePassword,
                enableSuggestions: false,
                autocorrect: false,
                textInputAction: _register
                    ? TextInputAction.next
                    : TextInputAction.done,
                onFieldSubmitted: _register || busy
                    ? null
                    : (_) => _submit(controller),
                autofillHints: [
                  _register
                      ? AutofillHints.newPassword
                      : AutofillHints.password,
                ],
                decoration: _input(
                  context,
                  context.plannerText('cloudPassword'),
                  Icons.lock_outline_rounded,
                  helper: _register
                      ? context.plannerText('cloudPasswordRule')
                      : null,
                  suffix: _visibilityToggle(controller),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? context.plannerText('cloudInvalidPassword')
                    : _register &&
                          (value.runes.length < 12 ||
                              utf8.encode(value).length > 72)
                    ? context.plannerText('cloudPasswordRule')
                    : null,
              ),
              if (_register) ...[
                const SizedBox(height: 12),
                _confirmField(controller),
              ],
              if (!_register)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            _resetMode = true;
                            _resetSent = false;
                            _password.clear();
                          }),
                    style: TextButton.styleFrom(
                      foregroundColor: muted,
                      textStyle: Theme.of(context).textTheme.bodySmall,
                    ),
                    child: Text(context.plannerText('cloudForgotPassword')),
                  ),
                )
              else
                const SizedBox(height: 20),
              _primary(
                const ValueKey('cloud-submit'),
                context.plannerText(
                  _register ? 'cloudRegister' : 'cloudSignIn',
                ),
                busy ? null : () => _submit(controller),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          _register = !_register;
                          _confirmPassword.clear();
                        }),
                  child: Text(
                    context.plannerText(
                      _register ? 'cloudSignIn' : 'cloudRegister',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _authentication(CloudSyncController controller) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/icon.png',
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Level Up',
                textAlign: TextAlign.center,
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 32),
              if (!controller.configured)
                Text(
                  cloudStatusText(context, controller),
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: context.tokens.muted),
                )
              else if (_resetMode)
                ..._resetForm(controller)
              else
                ..._signInForm(controller),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                child: Column(
                  children: [
                    if (controller.busy)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (controller.errorCode != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: _CloudMessage(
                          controller: controller,
                          center: true,
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.onContinueWithoutAccount case final skip?
                  when !_resetMode) ...[
                const SizedBox(height: 24),
                Center(
                  child: TextButton.icon(
                    key: const ValueKey('cloud-continue-without-account'),
                    onPressed: controller.busy ? null : skip,
                    style: TextButton.styleFrom(
                      foregroundColor: context.tokens.muted,
                    ),
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text(
                      context.plannerText('cloudContinueWithoutAccount'),
                    ),
                  ),
                ),
              ],
              if (controller.user case final user?) ...[
                const SizedBox(height: 24),
                Text(
                  user.email,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: text.bodySmall?.copyWith(color: context.tokens.muted),
                ),
                Center(
                  child: TextButton.icon(
                    onPressed: controller.busy ? null : controller.signOut,
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: Text(context.plannerText('cloudSignOut')),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller ?? context.read<CloudSyncController>();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final signIn =
            controller.user == null ||
            controller.status == CloudSyncStatus.sessionExpired;
        final requiredAuthentication = widget.requiredAuthentication;
        return PopScope(
          canPop: !requiredAuthentication,
          child: Scaffold(
            appBar: requiredAuthentication
                ? null
                : AppBar(title: Text(context.plannerText('cloudAccount'))),
            body: SafeArea(
              top: requiredAuthentication,
              child: signIn
                  ? _authentication(controller)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      children: [
                        CloudIdentityHeader(controller: controller),
                        const SizedBox(height: 20),
                        CloudAccountActions(controller: controller),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}
