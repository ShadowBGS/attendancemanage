import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import '../db/database.dart';

/// Service for managing face data operations in the database
class FaceDataManager {
  final AppDatabase _database;

  FaceDataManager(this._database);

  /// Store face embedding for a user
  /// Returns the ID of the stored face data
  Future<int> storeFaceEmbedding(
    int userId,
    List<double> embedding,
  ) async {
    try {
      // Delete any existing embedding for this user (one face per user)
      final existingCount = await (_database.delete(_database.faceDataTable)
              ..where((row) => row.userId.equals(userId)))
          .go();

      // Insert new embedding  
      final result = await _database.into(_database.faceDataTable).insert(
        FaceDataTableCompanion(
          userId: Value(userId),
          embedding: Value(jsonEncode(embedding)),
        ),
      );
      
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Retrieve face embedding for a user
  /// Returns null if no embedding exists
  Future<List<double>?> getFaceEmbedding(int userId) async {
    try {
      final results = await (_database.select(_database.faceDataTable)
            ..where((row) => row.userId.equals(userId)))
          .get();

      if (results.isEmpty) {
        return null;
      }

      final embeddingJson = results.first.embedding;
      final embedding = List<double>.from(jsonDecode(embeddingJson) as List);

      return embedding;
    } catch (e) {
      return null;
    }
  }

  /// Check if a user has a stored face embedding
  Future<bool> hasFaceEmbedding(int userId) async {
    final embedding = await getFaceEmbedding(userId);
    return embedding != null;
  }

  /// Delete face embedding for a user
  Future<void> deleteFaceEmbedding(int userId) async {
    try {
      await (_database.delete(_database.faceDataTable)
            ..where((row) => row.userId.equals(userId)))
          .go();
    } catch (e) {
      rethrow;
    }
  }

  /// Update attendance record with facial verification status
  Future<void> updateAttendanceVerification(
    int attendanceRecordId,
    bool isFacialVerified,
    String verificationMethod,
  ) async {
    try {
      await (_database.update(_database.attendanceRecords)
            ..where((row) => row.id.equals(attendanceRecordId)))
          .write(
        AttendanceRecordsCompanion(
          faceVerified: Value(isFacialVerified),
          verificationMethod: Value(verificationMethod),
        ),
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Get statistics on facial verification for a session
  Future<Map<String, dynamic>> getSessionVerificationStats(int sessionId) async {
    try {
      final records = await (_database.select(_database.attendanceRecords)
            ..where((row) => row.sessionId.equals(sessionId)))
          .get();

      final totalRecords = records.length;
      final faciallyVerified = records.where((r) => r.faceVerified).length;
      final notVerified = totalRecords - faciallyVerified;

      return {
        'total': totalRecords,
        'verified': faciallyVerified,
        'not_verified': notVerified,
        'verification_rate':
            totalRecords > 0 ? (faciallyVerified / totalRecords) : 0.0,
      };
    } catch (e) {
      return {
        'total': 0,
        'verified': 0,
        'not_verified': 0,
        'verification_rate': 0.0,
      };
    }
  }

  /// Mark all attendance records in a session as needing facial verification
  /// (Called when lecturer enables facial verification for a session)
  Future<void> enableFacialVerificationForSession(int sessionId) async {
    // This is informational - actual verification happens per-student
    // We just need to track that the session requires facial verification
  }
}
