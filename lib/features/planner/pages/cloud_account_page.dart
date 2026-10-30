// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:streak/features/planner/l10n/planner_l10n.dart';
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
      'google_link_required' => 'cloudGoogleLinkRequired',
      'google_email_mismatch' => 'cloudGoogleEmailMismatch',
      'google_already_linked' => 'cloudGoogleAlreadyLinked',
      'rate_limited' => 'cloudRateLimited',
      'network_error' => 'cloudNetworkError',
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

class CloudAccountTile extends StatelessWidget {
  const CloudAccountTile({super.key, required this.controller});
  final CloudSyncController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.cloud_outlined),
      title: Text(context.plannerText('cloudAccount')),
      subtitle: Text(cloudStatusText(context, controller)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CloudAccountPage(controller: controller),
        ),
      ),
    ),
  );
}

class CloudAccountPage extends StatefulWidget {
  const CloudAccountPage({super.key, this.controller});
  final CloudSyncController? controller;
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
  bool _exporting = false;
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
      await controller.requestPasswordReset(_email.text);
      if (mounted && controller.errorCode == 'password_reset_sent') {
        setState(() => _resetSent = true);
      }
    }
  }

  Future<void> _export(CloudSyncController controller) async {
    if (_exporting || controller.exportDraft == null) return;
    setState(() => _exporting = true);
    try {
      final json = await controller.exportDraft!();
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/levelup-local-draft-${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(json, flush: true);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(file.path)],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.plannerText('genericError'))),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
        return Scaffold(
          appBar: AppBar(title: Text(context.plannerText('cloudAccount'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.cloud_outlined, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (controller.user != null)
                          Text(
                            controller.user!.email,
                            textDirection: TextDirection.ltr,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        Text(cloudStatusText(context, controller)),
                        if (controller.pendingCount > 0 &&
                            controller.status != CloudSyncStatus.pending)
                          Text(
                            context.plannerText('cloudPending', {
                              'count': plannerNumber(
                                context,
                                controller.pendingCount,
                              ),
                            }),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (controller.busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
              if (controller.errorCode != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    controller.errorCode == 'password_reset_sent' &&
                            controller.passwordResetCompletesInEmail
                        ? context.plannerText('cloudResetLinkSent')
                        : _cloudError(context, controller.errorCode!),
                    style: TextStyle(
                      color: switch (controller.errorCode) {
                        'password_reset_sent' || 'password_reset_complete' =>
                          Theme.of(context).colorScheme.primary,
                        _ => Theme.of(context).colorScheme.error,
                      },
                    ),
                  ),
                ),
              if (signIn && controller.configured && _resetMode) ...[
                const SizedBox(height: 24),
                Text(
                  context.plannerText(
                    _resetSent
                        ? controller.passwordResetCompletesInEmail
                              ? 'cloudResetLinkInfo'
                              : 'cloudResetCodeInfo'
                        : 'cloudResetRequestInfo',
                  ),
                ),
                const SizedBox(height: 16),
                Form(
                  key: _form,
                  child: Column(
                    children: [
                      TextFormField(
                        key: const ValueKey('cloud-email'),
                        enabled: !controller.busy,
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: context.plannerText('cloudEmail'),
                          prefixIcon: const Icon(Icons.mail_outline),
                        ),
                        validator: (value) =>
                            value == null ||
                                value.trim().length > 254 ||
                                !RegExp(
                                  r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                ).hasMatch(value.trim())
                            ? context.plannerText('cloudInvalidEmail')
                            : null,
                      ),
                      if (_resetSent &&
                          !controller.passwordResetCompletesInEmail) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('cloud-reset-code'),
                          enabled: !controller.busy,
                          controller: _resetCode,
                          textDirection: TextDirection.ltr,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: InputDecoration(
                            labelText: context.plannerText('cloudResetCode'),
                            prefixIcon: const Icon(Icons.password_outlined),
                          ),
                          validator: (value) =>
                              value == null || value.trim().length < 32
                              ? context.plannerText('cloudResetInvalid')
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('cloud-password'),
                          enabled: !controller.busy,
                          controller: _password,
                          obscureText: _hidePassword,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            labelText: context.plannerText('cloudPassword'),
                            helperText: context.plannerText(
                              'cloudPasswordRule',
                            ),
                            helperMaxLines: 4,
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: context.plannerText(
                                _hidePassword
                                    ? 'cloudShowPassword'
                                    : 'cloudHidePassword',
                              ),
                              onPressed: controller.busy
                                  ? null
                                  : () => setState(
                                      () => _hidePassword = !_hidePassword,
                                    ),
                              icon: Icon(
                                _hidePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) =>
                              value == null ||
                                  value.runes.length < 12 ||
                                  utf8.encode(value).length > 72
                              ? context.plannerText('cloudPasswordRule')
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('cloud-confirm-password'),
                          enabled: !controller.busy,
                          controller: _confirmPassword,
                          obscureText: _hidePassword,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            labelText: context.plannerText(
                              'cloudConfirmPassword',
                            ),
                            prefixIcon: const Icon(Icons.lock_outline),
                          ),
                          validator: (value) => value != _password.text
                              ? context.plannerText('cloudPasswordsDoNotMatch')
                              : null,
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (_resetSent &&
                          controller.passwordResetCompletesInEmail)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            key: const ValueKey('cloud-reset-return'),
                            onPressed: controller.busy
                                ? null
                                : () => setState(() {
                                    _resetMode = false;
                                    _resetSent = false;
                                  }),
                            child: Text(
                              context.plannerText('cloudReturnToSignIn'),
                            ),
                          ),
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            key: const ValueKey('cloud-reset-submit'),
                            onPressed: controller.busy
                                ? null
                                : () => _reset(controller),
                            child: Text(
                              context.plannerText('cloudResetPassword'),
                            ),
                          ),
                        ),
                      TextButton(
                        onPressed: controller.busy
                            ? null
                            : () => setState(() {
                                _resetMode = false;
                                _resetSent = false;
                                _resetCode.clear();
                              }),
                        child: Text(context.plannerText('cloudSignIn')),
                      ),
                    ],
                  ),
                ),
              ],
              if (signIn && controller.configured && !_resetMode) ...[
                const SizedBox(height: 24),
                Form(
                  key: _form,
                  child: AutofillGroup(
                    child: Column(
                      children: [
                        TextFormField(
                          key: const ValueKey('cloud-email'),
                          enabled: !controller.busy,
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.username],
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText: context.plannerText('cloudEmail'),
                            prefixIcon: const Icon(Icons.mail_outline),
                          ),
                          validator: (value) =>
                              value == null ||
                                  value.trim().length > 254 ||
                                  !RegExp(
                                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                  ).hasMatch(value.trim())
                              ? context.plannerText('cloudInvalidEmail')
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('cloud-password'),
                          enabled: !controller.busy,
                          controller: _password,
                          obscureText: _hidePassword,
                          enableSuggestions: false,
                          autocorrect: false,
                          autofillHints: [
                            _register
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          decoration: InputDecoration(
                            labelText: context.plannerText('cloudPassword'),
                            helperText: _register
                                ? context.plannerText('cloudPasswordRule')
                                : null,
                            helperMaxLines: 4,
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: context.plannerText(
                                _hidePassword
                                    ? 'cloudShowPassword'
                                    : 'cloudHidePassword',
                              ),
                              onPressed: controller.busy
                                  ? null
                                  : () => setState(
                                      () => _hidePassword = !_hidePassword,
                                    ),
                              icon: Icon(
                                _hidePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
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
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const ValueKey('cloud-confirm-password'),
                            enabled: !controller.busy,
                            controller: _confirmPassword,
                            obscureText: _hidePassword,
                            enableSuggestions: false,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: InputDecoration(
                              labelText: context.plannerText(
                                'cloudConfirmPassword',
                              ),
                              prefixIcon: const Icon(Icons.lock_outline),
                            ),
                            validator: (value) => value != _password.text
                                ? context.plannerText(
                                    'cloudPasswordsDoNotMatch',
                                  )
                                : null,
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            key: const ValueKey('cloud-submit'),
                            onPressed: controller.busy
                                ? null
                                : () => _submit(controller),
                            child: Text(
                              context.plannerText(
                                _register ? 'cloudRegister' : 'cloudSignIn',
                              ),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: controller.busy
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
                        if (!_register)
                          TextButton(
                            onPressed: controller.busy
                                ? null
                                : () => setState(() {
                                    _resetMode = true;
                                    _resetSent = false;
                                    _password.clear();
                                  }),
                            child: Text(
                              context.plannerText('cloudForgotPassword'),
                            ),
                          ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            key: const ValueKey('cloud-google-submit'),
                            onPressed: controller.busy
                                ? null
                                : controller.signInWithGoogle,
                            icon: const Icon(Icons.account_circle_outlined),
                            label: Text(
                              context.plannerText('cloudGoogleSignIn'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.plannerText('cloudPrivacy'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (!signIn) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: controller.busy || !controller.configured
                      ? null
                      : controller.retryNow,
                  icon: const Icon(Icons.sync),
                  label: Text(context.plannerText('cloudSyncNow')),
                ),
                if (controller.canRestore) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: controller.busy
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
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: Text(context.plannerText('cloudRestoreCloud')),
                  ),
                ],
                if (controller.user != null && !controller.user!.hasGoogle) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: controller.busy ? null : controller.linkGoogle,
                    icon: const Icon(Icons.account_circle_outlined),
                    label: Text(context.plannerText('cloudGoogleLink')),
                  ),
                ],
              ],
              if (controller.exportDraft != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: controller.busy || _exporting
                      ? null
                      : () => _export(controller),
                  icon: const Icon(Icons.file_download_outlined),
                  label: Text(context.plannerText('cloudExportDraft')),
                ),
              ],
              if (controller.user != null) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: controller.busy
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
                  icon: const Icon(Icons.logout),
                  label: Text(context.plannerText('cloudSignOut')),
                ),
              ],
              if (signIn)
                TextButton(
                  onPressed: () => Navigator.maybePop(context),
                  child: Text(context.plannerText('cloudKeepOffline')),
                ),
            ],
          ),
        );
      },
    );
  }
}
