import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Burns a GPS Map Camera-style date/time + Lat/Lng overlay into a captured
/// photo, matching the stamped photos field staff are used to from other
/// survey apps.
class PhotoStamp {
  PhotoStamp._();

  static Future<Uint8List> stamp({
    required Uint8List bytes,
    required double latitude,
    required double longitude,
    DateTime? timestamp,
  }) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final width = image.width.toDouble();
    final height = image.height.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
    canvas.drawImage(image, Offset.zero, Paint());

    final dt = timestamp ?? DateTime.now();
    final dateLine =
        '${dt.day}/${dt.month}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final geoLine =
        'Lat: ${latitude.toStringAsFixed(6)}, Lng: ${longitude.toStringAsFixed(6)}';

    final fontSize = (width * 0.032).clamp(20.0, 40.0);
    final padding = fontSize * 0.7;

    final paragraphBuilder =
        ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: fontSize, height: 1.4))
          ..pushStyle(
            ui.TextStyle(
              color: const Color(0xFF212121),
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
            ),
          )
          ..addText('$dateLine\n$geoLine');

    final paragraph = paragraphBuilder.build()
      ..layout(ui.ParagraphConstraints(width: width - padding * 2));

    final barHeight = paragraph.height + padding * 2;
    final barTop = height - barHeight;

    canvas.drawRect(
      Rect.fromLTWH(0, barTop, width, barHeight),
      Paint()..color = const Color(0xE6F5F5F5),
    );
    canvas.drawParagraph(paragraph, Offset(padding, barTop + padding));

    final picture = recorder.endRecording();
    final stamped = await picture.toImage(image.width, image.height);
    final rawBytes = await stamped.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );

    // Re-encoded as JPEG rather than PNG — a lossless PNG of a full photo
    // routinely blew past the 8MB upload limit, since dart:ui can only
    // produce PNG/raw output directly.
    final rgbaImage = img.Image.fromBytes(
      width: stamped.width,
      height: stamped.height,
      bytes: rawBytes!.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    final result = Uint8List.fromList(img.encodeJpg(rgbaImage, quality: 82));

    // Release native/GPU buffers immediately. Several photos may be retained
    // by the form, so waiting for GC here can otherwise cause an Android OOM.
    stamped.dispose();
    picture.dispose();
    image.dispose();
    codec.dispose();
    return result;
  }
}
