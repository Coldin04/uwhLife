import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ScheduleFileExporter {
  const ScheduleFileExporter._();

  static const _documentExportChannel = MethodChannel(
    'uwhlife/document_export',
  );

  static Future<void> saveOrShare(
    BuildContext context, {
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String title,
    required String subject,
    bool chooseLocationOnIOS = false,
  }) async {
    final screenSize = MediaQuery.sizeOf(context);
    final origin = Rect.fromLTWH(
      (screenSize.width - 56).clamp(0, screenSize.width).toDouble(),
      8,
      48,
      48,
    );
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    if (Platform.isIOS && chooseLocationOnIOS) {
      await _documentExportChannel.invokeMethod<void>(
        'exportFile',
        <String, Object>{'sourcePath': file.path, 'fileName': fileName},
      );
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        title: title,
        subject: subject,
        files: <XFile>[XFile(file.path, mimeType: mimeType)],
        fileNameOverrides: <String>[fileName],
        sharePositionOrigin: origin,
      ),
    );
  }
}
