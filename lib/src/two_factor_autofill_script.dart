import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'generated/two_factor_autofill.g.dart';
import 'generated/two_factor_autofill_teardown.g.dart';

class TwoFactorAutofillScript {
  static const inputName = 'ninshoCode';

  const TwoFactorAutofillScript._();

  static String buildTeardown() {
    return gakujoTwoFactorAutofillTeardownJs;
  }

  static String build({
    required String token,
    String? secret,
    int maxAttempts = 20,
    int intervalMillis = 250,
    bool autoSubmit = true,
    bool debugLogging = false,
  }) {
    return _build(
      token: token,
      secret: secret,
      maxAttempts: maxAttempts,
      intervalMillis: intervalMillis,
      autoSubmit: autoSubmit,
      debugLogging: debugLogging,
      debugFixture: false,
    );
  }

  /// The local Android QA page receives only a public synthetic value.
  static String buildDebugFixture() => _build(
    token: '123456',
    secret: null,
    maxAttempts: 20,
    intervalMillis: 250,
    autoSubmit: true,
    debugLogging: true,
    debugFixture: true,
  );

  static String _build({
    required String token,
    required String? secret,
    required int maxAttempts,
    required int intervalMillis,
    required bool autoSubmit,
    required bool debugLogging,
    required bool debugFixture,
  }) {
    if (maxAttempts <= 0) {
      throw ArgumentError.value(maxAttempts, 'maxAttempts', 'must be positive');
    }
    if (intervalMillis <= 0) {
      throw ArgumentError.value(
        intervalMillis,
        'intervalMillis',
        'must be positive',
      );
    }

    final secretKey = secret == null
        ? 'no-secret'
        : sha256.convert(utf8.encode(secret)).toString();
    return gakujoTwoFactorAutofillJs({
      'debugFixture': debugFixture,
      'debugLogging': debugLogging,
      'maxAttempts': maxAttempts,
      'intervalMillis': intervalMillis,
      'token': token,
      'secretKey': secretKey,
      'autoSubmit': autoSubmit,
      'inputName': inputName,
    });
  }
}
