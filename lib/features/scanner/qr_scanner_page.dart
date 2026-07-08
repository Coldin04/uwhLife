import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final ImagePicker _imagePicker = ImagePicker();
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const [BarcodeFormat.qrCode, BarcodeFormat.code128],
  );
  bool _handled = false;
  bool _pickingImage = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw != null && raw.isNotEmpty) {
        _handled = true;
        Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  Future<void> _pickImageAndScan() async {
    if (_handled || _pickingImage) return;
    _pickingImage = true;
    try {
      await _scanner.stop();
      final image = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (image == null) {
        if (mounted) {
          await _scanner.start();
        }
        return;
      }

      final capture = await _scanner.analyzeImage(image.path);
      if (!mounted) return;

      String? value;
      if (capture != null) {
        for (final barcode in capture.barcodes) {
          final raw = barcode.rawValue;
          if (raw != null && raw.isNotEmpty) {
            value = raw;
            break;
          }
        }
      }

      if (value != null) {
        _handled = true;
        Navigator.of(context).pop(value);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这张图片里没有识别到二维码/条形码')),
      );
      await _scanner.start();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('打开相册失败，请重试')),
      );
      await _scanner.start();
    } finally {
      _pickingImage = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _scanner,
              onDetect: _onDetect,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _ScannerOverlayPainter()),
            ),
          ),
          Positioned(
            top: topInset + 8,
            left: 12,
            child: _CircleActionButton(
              icon: Icons.close_rounded,
              onTap: () => Navigator.of(context).pop(),
              semanticLabel: '关闭',
            ),
          ),
          Positioned(
            top: topInset + 8,
            right: 12,
            child: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _scanner,
              builder: (_, state, _) {
                final on = state.torchState == TorchState.on;
                return _CircleActionButton(
                  icon: on
                      ? Icons.flash_on_rounded
                      : Icons.flash_off_rounded,
                  onTap: () => _scanner.toggleTorch(),
                  semanticLabel: '手电',
                );
              },
            ),
          ),
          Positioned(
            left: 12,
            bottom: 72,
            child: _CircleActionButton(
              icon: Icons.photo_library_outlined,
              onTap: _pickImageAndScan,
              semanticLabel: '相册',
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 80,
            child: Center(
              child: Text(
                '将二维码 / 条形码对准扫描框',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleActionButton extends StatelessWidget {
  const _CircleActionButton({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.88),
      shape: const CircleBorder(),
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: Icon(
              icon,
              size: 18,
              color: const Color(0xFF111111),
              semanticLabel: semanticLabel,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final boxSize = (size.shortestSide * 0.7).clamp(220.0, 360.0);
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: boxSize,
      height: boxSize,
    );
    final outer = Path()..addRect(Offset.zero & size);
    final inner = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(18)));
    final mask = Path.combine(PathOperation.difference, outer, inner);
    canvas.drawPath(mask, Paint()..color = Colors.black.withValues(alpha: 0.55));

    final corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const len = 22.0;
    final r = rect;
    canvas.drawLine(r.topLeft, r.topLeft + const Offset(len, 0), corner);
    canvas.drawLine(r.topLeft, r.topLeft + const Offset(0, len), corner);
    canvas.drawLine(r.topRight, r.topRight + const Offset(-len, 0), corner);
    canvas.drawLine(r.topRight, r.topRight + const Offset(0, len), corner);
    canvas.drawLine(r.bottomLeft, r.bottomLeft + const Offset(len, 0), corner);
    canvas.drawLine(r.bottomLeft, r.bottomLeft + const Offset(0, -len), corner);
    canvas.drawLine(r.bottomRight, r.bottomRight + const Offset(-len, 0), corner);
    canvas.drawLine(r.bottomRight, r.bottomRight + const Offset(0, -len), corner);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
