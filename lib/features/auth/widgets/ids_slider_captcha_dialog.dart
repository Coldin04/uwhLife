import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../ids_slider_captcha.dart';
import '../ids_slider_recorder.dart';

/// Shows the IDS puzzle slider and lets the user drag it by hand.
///
/// The widget only collects the gesture: it returns an [IdsSliderAnswer] and
/// leaves signing/verification to `IdsHttpAuthClient`.
class IdsSliderCaptchaDialog extends StatefulWidget {
  const IdsSliderCaptchaDialog({
    super.key,
    required this.challenge,
    this.message,
  });

  final IdsSliderChallenge challenge;

  /// Optional hint shown above the picture (for example after a failed try).
  final String? message;

  /// Test hook: the draggable bar.
  static const Key sliderBarKey = ValueKey<String>('ids-slider-captcha-bar');

  static Future<IdsSliderAnswer?> show(
    BuildContext context,
    IdsSliderChallenge challenge, {
    String? message,
  }) {
    return showDialog<IdsSliderAnswer>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          IdsSliderCaptchaDialog(challenge: challenge, message: message),
    );
  }

  @override
  State<IdsSliderCaptchaDialog> createState() => _IdsSliderCaptchaDialogState();
}

class _IdsSliderCaptchaDialogState extends State<IdsSliderCaptchaDialog> {
  static const double _maxCanvasWidth = 280;
  static const double _knobSize = 42;
  static const double _barHeight = 46;

  Size? _imageSize;
  IdsSliderDragRecorder? _recorder;
  double _drag = 0;
  double _canvasWidth = _maxCanvasWidth;
  bool _dragging = false;
  String? _hint;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  Future<void> _loadImageSize() async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      widget.challenge.bigImage,
    );
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size = Size(
      descriptor.width.toDouble(),
      descriptor.height.toDouble(),
    );
    descriptor.dispose();
    buffer.dispose();
    if (!mounted) return;
    setState(() => _imageSize = size);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '安全验证',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: wBold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '取消',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            if (widget.message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  widget.message!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              '拖动下方滑块，把拼图补进缺口',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.66),
              ),
            ),
            const SizedBox(height: 12),
            _buildCanvas(theme),
            const SizedBox(height: 10),
            SizedBox(
              height: 18,
              child: Center(
                child: Text(
                  _hint ?? '',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvas(ThemeData theme) {
    final imageSize = _imageSize;
    if (imageSize == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasWidth = math.min(constraints.maxWidth, _maxCanvasWidth);
        final scale = canvasWidth / imageSize.width;
        final canvasHeight = imageSize.height * scale;
        final pieceWidth = math.max(1.0, widget.challenge.tagWidth * scale);
        final maxDrag = math.max(1.0, canvasWidth - pieceWidth);
        _canvasWidth = canvasWidth;
        final recorder = _recorder;
        if (recorder == null || recorder.maxDistance != maxDrag) {
          _recorder = IdsSliderDragRecorder(maxDistance: maxDrag);
          _drag = 0;
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: canvasWidth,
                height: canvasHeight,
                child: Stack(
                  children: [
                    Image.memory(
                      widget.challenge.bigImage,
                      width: canvasWidth,
                      height: canvasHeight,
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                    ),
                    Positioned(
                      left: _drag,
                      top: 0,
                      width: pieceWidth,
                      height: canvasHeight,
                      child: Image.memory(
                        widget.challenge.smallImage,
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _buildSliderBar(theme, canvasWidth, maxDrag),
          ],
        );
      },
    );
  }

  Widget _buildSliderBar(ThemeData theme, double width, double maxDrag) {
    final scheme = theme.colorScheme;
    final travel = math.max(0.0, width - _knobSize);
    final knobLeft = maxDrag <= 0 ? 0.0 : (_drag / maxDrag) * travel;

    return Listener(
      key: IdsSliderCaptchaDialog.sliderBarKey,
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (_dragging) return;
        setState(() {
          _dragging = true;
          _hint = null;
          _drag = _recorder?.start(event.localPosition, event.timeStamp) ?? 0;
        });
      },
      onPointerMove: (event) {
        if (!_dragging) return;
        final recorder = _recorder;
        if (recorder == null) return;
        setState(
          () => _drag = recorder.update(event.localPosition, event.timeStamp),
        );
      },
      onPointerUp: _finishDrag,
      onPointerCancel: (_) {
        setState(() {
          _dragging = false;
          _drag = 0;
        });
      },
      child: SizedBox(
        width: width,
        height: _barHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(_barHeight / 2),
            border: Border.all(color: scheme.onSurface.withValues(alpha: 0.12)),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 14,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Text(
                    '向右滑动填充拼图',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.42),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: knobLeft,
                top: 2,
                width: _knobSize,
                height: _knobSize,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: brandGreen,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: brandGreen.withValues(alpha: 0.32),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.drag_handle_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _finishDrag(PointerUpEvent event) {
    final recorder = _recorder;
    if (recorder == null) return;
    final answer = recorder.finish(
      event.localPosition,
      event.timeStamp,
      canvasLength: _canvasWidth.round(),
    );
    setState(() {
      _dragging = false;
      if (answer == null) {
        _drag = 0;
        _hint = '请按住滑块向右拖动';
      }
    });
    if (answer == null) return;
    Navigator.of(context).pop(answer);
  }
}
