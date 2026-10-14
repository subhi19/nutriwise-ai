import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

export 'image_saver_stub.dart' if (dart.library.js_interop) 'image_saver_web.dart';

Future<String> saveImageBytes(Uint8List bytes, String filename) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'image/png'),
  );
  final url = web.URL.createObjectURL(blob);

  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;
  anchor.click();

  web.URL.revokeObjectURL(url);
  return 'Downloaded to your browser\'s Downloads folder';
}

