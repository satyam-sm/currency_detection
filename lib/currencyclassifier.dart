import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';

class CurrencyClassifierPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CurrencyClassifierPage({super.key, required this.cameras});

  @override
  _CurrencyClassifierPageState createState() => _CurrencyClassifierPageState();
}

class _CurrencyClassifierPageState extends State<CurrencyClassifierPage> {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;

  Interpreter? _interpreter;
  final List<String> labelsName = [
    '10',
    '20',
    '50',
    '100',
    '200',
    '500',
    '2000'
  ];

  // Text-to-Speech
  final FlutterTts _flutterTts = FlutterTts();

  // Flag to track if classification is in progress
  bool _isClassifying = false;

  // Variable to store the current classification result
  Map<String, dynamic> _currentResult = {};

  @override
  void initState() {
    super.initState();

    // Initialize camera
    _controller = CameraController(
      widget.cameras[0],
      ResolutionPreset.high,
    );
    _initializeControllerFuture = _controller?.initialize();

    _loadModel();

    // Configure Text-to-Speech
    _configureTextToSpeech();
  }

  // Load the TensorFlow Lite model
  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/model.tflite');
    } catch (e) {
      print('Failed to load model: $e');
    }
  }

  // Configure Text-to-Speech settings
  Future<void> _configureTextToSpeech() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5);
  }

  // Speak the detected denomination
  Future<void> _speakDenomination(String denomination) async {
    await _flutterTts.speak('Detected $denomination Rupees');
  }

  // Capture and classify 3 snapshots with different zoom levels
  Future<void> _captureAndClassify() async {
    setState(() {
      _isClassifying = true;
    });

    try {
      // List to store the results of each classification
      List<String> results = [];

      for (int i = 0; i < 3; i++) {
        // Ensure the camera is initialized
        await _initializeControllerFuture;

        // Capture an image
        final image = await _controller!.takePicture();

        // Read image bytes
        final imageBytes = await image.readAsBytes();
        final decodedImage = img.decodeImage(imageBytes);

        if (decodedImage == null) {
          _showErrorDialog('Failed to decode image');
          return;
        }

        // Preprocess image based on the iteration
        img.Image processedImage;
        if (i == 0) {
          // First image: no zoom
          processedImage = decodedImage;
        } else if (i == 1) {
          // Second image: zoom in on the top half with 2x zoom
          processedImage = _zoomImage(decodedImage, 0, 0, decodedImage.width, decodedImage.height ~/ 2, zoom: 2.0);
        } else {
          // Third image: zoom in on the bottom half with 2x zoom
          processedImage = _zoomImage(decodedImage, 0, decodedImage.height ~/ 2, decodedImage.width, decodedImage.height ~/ 2, zoom: 2.0);
        }

        // Preprocess the processed image for classification
        final Float32List input = _preprocessImage(processedImage);

        // Perform classification
        final result = _classifyImage(input);

        // Store the result
        results.add(result['label']);
      }

      // Determine the majority result
      final majorityResult = _getMajorityResult(results);

      // Update UI with the majority result
      setState(() {
        _currentResult = {'label': majorityResult, 'confidence': 'N/A'};
        _isClassifying = false;
      });

      // Speak the majority result
      await _speakDenomination(majorityResult);
    } catch (e) {
      _showErrorDialog('Classification error: $e');
      setState(() {
        _isClassifying = false;
      });
    }
  }

  // Helper method to zoom in on a specific region of the image
  img.Image _zoomImage(img.Image image, int x, int y, int width, int height, {double zoom = 1.0}) {
    // Calculate the zoomed region
    final zoomedWidth = (width / zoom).round();
    final zoomedHeight = (height / zoom).round();

    // Calculate the center of the region
    final centerX = x + width ~/ 2;
    final centerY = y + height ~/ 2;

    // Calculate the new crop coordinates
    final newX = (centerX - zoomedWidth ~/ 2).clamp(0, image.width - zoomedWidth);
    final newY = (centerY - zoomedHeight ~/ 2).clamp(0, image.height - zoomedHeight);

    // Crop the image
    final croppedImage = img.copyCrop(image, x: newX, y: newY, width: zoomedWidth, height: zoomedHeight);

    // Resize the cropped image back to the original dimensions
    return img.copyResize(croppedImage, width: width, height: height);
  }

  // Helper method to determine the majority result
  String _getMajorityResult(List<String> results) {
    // Create a map to count the occurrences of each result
    Map<String, int> resultCounts = {};

    for (var result in results) {
      if (resultCounts.containsKey(result)) {
        resultCounts[result] = resultCounts[result]! + 1;
      } else {
        resultCounts[result] = 1;
      }
    }

    // Find the result with the highest count
    String majorityResult = '';
    int maxCount = 0;

    resultCounts.forEach((result, count) {
      if (count > maxCount) {
        majorityResult = result;
        maxCount = count;
      }
    });

    return majorityResult;
  }

  // Preprocess the image for classification
  Float32List _preprocessImage(img.Image image) {
    final int targetHeight = 128;
    final int targetWidth = 128;

    // Rotate the image anti-clockwise by 90 degrees
    final rotatedImage = img.copyRotate(image, angle: -90);

    // Resize image to match the 2:1 aspect ratio (currency note shape)
    final resizedImage =
    img.copyResize(rotatedImage, width: targetWidth, height: targetHeight);

    // Normalize pixel values
    final Float32List input = Float32List(targetHeight * targetWidth * 3);

    for (int y = 0; y < targetHeight; y++) {
      for (int x = 0; x < targetWidth; x++) {
        final pixel = resizedImage.getPixel(x, y);
        final index = (y * targetWidth + x) * 3;

        input[index] = pixel.r / 255.0;
        input[index + 1] = pixel.g / 255.0;
        input[index + 2] = pixel.b / 255.0;
      }
    }

    return input;
  }

  // Classify the preprocessed image using the TensorFlow Lite model
  Map<String, dynamic> _classifyImage(Float32List processedImage) {
    if (_interpreter == null) {
      throw Exception('Model not loaded');
    }

    final inputShape = [1, 128, 128, 3];
    final output = List.generate(1, (_) => List.filled(labelsName.length, 0.0));

    _interpreter!
        .run(processedImage.buffer.asFloat32List().reshape(inputShape), output);

    final probabilities = output[0];
    int maxIndex = 0;
    double maxValue = 0.0;

    for (int i = 0; i < probabilities.length; i++) {
      if (probabilities[i] > maxValue) {
        maxValue = probabilities[i];
        maxIndex = i;
      }
    }

    return {
      'label': labelsName[maxIndex],
      'confidence': (maxValue * 100).toStringAsFixed(2)
    };
  }

  // Show an error dialog
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  // Build the camera preview widget
  Widget _buildCameraPreview() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return Center(child: CircularProgressIndicator());
    }

    final mediaSize = MediaQuery.of(context).size;

    // Define height for 60% of the screen
    final double previewHeight = mediaSize.height * 0.6;
    final double previewWidth = mediaSize.width;

    // Aspect ratio 2:1 for currency note
    final double cameraAspectRatio = 2.0;

    return Center(
      child: ClipRect(
        child: Container(
          width: previewWidth,
          height: previewHeight,
          child: RotatedBox(
            quarterTurns: 1,
            child: Center(
              child: AspectRatio(
                aspectRatio: cameraAspectRatio,
                child: CameraPreview(_controller!),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Currency Classifier')),
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // Camera Preview design
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(
                  color: const Color.fromARGB(255, 5, 77, 111),
                  width: 3.0,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              margin: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(17),
                child: FutureBuilder<void>(
                  future: _initializeControllerFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.done) {
                      return Expanded(
                        child: _buildCameraPreview(),
                      );
                    } else {
                      return Center(child: CircularProgressIndicator());
                    }
                  },
                ),
              ),
            ),

            // Button design
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: ElevatedButton(
                onPressed: _isClassifying ? null : _captureAndClassify,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 40),
                  foregroundColor: const Color.fromARGB(255, 255, 255, 255),
                  backgroundColor: const Color.fromARGB(255, 109, 51, 0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: _isClassifying
                    ? CircularProgressIndicator(color: Colors.white)
                    : Text('Detect Currency'),
              ),
            ),

            // Results Display
            if (_currentResult.isNotEmpty) ...[
              Text(
                'Denomination: ${_currentResult['label']} Rupees\n',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 5),
            ]
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _interpreter?.close();
    super.dispose();
  }
}