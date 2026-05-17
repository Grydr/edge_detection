import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';

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
      final x = (detection['x'] ?? 0).toDouble();
      final y = (detection['y'] ?? 0).toDouble();
      final w = (detection['w'] ?? 0).toDouble();
      final h = (detection['h'] ?? 0).toDouble();

      final left = outputRect.left + ((x - w / 2 - sourceRect.left) * scaleX);
      final top = outputRect.top + ((y - h / 2 - sourceRect.top) * scaleY);
      final rectWidth = w * scaleX;
      final rectHeight = h * scaleY;

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
}
