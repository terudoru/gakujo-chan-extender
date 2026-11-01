class GakujoLoginObserverScript {
  const GakujoLoginObserverScript._();

  static String build() => r'''
(function() {
  if (window.__MBG_LOGIN_OBSERVER_INSTALLED) return;
  window.__MBG_LOGIN_OBSERVER_INSTALLED = true;

  function report(form) {
    if (!form || form.querySelectorAll('input[type="password"]').length !== 1) return;
    var inputs = form.querySelectorAll('input');
    var username = null;
    for (var i = 0; i < inputs.length; i += 1) {
      var type = (inputs[i].getAttribute('type') || 'text').toLowerCase();
      if (type !== 'text' && type !== 'email' && type !== 'tel') continue;
      var identifiers = [inputs[i].getAttribute('name'), inputs[i].getAttribute('id')];
      if (identifiers.some(function(identifier) {
        return ['userid', 'loginid', 'username', 'jusername'].indexOf(
          (identifier || '').toLowerCase().replace(/[\s_-]+/g, '')
        ) !== -1;
      })) {
        username = inputs[i];
        break;
      }
    }
    var loginId = username ? username.value.trim() : '';
    if (!loginId) return;
    var channel = window.GakujoMessageStars;
    if (channel && channel.postMessage) {
      channel.postMessage(JSON.stringify({
        type: 'gakujoLoginSubmitted',
        loginId: loginId
      }));
    }
  }

  document.addEventListener('submit', function(event) {
    report(event.target);
  }, true);
  document.addEventListener('click', function(event) {
    var button = event.target.closest('button, input');
    if (!button) return;
    var type = (button.getAttribute('type') ||
      (button.tagName.toLowerCase() === 'button' ? 'submit' : '')).toLowerCase();
    if (type === 'submit' || type === 'image') report(button.form);
  }, true);
})();
''';
}
