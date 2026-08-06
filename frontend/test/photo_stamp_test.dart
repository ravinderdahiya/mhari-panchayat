import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mhari_panchayat/utils/photo_stamp.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stamp() produces a JPEG every client can decode', () async {
    final source = img.Image(width: 320, height: 240);
    img.fill(source, color: img.ColorRgb8(90, 140, 90));
    final sourceBytes = Uint8List.fromList(img.encodePng(source));

    final stamped = await PhotoStamp.stamp(
      bytes: sourceBytes,
      latitude: 29.703398,
      longitude: 76.984200,
    );

    final decoded = img.decodeJpg(stamped);

    expect(decoded, isNotNull, reason: 'stamped output must be a valid, decodable JPEG');
    expect(decoded!.width, 320);
    expect(decoded.height, 240);
  });
}
