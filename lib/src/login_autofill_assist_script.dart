import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'generated/login_autofill_assist.g.dart';
import 'generated/login_autofill_assist_teardown.g.dart';

class LoginAutofillAssistScript {
  const LoginAutofillAssistScript._();

  static const channelName = 'MoreBetterGakujoLoginAutofill';

  static String buildTeardown() {
    return gakujoLoginAutofillAssistTeardownJs;
  }

  static String build({
    GakujoLoginAutofillCredentials? credentials,
    bool debugLogging = false,
  }) {
    final credentialKey = credentials == null
        ? null
        : sha256
              .convert(
                utf8.encode(
                  '${credentials.loginId}\u0000${credentials.password}',
                ),
              )
              .toString();
    return gakujoLoginAutofillAssistJs({
      'debugLogging': debugLogging,
      'savedUsername': credentials?.loginId,
      'savedPassword': credentials?.password,
      'savedCredentialKey': credentialKey,
      'logChannelName': channelName,
    });
  }
}

class GakujoLoginAutofillCredentials {
  const GakujoLoginAutofillCredentials({
    required this.loginId,
    required this.password,
  });

  final String loginId;
  final String password;
}
