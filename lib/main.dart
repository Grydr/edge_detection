import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YOLO Realtime Detection',
      theme: ThemeData.dark(),
      home: const YOLODetection(),
    );
  }
}

class YOLODetection extends StatefulWidget {
  const YOLODetection({super.key});

  @override
  State<YOLODetection> createState() => _YOLODetectionState();
}

class _YOLODetectionState extends State<YOLODetection> {
  List<YOLOResult> _detections = [];
  double _fps = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black54,
        title: Text('${_detections.length} objects'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                '${_fps.toStringAsFixed(1)} FPS',
                style: const TextStyle(color: Colors.greenAccent),
              ),
            ),
          ),
        ],
      ),
      body: YOLOView(
        modelPath: 'assets/models/yolo11n_int8.tflite',
        task: YOLOTask.detect,
        confidenceThreshold: 0.5,
        iouThreshold: 0.45,
        lensFacing: LensFacing.back,
        showOverlays: true,
        onResult: (results) {
          setState(() => _detections = results);
        },
        onPerformanceMetrics: (metrics) {
          setState(() => _fps = metrics.fps);
        },
      ),
    );
  }
}
