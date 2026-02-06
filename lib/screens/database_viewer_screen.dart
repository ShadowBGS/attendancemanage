import 'package:flutter/material.dart';
import '../db/database_provider.dart';
import '../db/database.dart';

class DatabaseViewerScreen extends StatefulWidget {
  const DatabaseViewerScreen({super.key});

  @override
  State<DatabaseViewerScreen> createState() => _DatabaseViewerScreenState();
}

class _DatabaseViewerScreenState extends State<DatabaseViewerScreen> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final db = DatabaseProvider.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Database Viewer'),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Clear Sync Queue',
            icon: const Icon(Icons.clear_all),
            onPressed: () => _clearSyncQueue(db),
          ),
        ],
      ),
      body: Column(
        children: [
          // Tab Bar
          Container(
            color: Colors.white,
            child: Row(
              children: [
                _buildTab('Sessions', 0),
                _buildTab('Attendance', 1),
                _buildTab('Enrollments', 2),
                _buildTab('Users', 3),
              ],
            ),
          ),
          // Content
          Expanded(
            child: _buildContent(db),
          ),
        ],
      ),
    );
  }

  Future<void> _clearSyncQueue(AppDatabase db) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Sync Queue?'),
        content: const Text('This will delete all pending sync items. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await db.clearSyncQueue();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sync queue cleared'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Widget _buildTab(String label, int index) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? const Color(0xFF0D47A1) : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? const Color(0xFF0D47A1) : Colors.grey,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(AppDatabase db) {
    switch (_selectedTab) {
      case 0:
        return _buildSessions(db);
      case 1:
        return _buildAttendance(db);
      case 2:
        return _buildEnrollments(db);
      case 3:
        return _buildUsers(db);
      default:
        return const SizedBox();
    }
  }

  Widget _buildSessions(AppDatabase db) {
    return FutureBuilder<List<Session>>(
      future: db.select(db.sessions).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final sessions = snapshot.data!;
        if (sessions.isEmpty) {
          return const Center(child: Text('No sessions found'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sessions.length,
          itemBuilder: (context, index) {
            final session = sessions[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Session ID: ${session.id}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Course ID: ${session.courseId}'),
                    Text('Type: ${session.sessionType}'),
                    Text('Status: ${session.status}'),
                    Text('Started: ${session.startTime}'),
                    if (session.endTime != null)
                      Text('Ended: ${session.endTime}'),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAttendance(AppDatabase db) {
    return FutureBuilder<List<AttendanceRecord>>(
      future: db.select(db.attendanceRecords).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final records = snapshot.data!;
        if (records.isEmpty) {
          return const Center(child: Text('No attendance records found'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: records.length,
          itemBuilder: (context, index) {
            final record = records[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Attendance ID: ${record.id}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Session ID: ${record.sessionId}'),
                    Text('Student ID: ${record.studentId}'),
                    Text('Status: ${record.status}'),
                    Text('Marked: ${record.markedAt}'),
                    Text('Method: ${record.verificationMethod ?? "N/A"}'),
                    Text('Synced: ${record.synced}'),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEnrollments(AppDatabase db) {
    return FutureBuilder<List<Enrollment>>(
      future: db.select(db.enrollments).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final enrollments = snapshot.data!;
        if (enrollments.isEmpty) {
          return const Center(child: Text('No enrollments found'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: enrollments.length,
          itemBuilder: (context, index) {
            final enrollment = enrollments[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Enrollment ID: ${enrollment.id}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Student ID: ${enrollment.studentId}'),
                    Text('Course ID: ${enrollment.courseId}'),
                    Text('Enrolled: ${enrollment.enrolledAt}'),
                    Text('Synced: ${enrollment.synced}'),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUsers(AppDatabase db) {
    return FutureBuilder<List<User>>(
      future: db.select(db.users).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final users = snapshot.data!;
        if (users.isEmpty) {
          return const Center(child: Text('No users found'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('User ID: ${user.id}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Name: ${user.name}'),
                    Text('Email: ${user.email}'),
                    Text('Role: ${user.role}'),
                    Text('Firebase UID: ${user.firebaseUid}'),
                    if (user.externalId != null)
                      Text('External ID: ${user.externalId}'),
                    if (user.department != null)
                      Text('Department: ${user.department}'),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
