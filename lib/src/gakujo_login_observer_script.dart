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

  // Report only a submission the page let through: a click on the submit
  // button may still be stopped by validation or a page handler. Bubble phase
  // runs after the form's own handlers, so defaultPrevented is settled.
  document.addEventListener('submit', function(event) {
    if (!event.defaultPrevented) report(event.target);
  }, false);
  // form.submit() fires no submit event.
  var proto = window.HTMLFormElement && window.HTMLFormElement.prototype;
  if (proto && typeof proto.submit === 'function') {
    var submit = proto.submit;
    proto.submit = function() {
      report(this);
      return submit.apply(this, arguments);
    };
  }
})();
''';
}
