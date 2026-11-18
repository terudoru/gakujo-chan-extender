import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> writePreviewClipboard(String text) =>
    _postAction('clipboard', text);

Future<void> openPreviewLink(Uri url) =>
    _postAction('open-link', url.toString());

/// The token-protected loopback server performs native actions and returns
/// only a status. Clipboard and document contents are never returned.
Future<void> _postAction(String action, String text) async {
  final abort = web.AbortController();
  final headers = web.Headers()
    ..set('Content-Type', 'text/plain; charset=utf-8');
  final timer = Timer(const Duration(seconds: 10), () => abort.abort());
  try {
    final response = await web.window
        .fetch(
          Uri.base.resolve(action).toString().toJS,
          web.RequestInit(
            method: 'POST',
            headers: headers,
            body: text.toJS,
            signal: abort.signal,
            credentials: 'omit',
            cache: 'no-store',
          ),
        )
        .toDart;
    if (!response.ok) throw StateError('Viewer action failed');
  } finally {
    timer.cancel();
  }
}
