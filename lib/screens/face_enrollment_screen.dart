import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import '../services/facial_recognition_service.dart';

/// Screen for capturing student face during enrollment
/// Used during signup/profile completion and in facial verification setup
class FaceEnrollmentScreen extends StatefulWidget {
  final String studentName;
  final VoidCallback onComplete;
  final Function(String, List<double>) onFaceCaptured; // imagePath, embedding

  const FaceEnrollmentScreen({
    super.key,
    required this.studentName,
    required this.onComplete,
    required this.onFaceCaptured,
  });

  @override
  State<FaceEnrollmentScreen> createState() => _FaceEnrollmentScreenState();
}

class _FaceEnrollmentScreenState extends State<FaceEnrollmentScreen> {
  CameraController? _cameraController;
  bool _isInitialized = false;
  bool _isProcessing = false;
  String? _statusMessage;
  double _faceQuality = 0.0;
  bool _faceDetected = false;

  final FacialRecognitionService _facialRecognitionService =
      FacialRecognitionService();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = 'Failed to initialize camera: $e');
      }
    }
  }

  Future<void> _captureFace() async {
    if (_cameraController == null || !_isInitialized || _isProcessing) return;

    setState(() => _isProcessing = true);
    try {
      final image = await _cameraController!.takePicture();
      
      setState(() => _statusMessage = 'Processing face...');

      // Detect faces in captured image
      final faces =
          await _facialRecognitionService.detectFaces(image.path);

      if (faces.isEmpty) {
        if (mounted) {
          setState(() {
            _statusMessage = 'No face detected. Please try again.';
            _isProcessing = false;
          });
        }
        return;
      }

      // Get face quality score
      final quality =
          await _facialRecognitionService.getFaceQuality(image.path);

      if (mounted) {
        setState(() {
          _faceQuality = quality;
          _faceDetected = true;
          _statusMessage = 'Face quality: ${(quality * 100).toStringAsFixed(0)}%';
        });
      }

      // Extract embedding if quality is acceptable
      if (quality > 0.6) {
        final embedding =
            await _facialRecognitionService.extractFaceEmbedding(image.path);

        if (mounted) {
          setState(() => _statusMessage = 'Face captured successfully!');
        }

        // Pass captured data back to parent
        widget.onFaceCaptured(image.path, embedding);

        // Wait a moment before showing confirmation
        await Future.delayed(const Duration(milliseconds: 500));

        if (mounted) {
          _showEnrollmentConfirmation(image.path);
        }
      } else {
        if (mounted) {
          setState(() {
            _statusMessage =
                'Face quality too low. Better lighting or angle needed.';
            _isProcessing = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Error capturing face: $e';
          _isProcessing = false;
        });
      }
    }
  }

  void _showEnrollmentConfirmation(String imagePath) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Face Captured'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.file(
              File(imagePath),
              height: 200,
              width: 200,
              fit: BoxFit.cover,
            ),
            const SizedBox(height: 16),
            Text(
              'Quality: ${(_faceQuality * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _isProcessing = false);
            },
            child: const Text('Retake'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onComplete();
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture Your Face'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isInitialized
            ? SingleChildScrollView(
                child: Column(
                  children: [
                    // Camera preview
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: double.infinity,
                          child: AspectRatio(
                            aspectRatio: _cameraController!.value.aspectRatio,
                            child: CameraPreview(_cameraController!),
                          ),
                        ),
                      ),
                    ),

                    // Instructions
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Instructions:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              '• Face the camera directly\n'
                              '• Ensure good lighting\n'
                              '• Keep your face centered\n'
                              '• Tap "Capture" when ready',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Status message
                    if (_statusMessage != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _faceDetected ? Colors.green.shade50 : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _faceDetected ? Colors.green : Colors.orange,
                            ),
                          ),
                          child: Text(
                            _statusMessage!,
                            style: TextStyle(
                              color: _faceDetected ? Colors.green.shade900 : Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Capture button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _captureFace,
                          icon: _isProcessing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.camera),
                          label: Text(
                            _isProcessing ? 'Processing...' : 'Capture Face',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              )
            : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(_statusMessage ?? 'Initializing camera...'),
                  ],
                ),
              ),
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _facialRecognitionService.dispose();
    super.dispose();
  }
}
