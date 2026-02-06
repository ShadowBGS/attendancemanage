import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../db/database_provider.dart';
import '../services/sync_service.dart';

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

      final sync = SyncService(database: db, baseUrl: baseUrl);
      
      // Push any pending changes first, then pull latest data
      await sync.syncPendingChanges();
      
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
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Check-in',
          style: TextStyle(
            color: Colors.black,
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
                          color: widget.success ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
                          boxShadow: [
                            BoxShadow(
                              color: widget.success 
                                  ? const Color(0xFF4CAF50).withOpacity(0.3)
                                  : const Color(0xFFE53935).withOpacity(0.3),
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
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Subtitle
                      if (widget.success)
                        const Text(
                          "You're all set for today's session.",
                          style: TextStyle(
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
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
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
                                  color: const Color(0xFF0D47A1).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Current Session',
                                  style: TextStyle(
                                    color: Color(0xFF0D47A1),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ] else ...[
                              const Text(
                                'SESSION DETAILS',
                                style: TextStyle(
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
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),

                            if (!widget.success && widget.courseName.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                widget.courseName,
                                style: const TextStyle(
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
                                  const Icon(
                                    Icons.calendar_today,
                                    size: 20,
                                    color: Color(0xFF0D47A1),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    DateFormat('MMMM dd, yyyy').format(widget.timestamp!),
                                    style: const TextStyle(
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
                                  const Icon(
                                    Icons.access_time,
                                    size: 20,
                                    color: Color(0xFF0D47A1),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Checked in at ${DateFormat('h:mm a').format(widget.timestamp!)}',
                                    style: const TextStyle(
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
                            color: Colors.red,
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
                          backgroundColor: const Color(0xFF0D47A1),
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
                              // Pop result screen, then scanner screen to return to dashboard
                              Navigator.pop(context);
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0D47A1),
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
                              // On failure, just pop back to scanner
                              Navigator.pop(context);
                            },
                            child: const Text(
                              'Back to Dashboard',
                              style: TextStyle(
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
