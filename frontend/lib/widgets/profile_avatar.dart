import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../services/auth_api.dart';

/// The round avatar on every profile header, with the pencil badge that lets
/// the signed-in user set (or remove) their picture from the phone's gallery.
///
/// It keeps the picture it just uploaded itself, so the header updates at once;
/// a different [photoUrl] from the parent (after a reload) replaces it.
class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar({
    super.key,
    required this.photoUrl,
    required this.accent,
    this.radius = 40,
    this.badgeColor,
    this.background = const Color(0xFFE9F0E6),
  });

  final String? photoUrl;

  /// Colour of the default person icon and the pencil badge.
  final Color accent;
  final double radius;

  /// Pencil badge colour; defaults to [accent].
  final Color? badgeColor;
  final Color background;

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  final _picker = ImagePicker();
  String? _url;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _url = widget.photoUrl;
  }

  @override
  void didUpdateWidget(ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoUrl != widget.photoUrl) _url = widget.photoUrl;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showOptions() async {
    if (_busy) return;
    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: Text('गैलरी से फोटो चुनें', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.of(sheetContext).pop(_PhotoAction.gallery),
            ),
            if (_url != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: Text('फोटो हटाएं', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.red)),
                onTap: () => Navigator.of(sheetContext).pop(_PhotoAction.remove),
              ),
          ],
        ),
      ),
    );

    switch (action) {
      case _PhotoAction.gallery:
        await _pickAndUpload();
      case _PhotoAction.remove:
        await _remove();
      case null:
        break;
    }
  }

  Future<void> _pickAndUpload() async {
    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
    } catch (_) {
      _toast('फोटो चुनी नहीं जा सकी।');
      return;
    }
    if (picked == null) return;

    setState(() => _busy = true);
    try {
      final bytes = await picked.readAsBytes();
      final profile = await AuthApi.uploadProfilePhoto(
        bytes: bytes,
        fileName: picked.name.isEmpty ? 'profile.jpg' : picked.name,
      );
      if (!mounted) return;
      setState(() => _url = profile.photoUrl);
      _toast('प्रोफ़ाइल फोटो अपडेट हो गई।');
    } on AuthApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('फोटो अपलोड नहीं हो पाई। पुनः प्रयास करें।');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      final profile = await AuthApi.removeProfilePhoto();
      if (!mounted) return;
      setState(() => _url = profile.photoUrl);
      _toast('प्रोफ़ाइल फोटो हटा दी गई।');
    } on AuthApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('फोटो हटाई नहीं जा सकी। पुनः प्रयास करें।');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final diameter = widget.radius * 2;
    final fallback = Icon(Icons.person_rounded, color: widget.accent, size: widget.radius * 1.15);

    return Semantics(
      button: true,
      label: 'Change profile photo',
      child: GestureDetector(
        onTap: _showOptions,
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 3)),
                ],
              ),
              child: ClipOval(
                child: SizedBox(
                  width: diameter,
                  height: diameter,
                  child: ColoredBox(
                    color: widget.background,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_url == null)
                          Center(child: fallback)
                        else
                          Image.network(
                            _url!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Center(child: fallback),
                            loadingBuilder: (_, child, progress) =>
                                progress == null ? child : Center(child: fallback),
                          ),
                        if (_busy)
                          ColoredBox(
                            color: Colors.black.withValues(alpha: 0.35),
                            child: const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: widget.badgeColor ?? widget.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.edit_rounded, color: Colors.white, size: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PhotoAction { gallery, remove }
