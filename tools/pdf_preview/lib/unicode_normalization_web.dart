import 'dart:js_interop';

@JS('String.prototype.normalize.call')
external JSString _normalize(JSString value, JSString form);

String normalizeSearchText(String value) =>
    _normalize(value.toJS, 'NFKC'.toJS).toDart;
