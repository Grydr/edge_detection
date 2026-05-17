import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';
import 'detection_overlay_painter.dart';

class CameraScreen extends StatefulWidget {
  final YOLO yolo;
  final double confidenceThreshold;

  const CameraScreen({
    super.key,
    required this.yolo,
    required this.confidenceThreshold,
  });

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _cameraController;
  late List<CameraDescription> cameras;
  late YOLO _activeYolo;
  bool _usingGpu = true;
  bool _isDetecting = false;
  List<dynamic> _detections = [];
  bool _isInitializing = true;
  String? _initError;
  DateTime? _lastInferenceAt;
  static const Duration _minInferenceInterval = Duration(milliseconds: 180);

  @override
  void initState() {
    super.initState();
    _activeYolo = widget.yolo;
    _initializeCamera();
  }

  Future<void> _switchToCpuModel() async {
    if (!_usingGpu) return;

    _usingGpu = false;
    _activeYolo = YOLO(
      modelPath: widget.yolo.modelPath,
      task: widget.yolo.resolvedTask,
      useGpu: false,
    );
    await _activeYolo.loadModel();
  }

  Future<void> _initializeCamera() async {
    try {
      cameras = await availableCameras();

      if (cameras.isEmpty) {
        setState(() {
          _initError = 'No cameras available';
          _isInitializing = false;
        });
        return;
      }

      _cameraController = CameraController(
        cameras[0], // Use rear camera
        ResolutionPreset.high,
      );

      await _cameraController!.initialize();

      if (!mounted) return;

      // Start streaming frames
      _cameraController!.startImageStream((CameraImage image) {
        if (_isDetecting) {
          return;
        }

        final now = DateTime.now();
        if (_lastInferenceAt != null &&
            now.difference(_lastInferenceAt!) < _minInferenceInterval) {
          return;
        }

        _lastInferenceAt = now;
        if (!_isDetecting) {
          _detectObjects(image);
        }
      });

      setState(() {
        _isInitializing = false;
      });
    } catch (e) {
      setState(() {
        _initError = 'Camera initialization error: $e';
        _isInitializing = false;
      });
    }
  }

  Future<void> _detectObjects(CameraImage image) async {
    if (_cameraController == null) return;

    _isDetecting = true;

    try {
      // Convert CameraImage to bytes
      final imageBytes = await _convertCameraImage(image);

      if (imageBytes.isEmpty) {
        return;
      }

      // Run detection
      final results = await _predictWithFallback(imageBytes);
      final rawBoxes = results['boxes'] ?? [];
      final filteredBoxes = _filterByConfidence(
        rawBoxes,
        widget.confidenceThreshold,
      );

      if (mounted) {
        setState(() {
          _detections = filteredBoxes;
        });
      }
    } catch (e) {
      print('Detection error: $e');
    } finally {
      _isDetecting = false;
    }
  }

  Future<Uint8List> _convertCameraImage(CameraImage image) async {
    try {
      late final img.Image rgbImage;

      if (image.format.group == ImageFormatGroup.yuv420) {
        rgbImage = _convertYuv420ToRgb(image);
      } else if (image.format.group == ImageFormatGroup.bgra8888) {
        rgbImage = _convertBgra8888ToRgb(image);
      } else {
        throw UnsupportedError(
          'Unsupported image format: ${image.format.group}',
        );
      }

      final jpeg = img.encodeJpg(rgbImage, quality: 92);
      return Uint8List.fromList(jpeg);
    } catch (e) {
      print('Image conversion error: $e');
      return Uint8List(0);
    }
  }

  img.Image _convertYuv420ToRgb(CameraImage image) {
    final width = image.width;
    final height = image.height;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yBytes = yPlane.bytes;
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;

    final uvPixelStride = uPlane.bytesPerPixel ?? 1;
    final rgbImage = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      final yRowOffset = y * yPlane.bytesPerRow;
      final uvRowOffset = (y >> 1) * uPlane.bytesPerRow;

      for (int x = 0; x < width; x++) {
        final yIndex = yRowOffset + x;
        final uvColOffset = (x >> 1) * uvPixelStride;
        final uIndex = uvRowOffset + uvColOffset;
        final vIndex = (y >> 1) * vPlane.bytesPerRow + uvColOffset;

        if (yIndex >= yBytes.length ||
            uIndex >= uBytes.length ||
            vIndex >= vBytes.length) {
          continue;
        }

        final yValue = yBytes[yIndex].toDouble();
        final uValue = uBytes[uIndex].toDouble() - 128.0;
        final vValue = vBytes[vIndex].toDouble() - 128.0;

        final r = _toByte(yValue + 1.402 * vValue);
        final g = _toByte(yValue - 0.344136 * uValue - 0.714136 * vValue);
        final b = _toByte(yValue + 1.772 * uValue);

        rgbImage.setPixelRgb(x, y, r, g, b);
      }
    }

    return rgbImage;
  }

  img.Image _convertBgra8888ToRgb(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final plane = image.planes[0];
    final bytes = plane.bytes;

    final rgbImage = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      final rowOffset = y * plane.bytesPerRow;
      for (int x = 0; x < width; x++) {
        final pixelOffset = rowOffset + (x * 4);
        if (pixelOffset + 2 >= bytes.length) {
          continue;
        }

        final b = bytes[pixelOffset];
        final g = bytes[pixelOffset + 1];
        final r = bytes[pixelOffset + 2];
        rgbImage.setPixelRgb(x, y, r, g, b);
      }
    }

    return rgbImage;
  }

  int _toByte(double value) {
    if (value < 0) return 0;
    if (value > 255) return 255;
    return value.round();
  }

  Future<Map<String, dynamic>> _predictWithFallback(
    Uint8List imageBytes,
  ) async {
    try {
      return await _activeYolo.predict(imageBytes);
    } catch (e) {
      final message = e.toString();
      final shouldFallbackToCpu =
          _usingGpu &&
          (message.contains('delegate') || message.contains('GPU'));

      if (!shouldFallbackToCpu) rethrow;

      await _switchToCpuModel();
      return await _activeYolo.predict(imageBytes);
    }
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
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(title: Text('Live Object Detection')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_initError != null) {
      return Scaffold(
        appBar: AppBar(title: Text('Live Object Detection')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_initError!),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: Text('Live Object Detection')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Live Object Detection')),
      body: Stack(
        children: [
          CameraPreview(_cameraController!),
          // Draw bounding boxes
          Positioned.fill(
            child: CustomPaint(
              painter: DetectionOverlayPainter(
                _detections,
                _cameraController!.value.previewSize!,
              ),
            ),
          ),
          // Detection info overlay
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Detected: ${_detections.length} objects',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
          // Detection list
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 120,
              decoration: BoxDecoration(color: Colors.black54),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _detections.length,
                itemBuilder: (context, index) {
                  final detection = _detections[index];
                  return Container(
                    margin: EdgeInsets.all(8),
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          detection['class'] ?? 'Unknown',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${(detection['confidence'] * 100).toStringAsFixed(1)}%',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
