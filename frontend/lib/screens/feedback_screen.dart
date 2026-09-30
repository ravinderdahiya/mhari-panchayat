import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../services/feedback_api.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/photo_viewer.dart';

const _kCategories = <String, String>{
  'bug': 'Bug',
  'suggestion': 'Suggestion',
  'complaint': 'Complaint',
  'general': 'General',
};

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _imagePicker = ImagePicker();
  final _messageController = TextEditingController();
  String _category = 'general';
  int? _rating;
  Uint8List? _photo;
  bool _submitting = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickPhoto() async {
    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (photo == null) return;
      final bytes = await photo.readAsBytes();
      if (mounted) setState(() => _photo = bytes);
    } catch (_) {
      _showMessage('Photo चुना नहीं जा सका।');
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final message = _messageController.text.trim();
    if (message.length < 5) {
      _showMessage('कृपया कम से कम 5 अक्षरों में feedback लिखें');
      return;
    }

    setState(() => _submitting = true);
    try {
      await FeedbackApi.submit(
        category: _category,
        message: message,
        rating: _rating,
        photo: _photo,
      );
      if (!mounted) return;
      _showMessage('धन्यवाद! आपका feedback भेज दिया गया है।');
      Navigator.of(context).maybePop();
    } on FeedbackApiException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'App Feedback',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 28),
        children: [
          Text(
            'आपका feedback',
            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'App में कोई दिक्कत हो या सुझाव देना हो, यहाँ बताएं।',
            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.mutedText),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            initialValue: _category,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Category *',
              prefixIcon: Icon(Icons.category_outlined),
            ),
            items: [
              for (final entry in _kCategories.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) => setState(() => _category = value ?? _category),
          ),
          const SizedBox(height: 16),
          Text('Rating (optional)', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () => setState(() => _rating = _rating == i ? null : i),
                  icon: Icon(
                    i <= (_rating ?? 0) ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _messageController,
            minLines: 4,
            maxLines: 7,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: 'Message *',
              hintText: 'यहाँ लिखें…',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes_rounded),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Screenshot (optional)',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (_photo == null)
            OutlinedButton.icon(
              onPressed: _pickPhoto,
              icon: const Icon(Icons.image_outlined),
              label: const Text('Attach screenshot'),
            )
          else
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: () => showPhotoViewer(context, bytes: _photo!),
                    child: Image.memory(_photo!, width: 100, height: 100, fit: BoxFit.cover),
                  ),
                ),
                Positioned(
                  right: 2,
                  top: 2,
                  child: IconButton.filled(
                    onPressed: () => setState(() => _photo = null),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.rejectedText,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(28, 28),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_submitting ? 'भेजा जा रहा है…' : 'Feedback भेजें'),
            ),
          ),
        ],
      ),
    );
  }
}
