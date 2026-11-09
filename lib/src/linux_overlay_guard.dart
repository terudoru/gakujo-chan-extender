import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Tracks routes above the main page until their exit animations finish.
class LinuxOverlayObserver extends NavigatorObserver {
  final ValueNotifier<bool> obscured = ValueNotifier<bool>(false);
  final Set<Route<dynamic>> _routes = {};
  bool _disposed = false;

  void _add(Route<dynamic> route) {
    _routes.add(route);
    _update();
  }

  void _remove(Route<dynamic> route) {
    _routes.remove(route);
    _update();
  }

  void _update() {
    if (!_disposed) obscured.value = _routes.isNotEmpty;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is TransitionRoute<dynamic>) {
      unawaited(route.completed.then((_) => _remove(route)));
    } else {
      _remove(route);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null && _routes.remove(oldRoute) && newRoute != null) {
      _routes.add(newRoute);
    }
    _update();
  }

  void dispose() {
    _disposed = true;
    obscured.dispose();
  }
}

/// GTK WebViews sit above Flutter, so remove their widget while a route is up.
class LinuxOverlayGuard extends StatelessWidget {
  const LinuxOverlayGuard({
    super.key,
    required this.obscured,
    required this.child,
  });

  final ValueListenable<bool> obscured;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: obscured,
        child: child,
        builder: (context, hidden, child) =>
            hidden ? const SizedBox.expand() : child!,
      );
}
