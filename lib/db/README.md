# Offline Database Structure

This app uses **Drift** (SQLite) for offline data storage and sync.

## Database Tables

### 1. **users**
Cached user profile information
- `firebaseUid` - Links to Firebase Auth
- `email`, `name`, `role` (student/lecturer)
- `externalId` - Matric number (student) or Staff ID (lecturer)
- `department`, `profileCompleted`
- `lastSyncedAt` - Track when profile was last synced

### 2. **courses**
Course information accessible offline
- `code`, `name`, `description`
- `lecturerId` - Who teaches this course
- `serverId` - Backend course ID (null if created offline)
- `synced` - Whether changes have been pushed to server

### 3. **enrollments**
Student-course relationships
- Links students to their courses
- Enables offline access to student rosters

### 4. **sessions**
Attendance sessions (created by lecturers)
- `courseId`, `sessionType` (lecture/lab/tutorial)
- `startTime`, `endTime`, `location`
- `status` - scheduled/active/completed/cancelled
- Created offline, synced when online

### 5. **attendance_records**
Individual attendance marks (the core data!)
- `sessionId`, `studentId`
- `status` - present/absent/late/excused
- `faceVerified` - Was face recognition used?
- `verificationMethod` - face/manual/qr
- Critical for offline marking capability

### 6. **face_data**
Face embeddings for offline recognition
- `userId`, `embedding` (JSON array)
- Allows face verification without internet

### 7. **sync_queue**
Operations waiting to sync to server
- Tracks creates/updates/deletes made offline
- `entityType`, `operation`, `payload`
- `retryCount`, `lastError` for resilience

## Offline Capabilities

**Lecturer:**
- ✅ View course rosters
- ✅ Create attendance sessions
- ✅ Mark attendance (manual or face recognition)
- ✅ View session history
- 📡 Sync all changes when online

**Student:**
- ✅ View enrolled courses
- ✅ See upcoming sessions
- ✅ Check-in with face (if already captured)
- 📡 Sync attendance when online

## Sync Strategy

1. **On app start** (if online):
   - Pull latest courses, enrollments, sessions from server
   - Update local cache

2. **During use** (offline or online):
   - All operations write to local DB first
   - Changes queued in `sync_queue`

3. **When connection detected**:
   - Process `sync_queue` items in order
   - Push creates/updates/deletes to server
   - Update `serverId` fields with backend IDs
   - Mark items as `synced`

4. **Conflict resolution**:
   - Server timestamp wins for updates
   - Local deletes take priority

## Usage in Code

```dart
import 'package:attendance/db/database.dart';

// Initialize (typically in main.dart)
final db = AppDatabase();

// Get current user's courses
final courses = await db.getCoursesByLecturer(lecturerId);

// Mark attendance offline
await db.markAttendance(
  AttendanceRecordsCompanion.insert(
    sessionId: sessionId,
    studentId: studentId,
    status: 'present',
    faceVerified: Value(true),
  ),
);

// Later, sync to server
final pending = await db.getPendingSyncItems();
for (final item in pending) {
  // Push to server, then:
  await db.markSyncComplete(item.id);
}
```

## Next Steps

1. **Wire database into app**:
   - Initialize in `main.dart`
   - Replace direct HTTP calls with DB writes
   - Add background sync service

2. **Implement sync service**:
   - Listen for connectivity changes
   - Process sync queue automatically
   - Handle conflicts gracefully

3. **Add face recognition**:
   - Capture and store face embeddings
   - Offline face matching using stored embeddings
   - Sync new face data to server
