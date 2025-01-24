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

  @override
  void initState() {
    super.initState();

    // Initialize camera
    _controller = CameraController(
      widget.cameras[0],
      ResolutionPreset.medium,
    );
    _initializeControllerFuture = _controller?.initialize();

    _loadModel();

    // Configure Text-to-Speech
    _configureTextToSpeech();
  }

//loading model -----
  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/model.tflite');
    } catch (e) {
      print('Failed to load model: $e');
    }
  }

// tts work -----
  Future<void> _configureTextToSpeech() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5);
  }

  Future<void> _speakDenomination(String denomination) async {
    await _flutterTts.speak('Detected $denomination Rupees');
  }

// applying model
  Future<void> _captureAndClassify() async {
    try {
      //camera part --------
      await _initializeControllerFuture;

      final image = await _controller!.takePicture();

      // Read image bytes
      final imageBytes = await image.readAsBytes();
      final decodedImage = img.decodeImage(imageBytes);

      if (decodedImage == null) {
        _showErrorDialog('Failed to decode image');
        return;
      }

      // Preprocess image
      final processedImage = _preprocessImage(decodedImage);

      // Perform classification
      final result = _classifyImage(processedImage);

      // update UI -----
      setState(() {
        _currentResult = result;
      });
      await _speakDenomination(result['label']);
    } catch (e) {
      _showErrorDialog('Classification error: $e');
    }
  }

// preprocessing start -----
  Float32List _preprocessImage(img.Image image) {
    final int targetHeight = 128;
    final int targetWidth = 128;

    //resize
    final resizedImage =
        img.copyResize(image, width: targetWidth, height: targetHeight);

    // Normalize
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

// preprocessing end

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

// frontend work-----
  Widget _buildCameraPreview() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return Center(child: CircularProgressIndicator());
    }

    final mediaSize = MediaQuery.of(context).size;

    // Define height for 60% of the screen
    final double previewHeight = mediaSize.height * 0.6;
    final double previewWidth = mediaSize.width;

    // Calculate scale to crop the camera feed while maintaining aspect ratio
    final double cameraAspectRatio = _controller!.value.aspectRatio;
    final double screenAspectRatio = previewWidth / previewHeight;
    final double scale = cameraAspectRatio > screenAspectRatio
        ? cameraAspectRatio / screenAspectRatio
        : screenAspectRatio / cameraAspectRatio;

    return Center(
      child: ClipRect(
        child: Container(
          width: previewWidth, // Match screen width
          height: previewHeight, // Set to 70% of screen height
          child: Transform.scale(
            scale: scale * 1.2, // Uniformly scale the camera feed
            child: RotatedBox(
              quarterTurns: 1,
              child: Center(
                child: AspectRatio(
                  aspectRatio: cameraAspectRatio, // Match camera's aspect ratio
                  child: CameraPreview(_controller!),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _currentResult = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Currency Classifier')),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // Camera Preview design
          Container(
            decoration: BoxDecoration(
              color: Colors.white, // Background color
              border: Border.all(
                color: const Color.fromARGB(255, 5, 77, 111), // Border color
                width: 3.0, // Border width
              ),
              borderRadius: BorderRadius.circular(20), // Rounded corners
            ),
            margin: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                  17), // Slightly smaller than outer radius
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

//button design
          Padding(
              padding: const EdgeInsets.all(10.0),
              child: ElevatedButton(
                onPressed: _captureAndClassify,
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 40),
                    foregroundColor: const Color.fromARGB(255, 255, 255, 255),
                    backgroundColor: const Color.fromARGB(255, 109, 51, 0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    )),
                child: Text('Detect Currency'),
              )),

          // Results Display
          if (_currentResult.isNotEmpty) ...[
            Text(
              'Denomination: ${_currentResult['label']} Rupees\n',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(
              height: 5,
            ),
            Text(
              'Confidence: ${_currentResult['confidence']}%',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ]
        ],
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
