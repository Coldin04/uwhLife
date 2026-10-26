import 'dart:ui' show Offset;

import 'ids_slider_captcha.dart';

/// Records a pointer stream while the user drags the slider.
///
/// Mirrors the front end: a sample is kept only when at least
/// [minSampleMs] milliseconds and [minSampleDistance] logical pixels have
/// passed since the previous one, so a synthetic 1-pixel flood or a single
/// jump does not look like a real gesture.
class IdsSliderDragRecorder {
  IdsSliderDragRecorder({required this.maxDistance});

  static const int minSampleMs = 20;
  static const double minSampleDistance = 2;

  /// Longest horizontal travel the slider allows.
  final double maxDistance;

  final List<IdsSliderTrack> _tracks = <IdsSliderTrack>[];
  Offset _origin = Offset.zero;
  Duration _sampledAt = Duration.zero;
  double _distance = 0;

  /// Current horizontal travel, clamped to [maxDistance].
  double get distance => _distance;

  /// Samples recorded so far, starting with the mandatory `(0, 0, 0)`.
  List<IdsSliderTrack> get tracks => List<IdsSliderTrack>.unmodifiable(_tracks);

  double start(Offset position, Duration timeStamp) {
    _origin = position;
    _sampledAt = timeStamp;
    _distance = 0;
    _tracks
      ..clear()
      ..add(const IdsSliderTrack(a: 0, b: 0, c: 0));
    return _distance;
  }

  double update(Offset position, Duration timeStamp) {
    _distance = (position.dx - _origin.dx).clamp(0.0, maxDistance);
    final elapsed = timeStamp - _sampledAt;
    final previous = _tracks.last.a;
    if (elapsed.inMilliseconds >= minSampleMs &&
        (_distance - previous).abs() >= minSampleDistance) {
      _sampledAt = timeStamp;
      _tracks.add(
        IdsSliderTrack(
          a: _distance.round(),
          b: (position.dy - _origin.dy).round(),
          c: elapsed.inMilliseconds,
        ),
      );
    }
    return _distance;
  }

  /// Closes the gesture and returns `null` when the drag was too short to be
  /// worth submitting.
  IdsSliderAnswer? finish(
    Offset position,
    Duration timeStamp, {
    required int canvasLength,
  }) {
    update(position, timeStamp);
    final moveLength = _distance.round();
    if (moveLength < 4) return null;

    final elapsed = timeStamp - _sampledAt;
    final duration = elapsed.inMilliseconds < minSampleMs
        ? minSampleMs
        : elapsed.inMilliseconds;
    if (_tracks.last.a != moveLength || _tracks.length == 1) {
      _tracks.add(
        IdsSliderTrack(
          a: moveLength,
          b: (position.dy - _origin.dy).round(),
          c: duration,
        ),
      );
    }
    return IdsSliderAnswer(
      canvasLength: canvasLength,
      moveLength: moveLength,
      tracks: List<IdsSliderTrack>.unmodifiable(_tracks),
    );
  }
}
