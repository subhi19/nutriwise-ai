import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'inline_error.dart';

/// Desktop-browser camera capture.
/// Pops with the photo bytes, or with 'files' if the user prefers to pick a file.
class WebcamCaptureDialog extends StatefulWidget {
  const WebcamCaptureDialog({super.key});

  @override
  State<WebcamCaptureDialog> createState() => _WebcamCaptureDialogState();
}

class _WebcamCaptureDialogState extends State<WebcamCaptureDialog> {
  CameraController? _controller;
  String? _error;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    _startCamera();
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = 'No camera was found on this device.');
        return;
      }
      final controller = CameraController(cameras.first, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException catch (e) {
      if (!mounted) return;
      final denied = e.code.toLowerCase().contains('denied');
      setState(() => _error = denied
          ? 'Camera access is blocked. Allow it using the camera icon in your browser\'s address bar, then try again.'
          : 'We couldn\'t start the camera (${e.code}).');
    } catch (_) {
      if (mounted) setState(() => _error = 'We couldn\'t start the camera.');
    }
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || _capturing) return;
    setState(() => _capturing = true);
    try {
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) Navigator.pop(context, bytes);
    } catch (_) {
      if (mounted) {
        setState(() {
          _capturing = false;
          _error = 'The photo couldn\'t be taken. Please try again.';
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Take a photo', style: Theme.of(context).textTheme.titleMedium)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_error != null)
                InlineError(_error!)
              else if (c == null)
                const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                )
              else
                ClipRRect(borderRadius: BorderRadius.circular(14), child: CameraPreview(c)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, 'files'),
                      child: const Text('Choose a file'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: _capturing
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.camera_alt_outlined),
                      label: const Text('Capture'),
                      onPressed: (c == null || _capturing) ? null : _capture,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}