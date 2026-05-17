import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';
import 'dart:io';
import 'camera_screen.dart';
import 'detection_overlay_painter.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: YOLODemo());
  }
}

class YOLODemo extends StatefulWidget {
  const YOLODemo({super.key});

  @override
  _YOLODemoState createState() => _YOLODemoState();
}

class _YOLODemoState extends State<YOLODemo> {
  YOLO? yolo;
  File? selectedImage;
  Size? _selectedImageSize;
  List<dynamic> _rawResults = [];
  List<dynamic> results = [];
  bool isLoading = false;
  double _confidenceThreshold = 0.30;

  @override
  void initState() {
    super.initState();
    loadYOLO();
  }

  Future<void> loadYOLO() async {
    setState(() => isLoading = true);

    try {
      yolo = YOLO(
        modelPath: YOLO.defaultOfficialModel() ?? 'yolo26n',
        useGpu: false,
      );
      await yolo!.loadModel();
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<Map<String, dynamic>> _predictWithFallback(
    Uint8List imageBytes,
  ) async {
    try {
      return await yolo!.predict(imageBytes);
    } catch (e) {
      return await yolo!.predict(imageBytes);
    }
  }

  Future<void> pickAndDetect() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      setState(() {
        selectedImage = File(image.path);
        isLoading = true;
      });

      final imageBytes = await selectedImage!.readAsBytes();
      final decodedImage = img.decodeImage(imageBytes);
      final detectionResults = await _predictWithFallback(imageBytes);
      final boxes = detectionResults['boxes'] ?? [];

      setState(() {
        _selectedImageSize = decodedImage == null
            ? null
            : Size(
                decodedImage.width.toDouble(),
                decodedImage.height.toDouble(),
              );
        _rawResults = List<dynamic>.from(boxes);
        results = _filterByConfidence(_rawResults, _confidenceThreshold);
        isLoading = false;
      });
    }
  }

  void _openCameraScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraScreen(
          yolo: yolo!,
          confidenceThreshold: _confidenceThreshold,
        ),
      ),
    );
  }

  List<dynamic> _filterByConfidence(
    List<dynamic> detections,
    double threshold,
  ) {
    return detections.where((detection) {
      final confidence = (detection['confidence'] as num?)?.toDouble() ?? 0.0;
      return confidence >= threshold;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('YOLO Quick Demo')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (selectedImage != null)
              SizedBox(
                height: 300,
                child: _selectedImageSize == null
                    ? Image.file(selectedImage!, fit: BoxFit.contain)
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(selectedImage!, fit: BoxFit.contain),
                          CustomPaint(
                            painter: DetectionOverlayPainter(
                              results,
                              _selectedImageSize!,
                            ),
                          ),
                        ],
                      ),
              ),

            SizedBox(height: 20),

            if (isLoading)
              CircularProgressIndicator()
            else
              Text('Detected ${results.length} objects'),

            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                children: [
                  Text(
                    'Confidence threshold: ${_confidenceThreshold.toStringAsFixed(2)}',
                  ),
                  Slider(
                    min: 0.10,
                    max: 0.80,
                    divisions: 14,
                    value: _confidenceThreshold,
                    label: _confidenceThreshold.toStringAsFixed(2),
                    onChanged: (value) {
                      setState(() {
                        _confidenceThreshold = value;
                        results = _filterByConfidence(
                          _rawResults,
                          _confidenceThreshold,
                        );
                      });
                    },
                  ),
                ],
              ),
            ),

            SizedBox(height: 20),

            ElevatedButton(
              onPressed: yolo != null ? pickAndDetect : null,
              child: Text('Pick Image & Detect'),
            ),

            SizedBox(height: 10),

            ElevatedButton(
              onPressed: yolo != null ? _openCameraScreen : null,
              child: Text('Open Live Camera'),
            ),

            SizedBox(height: 20),

            // Show detection results
            Expanded(
              child: ListView.builder(
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final detection = results[index];
                  return ListTile(
                    title: Text(detection['class'] ?? 'Unknown'),
                    subtitle: Text(
                      'Confidence: ${(detection['confidence'] * 100).toStringAsFixed(1)}%',
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
