import 'package:flutter/material.dart';
import 'package:webview_flutter_linux/webview_flutter_linux.dart';

class LinuxDownloadStrip extends StatefulWidget {
  const LinuxDownloadStrip({
    super.key,
    required this.progress,
    required this.onCancel,
  });

  final LinuxDownloadProgress progress;
  final Future<void> Function() onCancel;

  @override
  State<LinuxDownloadStrip> createState() => _LinuxDownloadStripState();
}

class _LinuxDownloadStripState extends State<LinuxDownloadStrip> {
  bool _cancelling = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final progress = widget.progress;
    final fraction = progress.fraction;
    final amount = fraction == null
        ? _formatBytes(progress.bytesReceived)
        : '${(fraction * 100).floor()}%';
    return Material(
      color: colors.inverseSurface,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    '${progress.fileName} — $amount',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium!
                        .copyWith(color: colors.onInverseSurface),
                  ),
                ),
              ),
              TextButton(
                onPressed: _cancelling ? null : _cancel,
                style: TextButton.styleFrom(
                  foregroundColor: colors.inversePrimary,
                ),
                child: const Text('キャンセル'),
              ),
            ],
          ),
          LinearProgressIndicator(value: fraction, minHeight: 2),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    const megabyte = 1024 * 1024;
    return bytes < megabyte
        ? '${(bytes / 1024).toStringAsFixed(1)} KB'
        : '${(bytes / megabyte).toStringAsFixed(1)} MB';
  }

  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    try {
      await widget.onCancel();
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }
}
