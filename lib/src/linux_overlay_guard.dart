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

/// Replaces GTK's native view with visible page pixels while a route is up.
class LinuxOverlayGuard extends StatefulWidget {
  const LinuxOverlayGuard({
    super.key,
    required this.obscured,
    required this.child,
    this.forceObscured = false,
    this.navigation,
    this.takeSnapshot,
  });

  final ValueListenable<bool>? obscured;
  final bool forceObscured;
  final ValueListenable<int>? navigation;
  final Future<Uint8List?> Function()? takeSnapshot;
  final Widget child;

  @override
  State<LinuxOverlayGuard> createState() => LinuxOverlayGuardState();
}

class LinuxOverlayGuardState extends State<LinuxOverlayGuard> {
  MemoryImage? _snapshot;
  bool _nativeHidden = false;
  bool _capturing = false;
  int _request = 0;
  Future<void> _snapshotReady = Future<void>.value();

  Future<void> get snapshotReady => _snapshotReady;

  bool get _obscured =>
      widget.forceObscured || (widget.obscured?.value ?? false);

  @override
  void initState() {
    super.initState();
    widget.obscured?.addListener(_update);
    widget.navigation?.addListener(_navigationChanged);
    _update();
  }

  @override
  void didUpdateWidget(LinuxOverlayGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.obscured != widget.obscured) {
      oldWidget.obscured?.removeListener(_update);
      widget.obscured?.addListener(_update);
    }
    if (oldWidget.navigation != widget.navigation) {
      oldWidget.navigation?.removeListener(_navigationChanged);
      widget.navigation?.addListener(_navigationChanged);
      _navigationChanged();
    }
    _update();
  }

  void _discardSnapshot() {
    final provider = _snapshot;
    _snapshot = null;
    if (provider != null) unawaited(provider.evict());
  }

  void _navigationChanged() {
    ++_request;
    _capturing = false;
    _discardSnapshot();
    setState(() => _nativeHidden = _obscured);
  }

  bool _isCurrent(int request) =>
      mounted && _capturing && request == _request && _obscured;

  Future<MemoryImage?> _loadSnapshot(
    int request,
    Future<Uint8List?> Function() takeSnapshot,
  ) async {
    final bytes = await takeSnapshot();
    if (!mounted || bytes == null || bytes.isEmpty || !_isCurrent(request)) {
      return null;
    }
    final provider = MemoryImage(
      bytes,
      scale: MediaQuery.devicePixelRatioOf(context),
    );
    var failed = false;
    await precacheImage(
      provider,
      context,
      onError: (error, stackTrace) {
        failed = true;
      },
    );
    if (failed || !_isCurrent(request)) {
      unawaited(provider.evict());
      return null;
    }
    return provider;
  }

  Future<void> _capture(
    int request,
    Future<Uint8List?> Function() takeSnapshot,
  ) async {
    MemoryImage? provider;
    try {
      provider = await _loadSnapshot(
        request,
        takeSnapshot,
      ).timeout(const Duration(milliseconds: 150), onTimeout: () => null);
    } on Object {
      // A hidden, disposed or busy renderer can legitimately have no snapshot.
    }
    if (!_isCurrent(request)) return;
    setState(() {
      _snapshot = provider;
      _capturing = false;
      _nativeHidden = true;
    });
  }

  void _update() {
    if (!_obscured) {
      ++_request;
      _capturing = false;
      _discardSnapshot();
      setState(() => _nativeHidden = false);
      return;
    }
    if (_nativeHidden || _capturing) return;
    final takeSnapshot = widget.takeSnapshot;
    if (takeSnapshot == null) {
      setState(() => _nativeHidden = true);
      return;
    }
    _capturing = true;
    _snapshotReady = _capture(++_request, takeSnapshot);
  }

  @override
  void dispose() {
    widget.obscured?.removeListener(_update);
    widget.navigation?.removeListener(_navigationChanged);
    ++_request;
    _capturing = false;
    _discardSnapshot();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_nativeHidden) return widget.child;
    final provider = _snapshot;
    if (provider == null) return const SizedBox.expand();
    return SizedBox.expand(
      child: Image.memory(
        provider.bytes,
        scale: provider.scale,
        fit: BoxFit.fill,
        gaplessPlayback: true,
        filterQuality: FilterQuality.none,
        excludeFromSemantics: true,
      ),
    );
  }
}
