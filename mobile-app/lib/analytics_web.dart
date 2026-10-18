import 'dart:js_interop';

@JS('gtag')
external void _gtag(String command, String name, [JSAny? params]);

void logEvent(String name, [Map<String, Object>? params]) {
  try {
    _gtag('event', name, params?.jsify());
  } catch (_) {
    // analytics must never break the app
  }
}