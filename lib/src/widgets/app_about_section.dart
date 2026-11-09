import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

const appPageUrl = 'https://terudoru.com/apps/more-better-gakujo-flutter';

class AppAboutSection extends StatefulWidget {
  const AppAboutSection({super.key, required this.onOpenUrl, this.loadVersion});

  final void Function(Uri) onOpenUrl;
  final Future<String> Function()? loadVersion;

  @override
  State<AppAboutSection> createState() => _AppAboutSectionState();
}

class _AppAboutSectionState extends State<AppAboutSection> {
  String? _version;

  @override
  void initState() {
    super.initState();
    unawaited(_loadVersion());
  }

  Future<void> _loadVersion() async {
    try {
      final version =
          await (widget.loadVersion?.call() ??
              PackageInfo.fromPlatform().then((info) => info.version));
      if (mounted) setState(() => _version = version);
    } on Object {
      // The rest of the section remains available.
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleSmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('More Better Gakujo', style: titleStyle),
        Text('バージョン ${_version ?? '—'}'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => widget.onOpenUrl(Uri.parse(appPageUrl)),
              icon: const Icon(Icons.open_in_new),
              label: const Text('アプリの説明を開く'),
            ),
            OutlinedButton.icon(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'More Better Gakujo',
                applicationVersion: _version,
                applicationLegalese: 'MIT License\n非公式アプリ',
              ),
              icon: const Icon(Icons.description_outlined),
              label: const Text('オープンソースライセンス'),
            ),
          ],
        ),
      ],
    );
  }
}
