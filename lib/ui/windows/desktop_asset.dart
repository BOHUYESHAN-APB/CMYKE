import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DesktopAsset {
  const DesktopAsset._();

  static Future<String> materializeToFilePath(
    String assetPath, {
    String? filename,
  }) async {
    final data = await rootBundle.load(assetPath);
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, filename ?? p.basename(assetPath)));
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return file.path;
  }
}
