import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';

/// Checks the shared ashleyrichards.tech release feed for a newer a2 build
/// and, if one is published, prompts the user to download it -- the same
/// mechanism the other Ashley/Ania apps (inventory, prestapocket, ...) use.
class AppUpdateService {
  const AppUpdateService._();

  static const String _updateUrl =
      'https://ashleyrichards.tech/download/app_versions.json';
  static const String _fallbackDownloadPage =
      'https://ashleyrichards.tech/download/';
  static const String _appKey = 'a2';

  static bool _dialogOpen = false;

  static Future<void> checkForUpdate(BuildContext context) async {
    if (_dialogOpen) return;

    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      final uri = Uri.parse(
        '$_updateUrl?t=${DateTime.now().millisecondsSinceEpoch}',
      );
      final response = await http
          .get(
            uri,
            headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;

      final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      final appDataRaw = jsonData[_appKey];
      if (appDataRaw is! Map<String, dynamic>) return;

      // The feed's "latestVersion" sometimes carries a "+build" suffix; only
      // the plain semantic version is meaningful for display.
      final latestVersion = (appDataRaw['latestVersion'] ?? '')
          .toString()
          .split('+')
          .first;
      final latestBuild = appDataRaw['latestBuild'] is int
          ? appDataRaw['latestBuild'] as int
          : int.tryParse('${appDataRaw['latestBuild']}') ?? 0;
      final updatedAt = (appDataRaw['updatedAt'] ?? '').toString();
      final downloadPage =
          (appDataRaw['androidDownloadPage'] ??
                  appDataRaw['downloadPage'] ??
                  _fallbackDownloadPage)
              .toString();
      final notes = appDataRaw['notes'] is List
          ? List<String>.from(appDataRaw['notes'] as List)
          : const <String>[];

      if (latestBuild <= currentBuild) return;
      if (!context.mounted) return;

      _dialogOpen = true;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const LText('Update available'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LText('A new version ($latestVersion) is ready to download.'),
                if (updatedAt.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  LText('Released: $updatedAt'),
                ],
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...notes.map(
                    (note) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $note'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const LText('Later'),
            ),
            FilledButton(
              onPressed: () async {
                await launchUrl(
                  Uri.parse(downloadPage),
                  mode: LaunchMode.externalApplication,
                );
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              },
              child: const LText('Download'),
            ),
          ],
        ),
      );
    } catch (_) {
      // Update checks must never block normal app use.
    } finally {
      _dialogOpen = false;
    }
  }
}
