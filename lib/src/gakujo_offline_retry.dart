import 'dart:async';
import 'dart:io';

Future<bool> probeGakujoReachability() async {
  const host = 'gakujo.iess.niigata-u.ac.jp';
  const timeout = Duration(seconds: 3);
  try {
    final addresses = await InternetAddress.lookup(host).timeout(timeout);
    if (addresses.isEmpty) {
      return false;
    }
    // Connect by name so both IPv4 and IPv6 addresses can be tried.
    final socket = await Socket.connect(host, 443, timeout: timeout);
    socket.destroy();
    return true;
  } on SocketException {
    return false;
  } on TimeoutException {
    return false;
  }
}

class GakujoOfflineRetry {
  GakujoOfflineRetry({
    required this._probe,
    required this._onReachable,
    DateTime Function()? now,
  })  : _now = now ?? DateTime.now;

  final Future<bool> Function() _probe;
  final void Function() _onReachable;
  final DateTime Function() _now;
  Timer? _timer;
  Timer? _deadlineTimer;
  DateTime? _deadline;
  int _generation = 0;
  bool _checking = false;

  bool get isActive => _timer != null;

  void start() {
    if (isActive) {
      return;
    }
    final generation = ++_generation;
    _deadline = _now().add(const Duration(minutes: 10));
    _deadlineTimer = Timer(const Duration(minutes: 10), cancel);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_check(generation));
    });
  }

  void cancel() {
    _generation += 1;
    _timer?.cancel();
    _timer = null;
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    _deadline = null;
  }

  Future<void> _check(int generation) async {
    if (!isActive || generation != _generation) {
      return;
    }
    if (!_now().isBefore(_deadline!)) {
      cancel();
      return;
    }
    if (_checking) {
      return;
    }
    _checking = true;
    var reachable = false;
    try {
      reachable = await _probe();
    } on Object {
      // A failed probe leaves the next periodic check in charge.
    } finally {
      _checking = false;
    }
    if (!isActive || generation != _generation) {
      return;
    }
    if (!_now().isBefore(_deadline!)) {
      cancel();
      return;
    }
    if (reachable) {
      cancel();
      _onReachable();
    }
  }
}
