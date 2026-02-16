import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../models/wifi_direct_payload.dart';
import '../services/wifi_direct_session_service.dart';

import '../db/database_provider.dart';
import '../db/database.dart';
import '../theme/app_colors.dart';

class WifiDirectHostScreen extends StatefulWidget {
  final String courseCode;
  final String courseName;
  final int courseLocalId;
  final DateTime sessionDate;

  WifiDirectHostScreen({
    super.key,
    required this.courseCode,
    required this.courseName,
    required this.courseLocalId,
    DateTime? sessionDate,
  }) : sessionDate = sessionDate ?? DateTime.now();

  @override
  State<WifiDirectHostScreen> createState() => _WifiDirectHostScreenState();
}

class _WifiDirectHostScreenState extends State<WifiDirectHostScreen> with WidgetsBindingObserver {
  final WifiDirectSessionService _service = WifiDirectSessionService();
  WifiDirectPayload? _payload;
  bool _loading = true;

  String? _errorMessage;
  final List<AttendanceMessage> _attendees = [];
  final List<AttendanceMessage> _pendingPersist = [];

  StreamSubscription<AttendanceMessage>? _sub;
  StreamSubscription<List<P2pClientInfo>>? _clientSub;
  int? _sessionLocalId;
  Timer? _refreshTimer;
  Timer? _countdownTimer;
  int _secondsRemaining = 60;
  
