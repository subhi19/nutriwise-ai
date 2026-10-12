import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../services/image_saver.dart';

Future<Uint8List?> _capture(GlobalKey key) async {
  try {
    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// Asks "save this as a card?" with a live preview.
/// Yes -> captures the card, saves it as a PNG, returns true.
/// No  -> returns false. The caller decides where to navigate next.
Future<bool> confirmAndSaveCard(
  BuildContext context, {
  required String title,
  required String message,
  required Widget card,
  required String filenamePrefix,
}) async {
  final key = GlobalKey();
  Uint8List? captured;

  final yes = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 12),
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: SingleChildScrollView(
                      child: RepaintBoundary(key: key, child: card),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No, thanks')),
        ElevatedButton(
          onPressed: () async {
            captured = await _capture(key);
            if (ctx.mounted) Navigator.pop(ctx, true);
          },
          child: const Text('Yes, save'),
        ),
      ],
    ),
  );

  if (yes != true) return false;

  final bytes = captured;
  if (bytes == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t create the card image.')),
      );
    }
    return false;
  }

  final message2 = await saveImageBytes(
    bytes,
    '${filenamePrefix}_${DateTime.now().millisecondsSinceEpoch}.png',
  );
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message2)));
  }
  return true;
}