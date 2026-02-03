import 'dart:io';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'database.g.dart';

// ========== TABLES ==========

/// Local user profile cache
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get firebaseUid => text().unique()();
  TextColumn get email => text()();
  TextColumn get name => text()();
  TextColumn get role => text()(); // 'student' or 'lecturer'
  TextColumn get externalId => text().nullable()(); // matric/staff number
  TextColumn get department => text().nullable()();
  BoolColumn get profileCompleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
}

/// Courses (for both students and lecturers)
class Courses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get serverId => text().nullable()(); // backend course ID
  TextColumn get code => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  IntColumn get lecturerId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
}

/// Student-Course enrollments
class Enrollments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get studentId => integer().references(Users, #id)();
  IntColumn get courseId => integer().references(Courses, #id)();
  DateTimeColumn get enrolledAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
}

/// Attendance sessions
class Sessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get serverId => text().nullable()();
  IntColumn get courseId => integer().references(Courses, #id)();
  TextColumn get sessionType => text()(); // 'lecture', 'lab', 'tutorial'
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime().nullable()();
  TextColumn get location => text().nullable()();
  TextColumn get status => text()(); // 'scheduled', 'active', 'completed', 'cancelled'
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
}

/// Individual attendance records
class AttendanceRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get serverId => text().nullable()();
  IntColumn get sessionId => integer().references(Sessions, #id)();
  IntColumn get studentId => integer().references(Users, #id)();
  TextColumn get status => text()(); // 'present', 'absent', 'late', 'excused'
  DateTimeColumn get markedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get faceVerified => boolean().withDefault(const Constant(false))();
  TextColumn get verificationMethod => text().nullable()(); // 'face', 'manual', 'qr'
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
}

/// Face recognition data
class FaceDataTable extends Table {
  @override
  String get tableName => 'face_data';
  
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().references(Users, #id)();
  TextColumn get embedding => text()(); // JSON array of face embedding
  DateTimeColumn get capturedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
}

/// Queue for operations pending sync to server
class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()(); // 'course', 'session', 'attendance', etc.
  IntColumn get entityLocalId => integer()();
  TextColumn get operation => text()(); // 'create', 'update', 'delete'
  TextColumn get payload => text()(); // JSON data
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
}

// ========== DATABASE ==========

@DriftDatabase(tables: [
  Users,
  Courses,
  Enrollments,
  Sessions,
  AttendanceRecords,
  FaceDataTable,
  SyncQueue,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Handle future schema upgrades here
      },
    );
  }

  // ========== USER OPERATIONS ==========

  Future<User?> getUserByFirebaseUid(String firebaseUid) {
    return (select(users)..where((u) => u.firebaseUid.equals(firebaseUid)))
        .getSingleOrNull();
  }

  Future<int> upsertUser(UsersCompanion user) async {
    // Check if user exists
    final existing = await (select(users)
          ..where((u) => u.firebaseUid.equals(user.firebaseUid.value)))
        .getSingleOrNull();

    if (existing != null) {
      // User exists, update it
      await update(users).replace(user.copyWith(id: Value(existing.id)));
      return existing.id;
    } else {
      // User doesn't exist, insert
      return await into(users).insert(user);
    }
  }

  // ========== COURSE OPERATIONS ==========

  Future<List<Course>> getAllCourses() {
    return select(courses).get();
  }

  Future<List<Course>> getCoursesByLecturer(int lecturerId) {
    return (select(courses)..where((c) => c.lecturerId.equals(lecturerId)))
        .get();
  }

  Future<int> insertCourse(CoursesCompanion course) {
    return into(courses).insert(course);
  }

  Future<Course?> getCourseByLocalId(int courseLocalId) {
    return (select(courses)..where((c) => c.id.equals(courseLocalId))).getSingleOrNull();
  }

  Future<Course?> getCourseByServerId(String serverId) {
    return (select(courses)..where((c) => c.serverId.equals(serverId))).getSingleOrNull();
  }

  Future<int> upsertCourseFromServer({
    required String serverId,
    required String code,
    required String name,
    String? description,
    int? lecturerId,
  }) async {
    final existing = await getCourseByServerId(serverId);
    final row = CoursesCompanion(
      serverId: Value(serverId),
      code: Value(code),
      name: Value(name),
      description: Value(description),
      lecturerId: Value(lecturerId),
      synced: const Value(true),
    );

    if (existing != null) {
      await update(courses).replace(row.copyWith(id: Value(existing.id)));
      return existing.id;
    }

    return into(courses).insert(row);
  }

  // ========== SESSION OPERATIONS ==========

  Future<List<Session>> getSessionsByCourse(int courseId) {
    return (select(sessions)..where((s) => s.courseId.equals(courseId)))
        .get();
  }

  Future<List<Session>> getActiveSessions() {
    return (select(sessions)..where((s) => s.status.equals('active'))).get();
  }

  Future<int> insertSession(SessionsCompanion session) async {
    final id = await into(sessions).insert(session);
    
    // Fetch the inserted session to build complete payload
    final insertedSession = await (select(sessions)..where((s) => s.id.equals(id))).getSingle();
    final course = await (select(courses)..where((c) => c.id.equals(insertedSession.courseId))).getSingleOrNull();
    
    // Add to sync queue with complete payload
    await _queueSync('session', id, 'create', {
      'session_id': insertedSession.serverId,
      'course_id': course?.serverId,
      'session_type': insertedSession.sessionType,
      'start_time': insertedSession.startTime.toIso8601String(),
      'end_time': insertedSession.endTime?.toIso8601String(),
      'location': insertedSession.location,
      'status': insertedSession.status,
    });
    return id;
  }

  Future<Session?> getSessionByServerId(String serverId) {
    return (select(sessions)..where((s) => s.serverId.equals(serverId))).getSingleOrNull();
  }

  Future<int> upsertSessionFromServer({
    required String serverId,
    required int courseLocalId,
    required DateTime startTime,
    DateTime? endTime,
    required String status,
  }) async {
    final existing = await getSessionByServerId(serverId);
    final row = SessionsCompanion(
      serverId: Value(serverId),
      courseId: Value(courseLocalId),
      sessionType: const Value('lecture'),
      startTime: Value(startTime),
      endTime: Value(endTime),
      location: const Value(null),
      status: Value(status),
      synced: const Value(true),
    );

    if (existing != null) {
      await update(sessions).replace(row.copyWith(id: Value(existing.id)));
      return existing.id;
    }
    return into(sessions).insert(row);
  }

  // ========== ENROLLMENT/ROSTER OPERATIONS ==========

  Future<void> ensureEnrollment({
    required int studentLocalId,
    required int courseLocalId,
  }) async {
    final existing = await (select(enrollments)
          ..where((e) => e.studentId.equals(studentLocalId) & e.courseId.equals(courseLocalId)))
        .getSingleOrNull();
    if (existing != null) return;

    await into(enrollments).insert(
      EnrollmentsCompanion(
        studentId: Value(studentLocalId),
        courseId: Value(courseLocalId),
        synced: const Value(true),
      ),
    );
  }

  Future<List<User>> getStudentsForCourse(int courseLocalId) async {
    final query = select(users).join([
      innerJoin(
        enrollments,
        enrollments.studentId.equalsExp(users.id) & enrollments.courseId.equals(courseLocalId),
      ),
    ]);

    final rows = await query.get();
    final seen = <int>{};
    final result = <User>[];
    for (final row in rows) {
      final u = row.readTable(users);
      if (seen.add(u.id)) result.add(u);
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  // ========== STUDENT-FACING QUERIES ==========

  /// Get a list of courses a student is enrolled in.
  Future<List<Course>> getCoursesForStudent(int studentLocalId) async {
    final query = select(courses).join([
      innerJoin(
        enrollments,
        enrollments.courseId.equalsExp(courses.id) & enrollments.studentId.equals(studentLocalId),
      ),
    ]);

    final rows = await query.get();
    final seen = <int>{};
    final result = <Course>[];
    for (final row in rows) {
      final c = row.readTable(courses);
      if (seen.add(c.id)) result.add(c);
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  /// Count how many enrollments a student has.
  Future<int> countEnrollmentsForStudent(int studentLocalId) async {
    return (select(enrollments)..where((e) => e.studentId.equals(studentLocalId))).get().then((v) => v.length);
  }

  /// Get sessions for courses the student is enrolled in.
  Future<List<Session>> getSessionsForStudent(int studentLocalId) async {
    final query = select(sessions).join([
      innerJoin(
        enrollments,
        enrollments.courseId.equalsExp(sessions.courseId) & enrollments.studentId.equals(studentLocalId),
      ),
    ]);

    final rows = await query.get();
    final seen = <int>{};
    final result = <Session>[];
    for (final row in rows) {
      final s = row.readTable(sessions);
      if (seen.add(s.id)) result.add(s);
    }
    result.sort((a, b) => a.startTime.compareTo(b.startTime));
    return result;
  }
  // ========== ATTENDANCE OPERATIONS ==========

  Future<List<AttendanceRecord>> getAttendanceBySession(int sessionId) {
    return (select(attendanceRecords)
          ..where((a) => a.sessionId.equals(sessionId)))
        .get();
  }

  Future<int> markAttendance(AttendanceRecordsCompanion record) async {
    final id = await into(attendanceRecords).insert(record);
    
    // Fetch the inserted attendance record to build complete payload
    final insertedRecord = await (select(attendanceRecords)..where((a) => a.id.equals(id))).getSingle();
    final session = await (select(sessions)..where((s) => s.id.equals(insertedRecord.sessionId))).getSingleOrNull();
    final student = await (select(users)..where((u) => u.id.equals(insertedRecord.studentId))).getSingleOrNull();
    
    // Add to sync queue with complete payload
    await _queueSync('attendance', id, 'create', {
      'attendance_id': insertedRecord.serverId,
      'session_id': session?.serverId,
      'student_firebase_uid': student?.firebaseUid,
      'status': insertedRecord.status,
      'timestamp': insertedRecord.markedAt.toIso8601String(),
      'face_verified': insertedRecord.faceVerified,
      'verification_method': insertedRecord.verificationMethod,
    });
    return id;
  }

  Future<AttendanceRecord?> getAttendanceByServerId(String serverId) {
    return (select(attendanceRecords)..where((a) => a.serverId.equals(serverId))).getSingleOrNull();
  }

  Future<int> upsertAttendanceFromServer({
    required String serverId,
    required int sessionLocalId,
    required int studentLocalId,
    required String status,
    required DateTime markedAt,
    required bool faceVerified,
  }) async {
    final existing = await getAttendanceByServerId(serverId);
    final row = AttendanceRecordsCompanion(
      serverId: Value(serverId),
      sessionId: Value(sessionLocalId),
      studentId: Value(studentLocalId),
      status: Value(status),
      markedAt: Value(markedAt),
      faceVerified: Value(faceVerified),
      verificationMethod: const Value(null),
      synced: const Value(true),
    );

    if (existing != null) {
      await update(attendanceRecords).replace(row.copyWith(id: Value(existing.id)));
      return existing.id;
    }
    return into(attendanceRecords).insert(row);
  }

  Future<List<AttendanceWithStudent>> getAttendanceWithStudentForSession(int sessionLocalId) async {
    final query = select(attendanceRecords).join([
      innerJoin(users, users.id.equalsExp(attendanceRecords.studentId)),
    ])
      ..where(attendanceRecords.sessionId.equals(sessionLocalId))
      ..orderBy([
        OrderingTerm.asc(users.name),
      ]);

    final rows = await query.get();
    return [
      for (final row in rows)
        AttendanceWithStudent(
          record: row.readTable(attendanceRecords),
          student: row.readTable(users),
        ),
    ];
  }

  // ========== SYNC OPERATIONS ==========

  Future<List<SyncQueueData>> getPendingSyncItems() {
    return (select(syncQueue)..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<void> _queueSync(
    String entityType,
    int entityId,
    String operation,
    Map<String, dynamic> payload,
  ) {
    return into(syncQueue).insert(
      SyncQueueCompanion.insert(
        entityType: entityType,
        entityLocalId: entityId,
        operation: operation,
        payload: jsonEncode(payload),
      ),
    );
  }

  Future<void> markSyncComplete(int syncQueueId) {
    return (delete(syncQueue)..where((sq) => sq.id.equals(syncQueueId))).go();
  }

  Future<void> incrementSyncRetry(int syncQueueId, String error) async {
    // Get current retry count
    final item = await (select(syncQueue)..where((sq) => sq.id.equals(syncQueueId)))
        .getSingleOrNull();
    if (item == null) return;

    // Update with incremented count
    await (update(syncQueue)..where((sq) => sq.id.equals(syncQueueId))).write(
      SyncQueueCompanion(
        retryCount: Value(item.retryCount + 1),
        lastError: Value(error),
      ),
    );
  }
}

class AttendanceWithStudent {
  final AttendanceRecord record;
  final User student;

  AttendanceWithStudent({
    required this.record,
    required this.student,
  });
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attendance.db'));
    return NativeDatabase.createInBackground(file);
  });
}
