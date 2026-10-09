import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Module tiện ích chuyển đổi Flutter IconData sang định dạng tệp .ico của Windows
class IconUtils {
  /// Chuyển đổi một [IconData] thành mảng byte định dạng Windows ICO (.ico)
  static Future<Uint8List> createIcoBytes(
    IconData icon, {
    Color color = Colors.white,
    double size = 32.0,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size * 0.85,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final offset = Offset(
      (size - textPainter.width) / 2,
      (size - textPainter.height) / 2,
    );
    textPainter.paint(canvas, offset);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception('Không thể xuất dữ liệu hình ảnh sang PNG.');
    }

    final pngBytes = byteData.buffer.asUint8List();
    final builder = BytesBuilder();

    // 1. ICONDIR (6 bytes)
    builder.add([0, 0]); // Reserved
    builder.add([1, 0]); // Resource Type: 1 = Icon
    builder.add([1, 0]); // Số lượng ảnh: 1

    // 2. ICONDIRENTRY (16 bytes)
    builder.addByte(size.toInt()); // bWidth
    builder.addByte(size.toInt()); // bHeight
    builder.addByte(0); // bColorCount
    builder.addByte(0); // bReserved
    builder.add([1, 0]); // wPlanes
    builder.add([32, 0]); // wBitCount (32 bpp ARGB)

    // dwBytesInRes (4 bytes Little Endian)
    final sizeData = ByteData(4)..setUint32(0, pngBytes.length, Endian.little);
    builder.add(sizeData.buffer.asUint8List());

    // dwImageOffset (4 bytes Little Endian) - Vị trí dữ liệu ảnh bắt đầu từ byte 22
    final offsetData = ByteData(4)..setUint32(0, 22, Endian.little);
    builder.add(offsetData.buffer.asUint8List());

    // 3. PNG Payload
    builder.add(pngBytes);

    return builder.toBytes();
  }

  /// Sinh file .ico từ [IconData] và ghi ra ổ đĩa
  static Future<String> ensureIcoFile(
    IconData icon, {
    String? targetPath,
    Color color = Colors.white,
    double size = 42.0,
  }) async {
    final path =
        targetPath ?? '${Directory.systemTemp.path}/gamepad_tray_icon.ico';
    final file = File(path);
    final bytes = await createIcoBytes(icon, color: color, size: size);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file.absolute.path;
  }
}
