import 'dart:io';
import 'dart:math';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Service for facial recognition operations
/// Handles face detection, embedding extraction, and face comparison
class FacialRecognitionService {
  late FaceDetector _faceDetector;
  
  FacialRecognitionService() {
    final options = FaceDetectorOptions(
      enableClassification: true,
      enableTracking: false,
      enableLandmarks: true,
    );
    _faceDetector = FaceDetector(options: options);
  }

  /// Detect faces in an image file
  /// Returns list of detected faces with landmark data
  Future<List<Face>> detectFaces(String imagePath) async {
    final inputImage = InputImage.fromFile(File(imagePath));
    try {
      final faces = await _faceDetector.processImage(inputImage);
      return faces;
    } catch (e) {
      print('Error detecting faces: $e');
      return [];
    }
  }

  /// Extract face embedding (simplified version)
  /// In a production app, you'd use TensorFlow Lite with FaceNet model
  /// For now, we'll use ML Kit face landmarks to create a basic feature vector
  Future<List<double>> extractFaceEmbedding(String imagePath) async {
    final faces = await detectFaces(imagePath);
    
    if (faces.isEmpty) {
      throw Exception('No face detected in image');
    }

    final face = faces.first;
    
    // Use ML Kit landmarks to create a basic embedding
    // This is a simplified approach - in production use FaceNet via TFLite
    final embedding = _createEmbeddingFromLandmarks(face);
    
    return embedding;
  }

  /// Create a basic embedding from facial landmarks
  /// This is a simplified approach for demonstration
  List<double> _createEmbeddingFromLandmarks(Face face) {
    final embedding = <double>[];
    
    // Add face bounding box normalized coordinates as features
    final bounds = face.boundingBox;
    embedding.addAll([
      bounds.left,
      bounds.top,
      bounds.right,
      bounds.bottom,
      bounds.width.toDouble(),
      bounds.height.toDouble(),
    ]);
    
    // Add head euler angles if available
    if (face.headEulerAngleY != null) embedding.add(face.headEulerAngleY!);
    if (face.headEulerAngleZ != null) embedding.add(face.headEulerAngleZ!);
    if (face.headEulerAngleX != null) embedding.add(face.headEulerAngleX!);
    
    // Add smiley probability
    if (face.smilingProbability != null) embedding.add(face.smilingProbability!);
    
    // Add left eye open probability
    if (face.leftEyeOpenProbability != null) {
      embedding.add(face.leftEyeOpenProbability!);
    }
    
    // Add right eye open probability
    if (face.rightEyeOpenProbability != null) {
      embedding.add(face.rightEyeOpenProbability!);
    }
    
    // Add landmarks if available
    final landmarks = face.landmarks;
    for (final landmarkEntry in landmarks.entries) {
      final position = landmarkEntry.value?.position;
      if (position != null) {
        embedding.add(position.x.toDouble());
        embedding.add(position.y.toDouble());
      }
    }
    
    // Normalize embedding
    return _normalizeEmbedding(embedding);
  }

  /// Normalize embedding to unit vector
  List<double> _normalizeEmbedding(List<double> embedding) {
    double magnitude = 0.0;
    for (final value in embedding) {
      magnitude += value * value;
    }
    magnitude = sqrt(magnitude.clamp(0.0000001, double.infinity));
    
    return embedding.map((value) => value / magnitude).toList();
  }

  /// Compare two embeddings using cosine similarity
  /// Returns similarity score between 0 and 1 (1 = identical)
  double compareEmbeddings(List<double> embedding1, List<double> embedding2) {
    if (embedding1.length != embedding2.length) {
      throw Exception('Embeddings must have the same length');
    }

    double dotProduct = 0.0;
    for (int i = 0; i < embedding1.length; i++) {
      dotProduct += embedding1[i] * embedding2[i];
    }

    // Both embeddings are already normalized, so cosine similarity = dot product
    return dotProduct.clamp(0.0, 1.0);
  }

  /// Verify if a face matches a stored embedding
  /// Returns true if similarity > threshold (default 0.6)
  Future<bool> verifyFace(
    String capturedImagePath,
    List<double> storedEmbedding, {
    double threshold = 0.6,
  }) async {
    try {
      final capturedEmbedding = await extractFaceEmbedding(capturedImagePath);
      final similarity = compareEmbeddings(capturedEmbedding, storedEmbedding);
      
      print('Face verification similarity: $similarity (threshold: $threshold)');
      
      return similarity > threshold;
    } catch (e) {
      print('Error verifying face: $e');
      return false;
    }
  }

  /// Get face quality score (0-1)
  /// Higher scores indicate better quality for recognition
  Future<double> getFaceQuality(String imagePath) async {
    final faces = await detectFaces(imagePath);
    
    if (faces.isEmpty) {
      return 0.0;
    }

    final face = faces.first;
    var qualityScore = 0.5; // base score

    // Check if face is frontal (good for recognition)
    final yaw = (face.headEulerAngleY ?? 0).abs();
    final pitch = (face.headEulerAngleX ?? 0).abs();
    
    if (yaw < 20 && pitch < 20) {
      qualityScore += 0.3; // good angle
    }

    // Check if eyes are open
    if ((face.leftEyeOpenProbability ?? 0) > 0.5 &&
        (face.rightEyeOpenProbability ?? 0) > 0.5) {
      qualityScore += 0.2; // eyes open
    }

    return qualityScore.clamp(0.0, 1.0);
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _faceDetector.close();
  }
}