  // Cache student details to avoid repeated database lookups
  final Map<String, String?> _matricCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Clean up hotspot only when app is actually closing, not when going to background
    if (state == AppLifecycleState.detached) {
      print('🚪 App closing, cleaning up hotspot...');
      _cleanupHotspot();
    }
  }

  Future<void> _start() async {
    try {
      // IMPORTANT: Stop any existing hotspot first to avoid "Caller already has an active LocalOnlyHotspot" error
      print('🧹 Ensuring any existing hotspot is stopped before starting new one...');
      try {
        await _service.stopHostSession();
        await Future.delayed(const Duration(milliseconds: 500)); // Give system time to cleanup
        print('✅ Existing hotspot stopped');
      } catch (e) {
        print('⚠️  Error stopping existing hotspot (may not exist): $e');
        // Continue anyway - it's ok if there was no existing hotspot
      }

      final payload = await _service.startHostSession(
        courseCode: widget.courseCode,
        courseName: widget.courseName,
        onStatus: (s) {
          if (!mounted) return;
          setState(() => _status = s);
        },
      );
      if (!mounted) return;

      setState(() {
        _payload = payload;
        _loading = false;
        _status = null;
        _errorMessage = null;
        _secondsRemaining = 60;
      });

      // Start refresh timers
      _startRefreshTimers();

      // Subscribe immediately; broadcast streams do not buffer events.
      _clientSub = _service.clientsStream.listen((clients) {
        if (!mounted) return;
        setState(() => _clients = clients);
      });

      _sub = _service.attendanceStream.listen((msg) async {
        // Always update UI first.
        if (mounted) {
          // Cache matric number from the message itself (sent by student)
          if (msg.matricNumber != null && msg.matricNumber!.isNotEmpty) {
            _matricCache[msg.studentId] = msg.matricNumber;
          }
          
          setState(() {
            _attendees.removeWhere((m) => m.studentId == msg.studentId);
            _attendees.add(msg);
          });
        }

        // If the local DB session isn't created yet, queue persistence.
        if (_sessionLocalId == null) {
          _pendingPersist.removeWhere((m) => m.studentId == msg.studentId);
          _pendingPersist.add(msg);
          return;
        }

        // Persist to local DB (best effort; never block UI updates).
        try {
          if (!mounted) return;
          final db = DatabaseProvider.of(context);
          final sid = _sessionLocalId;
          print('💾 Persisting attendance for ${msg.studentName} (${msg.studentId}), session: $sid');

          final existing = await db.getUserByFirebaseUid(msg.studentId);
          int studentLocalId;
          if (existing != null) {
            studentLocalId = existing.id;
            print('   Found existing student with ID: $studentLocalId');
          } else {
            studentLocalId = await db.upsertUser(
              UsersCompanion.insert(
                firebaseUid: msg.studentId,
                email: '',
                name: msg.studentName.isNotEmpty ? msg.studentName : msg.studentId,
                role: 'student',
                externalId: const Value(null),
                department: const Value(null),
                profileCompleted: const Value(false),
                lastSyncedAt: const Value(null),
              ),
            );
            print('   Created new student with ID: $studentLocalId');
          }

          if (sid != null) {
            final attendanceId = await db.markAttendance(
              AttendanceRecordsCompanion.insert(
                serverId: const Value(null),
                sessionId: sid,
                studentId: studentLocalId,
                status: 'present',
                markedAt: Value(msg.timestamp),
                faceVerified: const Value(false),
                verificationMethod: const Value('qr'),
                synced: const Value(false),
              ),
            );
            print('   ✅ Attendance record created with ID: $attendanceId');
          } else {
            print('   ⚠️ Session ID is null, cannot save attendance');
          }
        } catch (e) {
          print('   ❌ Error saving attendance: $e');
        }
      });

      // Create session on server FIRST to get serverId immediately
      final db = DatabaseProvider.of(context);
      String? serverSessionId;
      
      try {
        print('🔄 Creating session on server first...');
        serverSessionId = await _createSessionOnServer();
        print('✅ Got server session ID: $serverSessionId');
      } catch (e) {
        print('⚠️ Could not create session on server (will sync later): $e');
        // Continue anyway - session will sync via sync queue
      }

      // Create local session - use direct insert to avoid duplicate sync queue when we have serverId
      int sessionId;
      if (serverSessionId != null) {
        // Session already exists on server, insert directly without queueing sync
        sessionId = await db.into(db.sessions).insert(
          SessionsCompanion.insert(
            serverId: Value(serverSessionId),
            courseId: widget.courseLocalId,
            sessionType: 'lecture',
            startTime: DateTime.now(),
            endTime: const Value(null),
            location: const Value(null),
            status: 'active',
            synced: const Value(true), // Already synced!
          ),
        );
      } else {
        // No serverId, use normal insert which will queue sync
        sessionId = await db.insertSession(
          SessionsCompanion.insert(
            serverId: const Value(null),
            courseId: widget.courseLocalId,
            sessionType: 'lecture',
            startTime: DateTime.now(),
            endTime: const Value(null),
            location: const Value(null),
            status: 'active',
            synced: const Value(false),
          ),
        );
      }
      
      if (!mounted) return;
      print('✅ Session created locally with ID: $sessionId, serverId: $serverSessionId');
      setState(() => _sessionLocalId = sessionId);

      // Flush any attendance received before session creation.
      print('📝 Flushing ${_pendingPersist.length} pending attendance records');
      for (final msg in List<AttendanceMessage>.from(_pendingPersist)) {
        try {
          print('   Processing pending: ${msg.studentName} (${msg.studentId})');
          final existing = await db.getUserByFirebaseUid(msg.studentId);
          int studentLocalId;
          if (existing != null) {
            studentLocalId = existing.id;
            print('   Found existing student with ID: $studentLocalId');
          } else {
            studentLocalId = await db.upsertUser(
              UsersCompanion.insert(
                firebaseUid: msg.studentId,
                email: '',
                name: msg.studentName.isNotEmpty ? msg.studentName : msg.studentId,
                role: 'student',
                externalId: const Value(null),
                department: const Value(null),
                profileCompleted: const Value(false),
                lastSyncedAt: const Value(null),
              ),
            );
            print('   Created new student with ID: $studentLocalId');
          }

          final attendanceId = await db.markAttendance(
            AttendanceRecordsCompanion.insert(
              serverId: const Value(null),
              sessionId: sessionId,
              studentId: studentLocalId,
              status: 'present',
              markedAt: Value(msg.timestamp),
              faceVerified: const Value(false),
              verificationMethod: const Value('qr'),
              synced: const Value(false),
            ),
          );
          print('   ✅ Pending attendance saved with ID: $attendanceId');
        } catch (e) {
          print('   ❌ Error flushing pending attendance: $e');
        }
      }
      _pendingPersist.clear();
    } catch (e) {
      print('❌ [WiFi Host] Fatal error starting session: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Dismiss'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Retry starting the session
              setState(() {
                _loading = true;
                _errorMessage = null;
              });
              _start();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _startRefreshTimers() {
    // Refresh QR code every 60 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      _refreshPayload();
    });

    // Countdown timer updates every second
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _secondsRemaining--;
        if (_secondsRemaining <= 0) {
          _secondsRemaining = 60;
        }
      });
    });
  }

  Future<void> _refreshPayload() async {
    try {
      await _service.stopHostSession();
      final newPayload = await _service.startHostSession(
        courseCode: widget.courseCode,
        courseName: widget.courseName,
        onStatus: (s) {
          if (!mounted) return;
          setState(() => _status = s);
        },
      );
      if (!mounted) return;
      setState(() {
        _payload = newPayload;
        _secondsRemaining = 60;
      });
    } catch (e) {
      // Silently fail - keep old payload active
    }
  }

  Future<void> _cleanupHotspot() async {
    print('🛑 Cleaning up WiFi Direct hotspot...');
    try {
      await _service.stopHostSession();
      print('✅ Hotspot stopped');
    } catch (e) {
      print('⚠️  Error stopping hotspot: $e');
    }
  }

  @override
  void dispose() {
    print('🔴 WifiDirectHostScreen.dispose() called');
    WidgetsBinding.instance.removeObserver(this);
    
    _refreshTimer?.cancel();
    _countdownTimer?.cancel();
    _sub?.cancel();
    _clientSub?.cancel();
    
    print('🛑 Stopping WiFi Direct host session and cleaning up hotspot...');
    // Use synchronous cleanup in dispose to ensure it happens before screen is destroyed
    _cleanupHotspot().then((_) {
      _service.dispose();
      print('✅ WiFi Direct cleanup complete');
    }).catchError((e) {
      print('❌ Error during cleanup: $e');
      _service.dispose();
    });
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final payload = _payload;
    final displayDate = widget.sessionDate.millisecondsSinceEpoch > 0 
        ? widget.sessionDate 
        : DateTime.now();
    
    // Show error state if session failed to start
    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.error_outline,
                      size: 40,
                      color: Colors.red,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Session Failed',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Back'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _loading = true;
                            _errorMessage = null;
                          });
                          _start();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Retry',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
              ),
            )
          : payload == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text(
                          'Could not start session',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _start,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            foregroundColor: AppColors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : SafeArea(
                  child: Column(
                    children: [
                      // Blue Header with Course Info and LIVE indicator
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                        decoration: const BoxDecoration(
                          color: AppColors.primaryBlue,
                          // borderRadius: BorderRadius.only(
                          //   bottomLeft: Radius.circular(24),
                          //   bottomRight: Radius.circular(24),
                          // ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        widget.courseCode,
                                        style: const TextStyle(
                                          color: AppColors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        DateFormat('MMM dd, yyyy').format(displayDate),
                                        style: TextStyle(
                                          color: AppColors.white.withOpacity(0.9),
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(Icons.circle, color: AppColors.white, size: 8),
                                      SizedBox(width: 6),
                                      Text(
                                        'LIVE',
                                        style: TextStyle(
                                          color: AppColors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
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

                      // Main Content
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // QR Code Card
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.black.withOpacity(0.05),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    // QR Code
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: AppColors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: AppColors.grey,
                                          width: 2,
                                        ),
                                      ),
                                      child: QrImageView(
                                        data: payload.toEncodedString(),
                                        version: QrVersions.auto,
                                        size: 240,
                                        backgroundColor: AppColors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    const Text(
                                      'Scan to mark attendance',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primaryBlue,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.timer, size: 16, color: AppColors.grey),
                                        const SizedBox(width: 6),
                                        const Text(
                                          'Code refreshes in ',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: AppColors.grey,
                                          ),
                                        ),
                                        Text(
                                          '${_secondsRemaining}s',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: AppColors.primaryBlue,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 24),

                              // Students Joined Header
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Students Joined (${_attendees.length})',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).textTheme.bodyLarge?.color,
                                    ),
                                  ),
                                  if (_attendees.isNotEmpty)
                                    TextButton(
                                      onPressed: () {
                                        // Navigate to full list
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => _StudentListScreen(
                                              courseCode: widget.courseCode,
                                              attendees: _attendees,
                                            ),
                                          ),
                                        );
                                      },
                                      child: const Text('View All'),
                                    ),
                                ],
                              ),

                              const SizedBox(height: 12),

                              // Students List
                              _attendees.isEmpty
                                  ? Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(32),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).cardColor,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Column(
                                        children: const [
                                          Icon(
                                            Icons.people_outline,
                                            size: 64,
                                            color: AppColors.grey,
                                          ),
                                          SizedBox(height: 12),
                                          Text(
                                            'No students have joined yet',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: AppColors.grey,
                                            ),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            'Waiting for students to scan...',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: AppColors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : ListView.builder(
                                      physics: const NeverScrollableScrollPhysics(),
                                      shrinkWrap: true,
                                      itemCount: _attendees.take(3).length,
                                      itemBuilder: (context, index) {
                                        final a = _attendees[index];
                                        final initials = _getInitials(a.studentName);
                                        final color = _getColorForIndex(index);
                                        // Use cached matric number for instant display
                                        final matricNumber = _matricCache[a.studentId];

                                            return Container(
                                              margin: const EdgeInsets.only(bottom: 12),
                                              padding: const EdgeInsets.all(16),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context).cardColor,
                                                borderRadius: BorderRadius.circular(16),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: AppColors.black.withOpacity(0.03),
                                                    blurRadius: 8,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: Row(
                                                children: [
                                                  // Avatar
                                                  Container(
                                                    width: 50,
                                                    height: 50,
                                                    decoration: BoxDecoration(
                                                      color: color.withOpacity(0.1),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: Center(
                                                      child: Text(
                                                        initials,
                                                        style: TextStyle(
                                                          color: color,
                                                          fontSize: 18,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  // Student Info
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          a.studentName.isNotEmpty 
                                                              ? a.studentName 
                                                              : 'Student ${index + 1}',
                                                          style: TextStyle(
                                                            fontSize: 16,
                                                            fontWeight: FontWeight.w600,
                                                            color: Theme.of(context).textTheme.bodyLarge?.color,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          matricNumber ?? 'Matric N/A',
                                                          style: const TextStyle(
                                                            fontSize: 14,
                                                            color: AppColors.grey,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  // Timestamp
                                                  Text(
                                                    _formatTime(a.timestamp),
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      color: AppColors.grey,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                            ],
                          ),
                        ),
                      ),

                      // End Session Button
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await _endSessionAndSync();
                            },
                            icon: const Icon(Icons.stop_circle, color: AppColors.white),
                            label: const Text(
                              'End Session',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD32F2F),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Future<void> _endSessionAndSync() async {
    print('🔴 Starting _endSessionAndSync()');
    
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Syncing attendance to server...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final db = DatabaseProvider.of(context);
      
      // Check if we have any attendees (QR code was actually used)
      if (_attendees.isEmpty && _sessionLocalId != null) {
        print('⚠️  Session has no attendees - deleting empty session');
        // Delete session if no one attended (QR code was never scanned)
        await db.deleteSession(_sessionLocalId!);
        print('✅ Empty session deleted');
      } else if (_sessionLocalId != null) {
        // End the session in database
        await db.updateSessionStatus(_sessionLocalId!, 'completed', DateTime.now());
        print('✅ Session ended with ID: $_sessionLocalId, attendees: ${_attendees.length}');
        
        // Sync to backend
        print('🔄 Calling _syncSessionToBackend()...');
        await _syncSessionToBackend();
        print('✅ _syncSessionToBackend() completed');
      }

      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog
      Navigator.of(context).pop(); // Go back to dashboard
      
      if (_attendees.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Session ended and synced successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ℹ️  Session was empty and has been discarded'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      print('❌ Error ending session: $e');
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog
      Navigator.of(context).pop(); // Go back to dashboard anyway
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Session ended. Sync failed: $e'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  /// Create session on server and return the server session ID
  Future<String> _createSessionOnServer() async {
    print('🟦 _createSessionOnServer() started');
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final idToken = await user.getIdToken();
    if (idToken == null) {
      throw Exception('Failed to get auth token');
    }

    const overrideUrl = String.fromEnvironment('BACKEND_URL');
    final baseUrl = overrideUrl.isNotEmpty ? overrideUrl : 'https://att-back-0xvj.onrender.com';
    final db = DatabaseProvider.of(context);

    // Get course details
    final course = await db.getCourseById(widget.courseLocalId);
    if (course == null) {
      throw Exception('Course not found');
    }

    print('📚 Course found: ${course.code} (local ID: ${course.id}, server ID: ${course.serverId})');

    // Resolve courseServerId
    int? courseServerId;
    if (course.serverId != null && course.serverId!.isNotEmpty) {
      courseServerId = int.tryParse(course.serverId!);
      print('✅ Using course server ID: $courseServerId');
    } else {
      print('⚠️  No server ID on local course, fetching from backend...');
      // Fetch from server
      final courseResponse = await http.get(
        Uri.parse('$baseUrl/courses/my-courses'),
        headers: {'Authorization': 'Bearer $idToken'},
      ).timeout(const Duration(seconds: 10));
      
      print('📡 Courses endpoint returned: ${courseResponse.statusCode}');
      
      if (courseResponse.statusCode == 200) {
        final decoded = jsonDecode(courseResponse.body);
        print('   Response: $decoded');
        final coursesList = (decoded is List) ? decoded : (decoded is Map && decoded['data'] is List) ? decoded['data'] : [];
        
        for (final c in coursesList) {
          if (c is Map) {
            final backendCode = c['code'] ?? c['course_code'];
            print('   Checking course: $backendCode against ${course.code}');
            if (backendCode == course.code) {
              courseServerId = c['id'] as int?;
              print('   ✅ Found matching course with server ID: $courseServerId');
              break;
            }
          }
        }
      }
    }

    if (courseServerId == null) {
      throw Exception('Course not found on server');
    }

    // Create session on server
    final sessionPayload = {
      'course_id': courseServerId,
      'session_type': 'lecture',
      'start_time': DateTime.now().toIso8601String(),
      'location': 'Lecture Hall',
      'status': 'active',
    };

    print('📤 Creating session on server with payload: $sessionPayload');

    final sessionResponse = await http.post(
      Uri.parse('$baseUrl/sessions/create'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(sessionPayload),
    ).timeout(const Duration(seconds: 30));

    print('📡 Session creation response: ${sessionResponse.statusCode}');
    print('   Body: ${sessionResponse.body}');

    if (sessionResponse.statusCode != 200 && sessionResponse.statusCode != 201) {
      throw Exception('Session creation failed: ${sessionResponse.statusCode} - ${sessionResponse.body}');
    }

    final sessionData = jsonDecode(sessionResponse.body);
    print('   Decoded: $sessionData');
    
    final serverSessionId = sessionData['id'] ?? sessionData['session_id'];
    
    if (serverSessionId == null) {
      print('❌ No session ID in response: $sessionData');
      throw Exception('No session ID in response');
    }

    print('✅ Server session created with ID: $serverSessionId');
    return serverSessionId.toString();
  }

  Future<void> _syncSessionToBackend() async {
    print('🟦 _syncSessionToBackend() started');
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('❌ User not authenticated');
        throw Exception('User not authenticated');
      }

      final idToken = await user.getIdToken();
      if (idToken == null) {
        print('❌ Failed to get auth token');
        throw Exception('Failed to get auth token');
      }

      const overrideUrl = String.fromEnvironment('BACKEND_URL');
      final baseUrl = overrideUrl.isNotEmpty ? overrideUrl : 'https://att-back-0xvj.onrender.com';

      final db = DatabaseProvider.of(context);
      
      if (_sessionLocalId == null) {
        print('❌ _sessionLocalId is null');
        throw Exception('Session ID is null');
      }

      // Get session details
      final session = await db.getSessionById(_sessionLocalId!);
      if (session == null) {
        print('❌ Session not found in database');
        throw Exception('Session not found');
      }
      print('📋 Found session: id=${session.id}, courseId=${session.courseId}, type=${session.sessionType}');

      final course = await db.getCourseById(session.courseId);
      if (course == null) {
        print('❌ Course not found in database');
        throw Exception('Course not found');
      }
      print('📚 Found course: id=${course.id}, code=${course.code}, serverId=${course.serverId}');

      // Resolve course.serverId if missing
      int? courseServerId;
      if (course.serverId != null && course.serverId!.isNotEmpty) {
        courseServerId = int.tryParse(course.serverId!);
        print('✅ Using cached serverId: $courseServerId');
      } else {
        print('🔍 Fetching course serverId from backend...');
        try {
          final courseResponse = await http.get(
            Uri.parse('$baseUrl/courses/my-courses'),
            headers: {'Authorization': 'Bearer $idToken'},
          ).timeout(const Duration(seconds: 10));
          
          print('📡 Course list response: ${courseResponse.statusCode}');
          if (courseResponse.statusCode == 200) {
            final decoded = jsonDecode(courseResponse.body);
            print('📦 Decoded response: $decoded');
            
            final coursesList = (decoded is List) ? decoded : (decoded is Map && decoded['data'] is List) ? decoded['data'] : [];
            print('📋 Found ${coursesList.length} courses on backend');
            
            for (final c in coursesList) {
              if (c is Map) {
                final backendCode = c['code'] ?? c['course_code'];
                print('   Checking: backend=$backendCode vs local=${course.code}');
                if (backendCode == course.code) {
                  courseServerId = c['id'] as int?;
                  print('✅ Matched! serverId=$courseServerId');
                  break;
                }
              }
            }
          }
        } catch (e) {
          print('⚠️ Error fetching courses: $e');
        }
      }

      if (courseServerId == null) {
        print('❌ Could not resolve courseServerId');
        throw Exception('Course serverId not found. Create course on backend first.');
      }

      // Get attendance records
      final attendanceRecords = await db.getAttendanceBySessionId(_sessionLocalId!);
      print('👥 Found ${attendanceRecords.length} attendance records');

      // Check if session already has a serverId (created during QR code generation)
      String serverSessionId;
      if (session.serverId != null && session.serverId!.isNotEmpty) {
        serverSessionId = session.serverId!;
        print('✅ Session already has serverId: $serverSessionId (skipping creation)');
        
        // Update session status to completed on server
        try {
          await http.patch(
            Uri.parse('$baseUrl/sessions/$serverSessionId'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'end_time': session.endTime?.toIso8601String() ?? DateTime.now().toIso8601String(),
              'status': 'completed',
            }),
          ).timeout(const Duration(seconds: 10));
          print('✅ Updated session status to completed');
        } catch (e) {
          print('⚠️ Could not update session status: $e');
        }
      } else {
        // Create session on backend (fallback for offline sessions)
        print('📤 POSTing session to /sessions/create...');
        final sessionPayload = {
          'course_id': courseServerId,
          'session_type': session.sessionType,
          'start_time': session.startTime.toIso8601String(),
          'end_time': session.endTime?.toIso8601String() ?? DateTime.now().toIso8601String(),
          'location': session.location ?? 'Lecture Hall',
          'status': 'completed',
        };
        print('📦 Payload: $sessionPayload');

        final sessionResponse = await http.post(
          Uri.parse('$baseUrl/sessions/create'),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(sessionPayload),
        ).timeout(const Duration(seconds: 30));

        print('🔄 Session response status: ${sessionResponse.statusCode}');
        print('📄 Session response body: ${sessionResponse.body}');

        if (sessionResponse.statusCode != 200 && sessionResponse.statusCode != 201) {
          print('❌ Session sync failed');
          throw Exception('Session creation failed: ${sessionResponse.statusCode}');
        }

        final sessionData = jsonDecode(sessionResponse.body);
        final tempServerSessionId = sessionData['id'] ?? sessionData['session_id'];
        print('✅ Got serverSessionId: $tempServerSessionId');

        if (tempServerSessionId == null) {
          print('❌ No session ID in response');
          throw Exception('Backend did not return session ID');
        }

        serverSessionId = tempServerSessionId.toString();
        
        // Update local session with server ID
        await db.updateSessionServerId(_sessionLocalId!, serverSessionId);
        print('✅ Updated local session ${_sessionLocalId!} with serverId: $serverSessionId');
      }

      // Sync attendance records
      print('👥 Syncing ${attendanceRecords.length} attendance records...');
      for (final record in attendanceRecords) {
        try {
          final student = await db.getUserById(record.studentId);
          if (student == null) {
            print('   ⚠️ Student not found for record ${record.id}');
            continue;
          }

          final payload = {
            'session_id': serverSessionId,
            'student_firebase_uid': student.firebaseUid,
            'status': record.status,
            'timestamp': record.markedAt.toIso8601String(),
            'verified': record.faceVerified,
          };

          print('   📤 Syncing attendance for ${student.name}...');
          final attendanceResponse = await http.post(
            Uri.parse('$baseUrl/attendance/mark'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          ).timeout(const Duration(seconds: 10));

          print('   🔄 Response: ${attendanceResponse.statusCode}');
          if (attendanceResponse.statusCode == 200 || attendanceResponse.statusCode == 201) {
            // ✅ FIX: Update attendance with server ID
            try {
              final attendanceData = jsonDecode(attendanceResponse.body);
              final serverAttendanceId = attendanceData['attendance_id']?.toString() ?? attendanceData['id']?.toString();
              if (serverAttendanceId != null) {
                await db.updateAttendanceServerId(record.id, serverAttendanceId);
                print('   ✅ Synced with serverId: $serverAttendanceId');
              } else {
                await db.markAttendanceSynced(record.id);
                print('   ✅ Synced (no serverId in response)');
              }
            } catch (e) {
              await db.markAttendanceSynced(record.id);
              print('   ✅ Synced (could not parse response: $e)');
            }
          } else {
            print('   ❌ Failed: ${attendanceResponse.body}');
          }
        } catch (e) {
          print('   ❌ Error: $e');
        }
      }

      print('✅ _syncSessionToBackend() completed successfully');
    } catch (e) {
      print('❌ _syncSessionToBackend() failed: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _getStudentDetails(List<AttendanceMessage> attendees) async {
    final results = <Map<String, dynamic>>[];

    for (final attendee in attendees) {
      // Use cached matric (populated from attendance message)
      final matric = _matricCache[attendee.studentId];
      
      results.add({
        'matricNumber': matric,
        'studentId': attendee.studentId,
      });
    }

    return results;
  }

  // Removed - no longer needed as we cache from local DB immediately

  Future<String?> _getSessionServerId() async {
    if (_sessionLocalId == null) return null;
    
    try {
      final db = DatabaseProvider.of(context);
      final session = await (db.select(db.sessions)..where((s) => s.id.equals(_sessionLocalId!))).getSingleOrNull();
      return session?.serverId;
    } catch (e) {
      return null;
    }
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length > 1 ? 2 : 1).toUpperCase();
  }

  Color _getColorForIndex(int index) {
    final colors = [
      const Color(0xFF0D47A1),
      const Color(0xFF7B1FA2),
      const Color(0xFF00ACC1),
      const Color(0xFFFF6F00),
      const Color(0xFFD32F2F),
      const Color(0xFF388E3C),
    ];
    return colors[index % colors.length];
  }

  String _formatTime(DateTime dt) {
    return DateFormat('h:mm a').format(dt.toLocal());
  }
}

// Full Student List Screen
class _StudentListScreen extends StatelessWidget {
  final String courseCode;
  final List<AttendanceMessage> attendees;

  const _StudentListScreen({
    required this.courseCode,
    required this.attendees,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Students Joined (${attendees.length})'),
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: AppColors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            color: Theme.of(context).cardColor,
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search name or matric no...',
                prefixIcon: const Icon(Icons.search, color: AppColors.grey),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey.shade800
                    : AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              ),
            ),
          ),

          // Student List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: attendees.length,
              itemBuilder: (context, index) {
                final a = attendees[index];
                final initials = _getInitials(a.studentName);
                final color = _getColorForIndex(index);
                // Use matric from message directly - no database lookup needed
                final matricNumber = a.matricNumber;

                return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.black.withOpacity(0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Avatar
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                initials,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Student Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  a.studentName.isNotEmpty 
                                      ? a.studentName 
                                      : 'Student ${index + 1}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).textTheme.bodyLarge?.color,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  matricNumber ?? 'Matric N/A',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Timestamp
                          Text(
                            DateFormat('h:mm a').format(a.timestamp.toLocal()),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length > 1 ? 2 : 1).toUpperCase();
  }

  Color _getColorForIndex(int index) {
    final colors = [
      const Color(0xFF0D47A1),
      const Color(0xFF7B1FA2),
      const Color(0xFF00ACC1),
      const Color(0xFFFF6F00),
      const Color(0xFFD32F2F),
      const Color(0xFF388E3C),
    ];
    return colors[index % colors.length];
  }
}
