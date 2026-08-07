import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

/// Opens a full-screen preview of a photo (already in memory, or fetched
/// from the backend) with a download action. Pass exactly one of [bytes] or
/// [imageUrl].
///
/// GPS / datetime already burned into the image by [PhotoStamp] are left as-is;
/// this viewer does not draw a second metadata strip under the photo.
Future<void> showPhotoViewer(
  BuildContext context, {
  Uint8List? bytes,
  String? imageUrl,
}) {
  assert(bytes != null || imageUrl != null);
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _PhotoViewerScreen(bytes: bytes, imageUrl: imageUrl),
    ),
  );
}

class _PhotoViewerScreen extends StatefulWidget {
  const _PhotoViewerScreen({this.bytes, this.imageUrl});

  final Uint8List? bytes;
  final String? imageUrl;

  @override
  State<_PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<_PhotoViewerScreen> {
  bool _saving = false;
  Uint8List? _cachedBytes;

  Future<Uint8List?> _resolveBytes() async {
    if (_cachedBytes != null) return _cachedBytes;
    if (widget.bytes != null) return _cachedBytes = widget.bytes;

    final url = widget.imageUrl;
    if (url == null) return null;

    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    return _cachedBytes = response.bodyBytes;
  }

  Future<void> _download() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await _resolveBytes();
      if (bytes == null) {
        _showMessage('फोटो डाउनलोड नहीं हो पाई। पुनः प्रयास करें।');
        return;
      }

      final granted =
          await Gal.hasAccess(toAlbum: true) ||
          await Gal.requestAccess(toAlbum: true);
      if (!granted) {
        _showMessage('फोटो सेव करने के लिए परमिशन आवश्यक है');
        return;
      }

      await Gal.putImageBytes(
        bytes,
        album: 'Mhari Panchayat',
        name: 'mhari_panchayat_${DateTime.now().millisecondsSinceEpoch}',
      );
      _showMessage('फोटो गैलरी में सेव हो गई');
    } catch (_) {
      _showMessage('फोटो सेव नहीं हो पाई। पुनः प्रयास करें।');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.poppins())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bytes = widget.bytes;
    final url = widget.imageUrl;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.download_rounded, color: Colors.white),
              tooltip: 'Download',
              onPressed: _download,
            ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: bytes != null
              ? Image.memory(bytes)
              : Image.network(
                  url!,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_rounded,
                    color: Colors.white54,
                    size: 64,
                  ),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const CircularProgressIndicator(color: Colors.white);
                  },
                ),
        ),
      ),
    );
  }
}
