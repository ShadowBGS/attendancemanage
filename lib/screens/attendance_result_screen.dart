import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
//import 'package:drift/drift.dart' show Value;
import '../db/database_provider.dart';
import '../theme/app_colors.dart';
//import '../db/database.dart';
//import '../services/sync_service.dart';

class AttendanceResultScreen extends StatefulWidget {
  final bool success;
  final String courseCode;
  final String courseName;
  final DateTime? timestamp;
  final String? errorMessage;

  const AttendanceResultScreen({
    super.key,
    required this.success,
    required this.courseCode,
    required this.courseName,
    this.timestamp,
    this.errorMessage,
  });

  @override
  State<AttendanceResultScreen> createState() => _AttendanceResultScreenState();
}

class _AttendanceResultScreenState extends State<AttendanceResultScreen> {
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    // If attendance was marked successfully, sync with backend immediately
    if (widget.success) {
      Future.microtask(() => _syncAfterSuccess());
    }
  }

  Future<void> _syncAfterSuccess() async {
    try {
      setState(() => _syncing = true);
      
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      const overrideUrl = String.fromEnvironment('BACKEND_URL');
      final baseUrl = overrideUrl.isNotEmpty ? overrideUrl : 'https://att-back-0xvj.onrender.com';
      final db = DatabaseProvider.of(context);

      // Wait a few seconds for lecturer to sync attendance to backend
      // The backend will auto-enroll the student when attendance is synced
      await Future.delayed(const Duration(seconds: 3));
      
      // Fetch updated courses and enrollments from backend
      try {
        final idToken = await user.getIdToken();
        if (idToken != null) {
          final coursesResponse = await http.get(
            Uri.parse(baseUrl).resolve('/student/my-courses'),
            headers: {'Authorization': 'Bearer $idToken'},
          ).timeout(const Duration(seconds: 10));

          if (coursesResponse.statusCode == 200) {
            final coursesData = jsonDecode(coursesResponse.body);
            final enrolledCourses = coursesData['enrolled_courses'] as List? ?? [];
            
            // Get current user's local ID
            final currentUser = await db.getUserByFirebaseUid(user.uid);
            if (currentUser != null) {
              // Track processed course IDs to avoid duplicates in this sync operation
              final processedCourseIds = <String>{};
              
              // Store courses and enrollments in local DB
              for (final courseJson in enrolledCourses) {
                try {
                  final courseId = courseJson['course_id']?.toString() ?? '';
                  final courseCode = courseJson['course_code']?.toString() ?? '';
                  final courseName = courseJson['course_name']?.toString() ?? '';
                  final lecturerId = courseJson['lecturer_id'] as int?;
                  
                  if (courseId.isEmpty || processedCourseIds.contains(courseId)) continue;
                  processedCourseIds.add(courseId);
                  
                  // Upsert course
                  await db.upsertCourseFromServer(
                    serverId: courseId,
                    code: courseCode,
                    name: courseName,
                    description: null,
                    lecturerId: lecturerId,
                  );
                  
                  // Get the local course to create enrollment
                  final localCourse = await db.getCourseByServerId(courseId);
                  if (localCourse != null) {
                    await db.ensureEnrollment(
                      studentLocalId: currentUser.id,
                      courseLocalId: localCourse.id,
                    );
                  }
                } catch (e) {
                  // Ignore local caching errors; backend already created it.
                }
              }
            }
          }
        }
      } catch (e) {
        // Silently fail if fetching courses after attendance fails
      }
      
      if (mounted) {
        setState(() => _syncing = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).appBarTheme.iconTheme?.color ?? Theme.of(context).textTheme.bodyLarge?.color),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Check-in',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ) ?? const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Success/Failure Icon
                      Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.success ? AppColors.successGreen : AppColors.errorRed,
                          boxShadow: [
                            BoxShadow(
                              color: widget.success 
                                  ? AppColors.successGreen.withValues(alpha: 0.3)
                                  : AppColors.errorRed.withValues(alpha: 0.3),
                              blurRadius: 40,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: Icon(
                          widget.success ? Icons.check : Icons.close,
                          size: 80,
                          color: Colors.white,
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Title
                      Text(
                        _syncing
                            ? 'Syncing your record...'
                            : (widget.success ? 'Attendance Recorded!' : 'Attendance Failed'),
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ) ?? const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Subtitle
                      if (widget.success)
                        Text(
                          "You're all set for today's session.",
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                          ) ?? const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),

                      const SizedBox(height: 40),

                      // Session Details Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.success) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryBlue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Current Session',
                                  style: TextStyle(
                                    color: AppColors.primaryBlue,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ] else ...[
                              Text(
                                'SESSION DETAILS',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                  color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                                ) ?? const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // Course Code and Name
                            Text(
                              widget.success ? '${widget.courseCode}: ${widget.courseName}' : widget.courseCode,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ) ?? const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            if (!widget.success && widget.courseName.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                widget.courseName,
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                                ) ?? const TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ],

                            if (widget.success && widget.timestamp != null) ...[
                              const SizedBox(height: 20),

                              // Date
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 20,
                                    color: AppColors.primaryBlue,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    DateFormat('MMMM dd, yyyy').format(widget.timestamp!),
                                    style: Theme.of(context).textTheme.bodyLarge ?? const TextStyle(
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),

                              // Time
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 20,
                                    color: AppColors.primaryBlue,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Checked in at ${DateFormat('h:mm a').format(widget.timestamp!)}',
                                    style: Theme.of(context).textTheme.bodyLarge ?? const TextStyle(
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),

                      if (!widget.success && widget.errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          widget.errorMessage!,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.errorRed,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Bottom Buttons
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  if (!widget.success) ...[
                    // Try Again Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
                        label: const Text(
                          'Try Again',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Back to Dashboard Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: widget.success
                        ? ElevatedButton(
                            onPressed: () {
                              // Pop back to dashboard (scan screen was replaced, so just one pop)
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryBlue,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'Back to Dashboard',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : TextButton(
                            onPressed: () {
                              // On failure, pop back to dashboard
                              Navigator.pop(context);
                            },
                            child: Text(
                              'Back to Dashboard',
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                              ) ?? const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
