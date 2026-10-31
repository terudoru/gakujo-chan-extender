import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
        const SizedBox(height: 12),
        Text('免責', style: titleStyle),
        const Text(
          '新潟大学および元のブラウザ拡張機能の作者とは関係のない非公式アプリです。学務情報システムの仕様変更により動作しなくなることがあります。本アプリは無保証で提供されます。',
        ),
        const SizedBox(height: 8),
        Text('プライバシー', style: titleStyle),
        const Text(
          'ログイン情報と2FA秘密鍵は端末内の安全な保存領域に保存し、開発者のサーバーへは何も送信しません。通信先は学務情報システム、授業カレンダー連携時の新潟大学公式サイト、アップデート確認時のGitHubだけです。',
        ),
        const SizedBox(height: 8),
        Text('ライセンス', style: titleStyle),
        const Text(
          'MIT License。上流プロジェクト koji-genba/gakujo-chan-extender をもとにしています。',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
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
            OutlinedButton.icon(
              onPressed: () => widget.onOpenUrl(
                Uri.parse('https://github.com/terudoru/gakujo-chan-extender'),
              ),
              icon: const Icon(Icons.code),
              label: const Text('ソースコード'),
            ),
          ],
        ),
      ],
    );
  }
}
