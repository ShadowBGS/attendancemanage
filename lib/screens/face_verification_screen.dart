import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/facial_recognition_service.dart';

/// Screen for verifying student face during attendance
/// Shown after student joins session if facial verification is enabled
class FaceVerificationScreen extends StatefulWidget {
  final String studentName;
  final List<double> storedEmbedding;
  final Function(bool) onVerificationResult; // true = verified, false = not verified

  const FaceVerificationScreen({
    super.key,
    required this.studentName,
    required this.storedEmbedding,
    required this.onVerificationResult,
  });

  @override
  State<FaceVerificationScreen> createState() => _FaceVerificationScreenState();
}

class _FaceVerificationScreenState extends State<FaceVerificationScreen> {
  CameraController? _cameraController;
  bool _isInitialized = false;
  bool _isProcessing = false;
  String? _statusMessage;

  double? _matchScore;
  bool? _isVerified;

  final FacialRecognitionService _facialRecognitionService =
      FacialRecognitionService();

  static const double VERIFICATION_THRESHOLD = 0.6;

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

  Future<void> _scanFace() async {
    if (_cameraController == null || !_isInitialized || _isProcessing) return;

    setState(() => _isProcessing = true);
    try {
      final image = await _cameraController!.takePicture();

      setState(() => _statusMessage = 'Scanning face...');

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
          _statusMessage = 'Face quality: ${(quality * 100).toStringAsFixed(0)}%';
        });
      }

      // Verify face if quality is acceptable
      if (quality > 0.5) {
        setState(() => _statusMessage = 'Verifying identity...');

        try {
          final capturedEmbedding =
              await _facialRecognitionService.extractFaceEmbedding(image.path);
          final similarity = _facialRecognitionService.compareEmbeddings(
            capturedEmbedding,
            widget.storedEmbedding,
          );

          if (mounted) {
            setState(() {
              _matchScore = similarity;
              _isVerified = similarity > VERIFICATION_THRESHOLD;
              _statusMessage = _isVerified!
                  ? '✓ Facial verification successful!'
                  : '✗ Face does not match. Please try again.';
            });
          }

          // Show result for 2 seconds then auto-close
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            widget.onVerificationResult(_isVerified ?? false);
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _statusMessage = 'Error in verification: $e';
              _isProcessing = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _statusMessage =
                'Face quality too low. Better lighting needed.';
            _isProcessing = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Error scanning face: $e';
          _isProcessing = false;
        });
      }
    }
  }

  void _skip() {
    widget.onVerificationResult(false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Facial Verification'),
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
                            child: Stack(
                              children: [
                                CameraPreview(_cameraController!),
                                // Overlay face guide
                                Center(
                                  child: Container(
                                    width: 200,
                                    height: 250,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Keep your face\nwithin the frame',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            shadows: [
                                              Shadow(
                                                offset: Offset(1, 1),
                                                blurRadius: 3,
                                                color: Colors.black54,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Student name
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(
                        'Verifying: ${widget.studentName}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Status message with color coding
                    if (_statusMessage != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _isVerified == null
                                ? Colors.blue.shade50
                                : _isVerified!
                                    ? Colors.green.shade50
                                    : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isVerified == null
                                  ? Colors.blue
                                  : _isVerified!
                                      ? Colors.green
                                      : Colors.red,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _statusMessage!,
                                style: TextStyle(
                                  color: _isVerified == null
                                      ? Colors.blue.shade900
                                      : _isVerified!
                                          ? Colors.green.shade900
                                          : Colors.red.shade900,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (_matchScore != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Match Score: ${(_matchScore! * 100).toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    color: _isVerified == null
                                        ? Colors.blue.shade700
                                        : _isVerified!
                                            ? Colors.green.shade700
                                            : Colors.red.shade700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Action buttons
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isProcessing ? null : _skip,
                              child: const Text('Skip'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed:
                                  _isProcessing ? null : _scanFace,
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
                                _isProcessing ? 'Scanning...' : 'Scan Face',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ),
                        ],
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
