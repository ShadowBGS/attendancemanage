import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../db/database_provider.dart';
import '../db/database.dart';
import '../theme/app_colors.dart';

class StudentCourseDetailScreen extends StatefulWidget {
  final Course course;

  const StudentCourseDetailScreen({
    super.key,
    required this.course,
  });

  @override
  State<StudentCourseDetailScreen> createState() => _StudentCourseDetailScreenState();
}

class _StudentCourseDetailScreenState extends State<StudentCourseDetailScreen> {
  List<Session> _sessions = [];
  int _attendedSessions = 0;
  double _attendancePercentage = 0.0;
  bool _isLoading = true;
  bool _didLoadInitialData = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoadInitialData) {
      _didLoadInitialData = true;
      _loadCourseData();
    }
  }

  Future<void> _loadCourseData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('❌ No Firebase user logged in');
        return;
      }

      print('📊 Loading course data for: ${widget.course.code} (ID: ${widget.course.id})');

      final db = DatabaseProvider.of(context);
      final cachedUser = await db.getUserByFirebaseUid(user.uid);
      if (cachedUser == null) {
        print('❌ No cached user found for UID: ${user.uid}');
        return;
      }

      print('👤 Found cached user: ${cachedUser.email} (Local ID: ${cachedUser.id})');

      // Get sessions for this course and student
      final sessions = await db.getSessionsByCourse(widget.course.id);
      print('📅 Found ${sessions.length} sessions for course ${widget.course.code}');
      
      if (sessions.isNotEmpty) {
        for (var i = 0; i < sessions.length; i++) {
          print('   Session ${i + 1}: ID=${sessions[i].id}, Start=${sessions[i].startTime}, Status=${sessions[i].status}');
        }
      }
      
      // Get attendance records for this student in this course
      int attended = 0;
      for (var session in sessions) {
        try {
          final attendance = await db.getAttendanceByStudentAndSession(cachedUser.id, session.id);
          if (attendance != null) {
            print('   ✓ Attendance for session ${session.id}: ${attendance.status}');
            if (attendance.status == 'present') {
              attended++;
            }
          } else {
            print('   ✗ No attendance record for session ${session.id}');
          }
        } catch (e) {
          // Handle duplicate records - skip and continue
          print('   ⚠️  Multiple attendance records for session ${session.id}, skipping');
        }
      }

      final percentage = sessions.isEmpty ? 0.0 : (attended / sessions.length) * 100;
      print('📈 Attendance: $attended/${ sessions.length} sessions = ${percentage.toStringAsFixed(1)}%');

      if (mounted) {
        setState(() {
          _sessions = sessions;
          _attendedSessions = attended;
          _attendancePercentage = percentage;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading course data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: RefreshIndicator(
                onRefresh: _loadCourseData,
                child: CustomScrollView(
                  slivers: [
                    // Header
                    SliverAppBar(
                      expandedHeight: 120,
                      pinned: true,
                      backgroundColor: AppColors.primaryBlue,
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      title: Text(
                        widget.course.code,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      flexibleSpace: FlexibleSpaceBar(
                        collapseMode: CollapseMode.parallax,
                        background: Container(
                          padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
                          alignment: Alignment.bottomLeft,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // r
                              const SizedBox(height: 4),
                              Text(
                                widget.course.name,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Overall Standing Card
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).shadowColor.withOpacity(0.12),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                    Text(
                                      'OVERALL STANDING',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).textTheme.titleSmall?.color,
                                      ),
                                    ),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryBlue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.bar_chart_rounded,
                                      color: AppColors.primaryBlue,
                                      size: 24,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  // Circular progress
                                  SizedBox(
                                    width: 120,
                                    height: 120,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        CircularProgressIndicator(
                                          value: _attendancePercentage / 100,
                                          strokeWidth: 10,
                                          backgroundColor: AppColors.primaryBlue.withOpacity(0.15),
                                          valueColor: const AlwaysStoppedAnimation<Color>(
                                            AppColors.primaryBlue,
                                          ),
                                          strokeCap: StrokeCap.round,
                                        ),
                                        Center(
                                          child: Text(
                                            '${_attendancePercentage.toStringAsFixed(0)}%',
                                            style: TextStyle(
                                              fontSize: 32,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context).textTheme.headlineSmall?.color,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 24),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Attendance:',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Theme.of(context).textTheme.bodyMedium?.color,
                                          ),
                                        ),
                                        Text(
                                          '${_attendancePercentage.toStringAsFixed(0)}%',
                                          style: TextStyle(
                                            fontSize: 32,
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context).textTheme.headlineSmall?.color,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'You have attended $_attendedSessions out of ${_sessions.length} sessions recorded.',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Theme.of(context).textTheme.bodyMedium?.color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Attendance History
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Attendance History',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).textTheme.titleLarge?.color,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${_sessions.length} Sessions',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(context).textTheme.bodyMedium?.color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Sessions List
                  _sessions.isEmpty
                      ? SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(40),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.calendar_today_outlined,
                                  size: 64,
                                  color: Theme.of(context).hintColor.withOpacity(0.5),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No sessions recorded yet',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Theme.of(context).textTheme.bodyMedium?.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final session = _sessions[index];
                              return FutureBuilder<AttendanceRecord?>(
                                future: _getAttendanceStatus(session.id),
                                builder: (context, snapshot) {
                                  final status = snapshot.data?.status ?? 'absent';
                                  return _SessionCard(
                                    sessionNumber: _sessions.length - index,
                                    dateTime: session.startTime,
                                    status: status,
                                  );
                                },
                              );
                            },
                            childCount: _sessions.length,
                          ),
                        ),

                  SliverToBoxAdapter(
                    child: const SizedBox(height: 20),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Future<AttendanceRecord?> _getAttendanceStatus(int sessionId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final db = DatabaseProvider.of(context);
      final cachedUser = await db.getUserByFirebaseUid(user.uid);
      if (cachedUser == null) return null;

      return await db.getAttendanceByStudentAndSession(cachedUser.id, sessionId);
    } catch (_) {
      return null;
    }
  }
}

class _SessionCard extends StatelessWidget {
  final int sessionNumber;
  final DateTime dateTime;
  final String status;

  const _SessionCard({
    required this.sessionNumber,
    required this.dateTime,
    required this.status,
  });

  Color _getStatusColor(BuildContext context) {
    switch (status.toLowerCase()) {
      case 'present':
        return Colors.green;
      case 'absent':
        return Theme.of(context).hintColor;
      case 'late':
        return Colors.orange;
      default:
        return Theme.of(context).hintColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final month = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][dateTime.month - 1];
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).shadowColor.withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.event_available_rounded,
                  color: AppColors.primaryBlue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session $sessionNumber',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$month ${dateTime.day}, ${dateTime.year} • ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')} AM',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getStatusColor(context).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _getStatusColor(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
