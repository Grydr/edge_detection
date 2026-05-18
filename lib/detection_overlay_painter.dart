import 'package:flutter/material.dart';
class DetectionOverlayPainter extends CustomPainter {
  final List<dynamic> detections;
  final Size sourceSize;

  DetectionOverlayPainter(this.detections, this.sourceSize);

  @override
  void paint(Canvas canvas, Size size) {
    if (sourceSize.width <= 0 || sourceSize.height <= 0) return;

    final fitted = applyBoxFit(BoxFit.contain, sourceSize, size);
    final inputRect = Offset.zero & sourceSize;
    final outputRect = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    final sourceRect = Alignment.center.inscribe(fitted.source, inputRect);

    final scaleX = outputRect.width / sourceRect.width;
    final scaleY = outputRect.height / sourceRect.height;

    final paint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final detection in detections) {
      final rectOnSource = _rectFromDetection(detection, sourceSize);
      if (rectOnSource == null) {
        continue;
      }

      final left = outputRect.left + ((rectOnSource.left - sourceRect.left) * scaleX);
      final top = outputRect.top + ((rectOnSource.top - sourceRect.top) * scaleY);
      final rectWidth = rectOnSource.width * scaleX;
      final rectHeight = rectOnSource.height * scaleY;

      final rect = Rect.fromLTWH(left, top, rectWidth, rectHeight);
      canvas.drawRect(rect, paint);

      textPainter.text = TextSpan(
        text:
            '${detection['class'] ?? 'Unknown'} ${(detection['confidence'] * 100).toStringAsFixed(1)}%',
        style: const TextStyle(
          color: Colors.green,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(left, (top - 18).clamp(0, size.height - 18)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant DetectionOverlayPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.sourceSize != sourceSize;
  }

  Rect? _rectFromDetection(dynamic detection, Size sourceSize) {
    double? left;
    double? top;
    double? right;
    double? bottom;

    if (detection is Map) {
      if (detection.containsKey('x1') && detection.containsKey('y1')) {
        left = (detection['x1'] as num?)?.toDouble();
        top = (detection['y1'] as num?)?.toDouble();
        right = (detection['x2'] as num?)?.toDouble();
        bottom = (detection['y2'] as num?)?.toDouble();
      } else if (detection.containsKey('left') && detection.containsKey('top')) {
        left = (detection['left'] as num?)?.toDouble();
        top = (detection['top'] as num?)?.toDouble();
        right = (detection['right'] as num?)?.toDouble();
        bottom = (detection['bottom'] as num?)?.toDouble();
      } else if (detection.containsKey('xmin') && detection.containsKey('ymin')) {
        left = (detection['xmin'] as num?)?.toDouble();
        top = (detection['ymin'] as num?)?.toDouble();
        right = (detection['xmax'] as num?)?.toDouble();
        bottom = (detection['ymax'] as num?)?.toDouble();
      } else if (detection.containsKey('x') && detection.containsKey('y')) {
        final x = (detection['x'] as num?)?.toDouble();
        final y = (detection['y'] as num?)?.toDouble();
        final w = (detection['w'] as num?)?.toDouble();
        final h = (detection['h'] as num?)?.toDouble();
        if (x == null || y == null || w == null || h == null) {
          return null;
        }

        final bool isNormalized = x <= 1 && y <= 1 && w <= 1 && h <= 1;
        final double scaleX = isNormalized ? sourceSize.width : 1.0;
        final double scaleY = isNormalized ? sourceSize.height : 1.0;

        left = (x - w / 2) * scaleX;
        top = (y - h / 2) * scaleY;
        right = (x + w / 2) * scaleX;
        bottom = (y + h / 2) * scaleY;
      }
    }

    if (left == null || top == null || right == null || bottom == null) {
      return null;
    }

    final bool normalizedCoords =
        left <= 1 && top <= 1 && right <= 1 && bottom <= 1;
    if (normalizedCoords) {
      left *= sourceSize.width;
      right *= sourceSize.width;
      top *= sourceSize.height;
      bottom *= sourceSize.height;
    }

    final rect = Rect.fromLTRB(left, top, right, bottom);
    if (rect.width <= 0 || rect.height <= 0) {
      return null;
    }
    return rect;
  }
}
