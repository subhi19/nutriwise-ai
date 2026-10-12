import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'webcam_capture_dialog.dart';

bool get _isDesktopWeb =>
    kIsWeb &&
    const {TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux}
        .contains(defaultTargetPlatform);

Future<Uint8List?> _fromImagePicker(ImageSource source) async {
  final x = await ImagePicker().pickImage(source: source, maxWidth: 1024, imageQuality: 80);
  return x == null ? null : await x.readAsBytes();
}

/// One place for every "Camera" / "Gallery" button.
/// - Phone (app or mobile browser): opens the camera app directly.
/// - Desktop browser: opens a webcam capture dialog.
/// - Gallery: opens the file chooser.
Future<Uint8List?> pickPhoto(BuildContext context, ImageSource source) async {
  if (source == ImageSource.camera && _isDesktopWeb) {
    final result = await showDialog<Object?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const WebcamCaptureDialog(),
    );
    if (result is Uint8List) return result;
    if (result == 'files') return _fromImagePicker(ImageSource.gallery);
    return null;
  }
  return _fromImagePicker(source);
}