import 'dart:typed_data';
import 'dart:ui' as ui;

Future<(int, int)?> imageDimensions(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;
      frame.image.dispose();
      return (w, h);
    } finally {
      codec.dispose();
    }
  } catch (_) {
    return null;
  }
}
