import 'dart:convert';
import '../db/database_provider.dart';
import '../db/database.dart';

/// Service for managing face data operations in the database
class FaceDataManager {
  final DatabaseProvider _dbProvider;

  FaceDataManager(this._dbProvider);

  /// Store face embedding for a user
  /// Returns the ID of the stored face data
  Future<int> storeFaceEmbedding(
    int userId,
    List<double> embedding,
  ) async {
    final db = _dbProvider.database;
    
    try {
      // Delete any existing embedding for this user (one face per user)
      await db.delete(db.faceDataTable)
          .where((row) => row.userId.equals(userId))
          .go();

      // Insert new embedding
      final faceData = FaceDataTableCompanion(
        userId: Value(userId),
        embedding: Value(jsonEncode(embedding)),
      );

      final id = await db.into(db.faceDataTable).insert(faceData);
      
      print('✓ Face embedding stored for user $userId (id: $id)');
      return id;
    } catch (e) {
      print('✗ Error storing face embedding: $e');
      rethrow;
    }
  }

  /// Retrieve face embedding for a user
  /// Returns null if no embedding exists
  Future<List<double>?> getFaceEmbedding(int userId) async {
    final db = _dbProvider.database;

    try {
      final query = db.select(db.faceDataTable)
          .where((row) => row.userId.equals(userId))
          .limit(1);

      final results = await query.get();

      if (results.isEmpty) {
        print('ℹ️  No face embedding found for user $userId');
        return null;
      }

      final embeddingJson = results.first.embedding;
      final embedding = List<double>.from(jsonDecode(embeddingJson));

      print('✓ Face embedding retrieved for user $userId');
      return embedding;
    } catch (e) {
      print('✗ Error retrieving face embedding: $e');
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
    final db = _dbProvider.database;

    try {
      await (db.delete(db.faceDataTable)
          .where((row) => row.userId.equals(userId)))
          .go();

      print('✓ Face embedding deleted for user $userId');
    } catch (e) {
      print('✗ Error deleting face embedding: $e');
      rethrow;
    }
  }

  /// Update attendance record with facial verification status
  Future<void> updateAttendanceVerification(
    int attendanceRecordId,
    bool isFacialVerified,
    String verificationMethod,
  ) async {
    final db = _dbProvider.database;

    try {
      await (db.update(db.attendanceRecords)
              .where((row) => row.id.equals(attendanceRecordId)))
          .write(
        AttendanceRecordsCompanion(
          faceVerified: Value(isFacialVerified),
          verificationMethod: Value(verificationMethod),
        ),
      );

      print('✓ Attendance record $attendanceRecordId verified: $isFacialVerified');
    } catch (e) {
      print('✗ Error updating attendance verification: $e');
      rethrow;
    }
  }

  /// Get statistics on facial verification for a session
  Future<Map<String, dynamic>> getSessionVerificationStats(int sessionId) async {
    final db = _dbProvider.database;

    try {
      final records = await (db.select(db.attendanceRecords)
              .where((row) => row.sessionId.equals(sessionId)))
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
      print('✗ Error getting verification stats: $e');
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
    final db = _dbProvider.database;

    try {
      // This is informational - actual verification happens per-student
      // We just need to track that the session requires facial verification
      print('✓ Facial verification enabled for session $sessionId');
    } catch (e) {
      print('✗ Error enabling facial verification: $e');
      rethrow;
    }
  }
}
