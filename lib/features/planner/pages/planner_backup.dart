// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:streak/features/planner/l10n/planner_l10n.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/features/planner/widgets/planner_widgets.dart';
import 'package:streak/services/planner_import.dart';

/// Settings > Data: back the planner up to a JSON file and restore it. Works
/// with or without an account; when signed in, an import syncs like any edit.
abstract final class PlannerBackup {
  /// Opens the system picker and returns the chosen file's text, or null
  /// when cancelled. Replaceable in tests.
  @visibleForTesting
  static Future<String?> Function() pickFile = _pickJsonFile;

  /// Hands the written backup to the system share sheet (Save to Files,
  /// Drive, and so on). Replaceable in tests.
  @visibleForTesting
  static Future<void> Function(BuildContext context, File file) shareFile =
      _share;

  static Future<String?> _pickJsonFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file == null) return null;
    if (file.size > plannerImportMaxBytes) {
      throw const FormatException('too_large');
    }
    final bytes =
        file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    return bytes == null ? null : utf8.decode(bytes);
  }

  static Future<void> _share(BuildContext context, File file) async {
    final box = context.findRenderObject() as RenderBox?;
    await Share.shareXFiles(
      [XFile(file.path)],
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    );
  }

  static Future<void> export(BuildContext context) async {
    final planner = context.read<PlannerController>();
    try {
      final now = planner.now;
      final directory = await getTemporaryDirectory();
      final stamp =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final file = File('${directory.path}/levelup-backup-$stamp.json');
      await file.writeAsString(
        encodePlannerBackup(planner.exportState, now),
        flush: true,
      );
      if (context.mounted) await shareFile(context, file);
    } catch (_) {
      if (context.mounted) {
        _message(context, context.plannerText('genericError'));
      }
    }
  }

  /// Replaces the planner with a backup after an explicit confirmation.
  /// Invalid files are rejected before anything changes.
  static Future<void> import(BuildContext context) async {
    final Map<String, dynamic> state;
    try {
      final source = await pickFile();
      if (source == null) return;
      state = plannerStateFromImport(source);
    } catch (_) {
      if (context.mounted) {
        _message(context, context.plannerText('importInvalid'));
      }
      return;
    }
    if (!context.mounted) return;
    final confirmed = await plannerConfirm(
      context,
      title: context.plannerText('importConfirmTitle'),
      message: context.plannerText('importConfirmMessage'),
      action: context.plannerText('importReplace'),
    );
    if (!confirmed || !context.mounted) return;
    final planner = context.read<PlannerController>();
    // Show the outcome now rather than queued behind an earlier message.
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await plannerAction(
      context,
      () => planner.replaceState(state),
      success: context.plannerText('importDone'),
    );
  }

  static void _message(BuildContext context, String text) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
}
