// import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';
// import 'package:qr_flutter/qr_flutter.dart';
// import 'dart:convert';
// import 'dart:async';
// import 'dart:math';
// import '../models/wifi_direct_payload.dart';
// import '../db/database_provider.dart';
// import '../db/database.dart';

// class LecturerSessionDetailScreen extends StatefulWidget {
//   final Session session;
//   final Course course;
//   final WifiDirectPayload? payload;

//   const LecturerSessionDetailScreen({
//     super.key,
//     required this.session,
//     required this.course,
//     this.payload,
//   });

//   @override
//   State<LecturerSessionDetailScreen> createState() =>
//       _LecturerSessionDetailScreenState();
// }

// class _LecturerSessionDetailScreenState
//     extends State<LecturerSessionDetailScreen> {
//   late Future<List<AttendanceWithStudent>> _attendanceFuture;
//   Timer? _refreshTimer;
//   Timer? _countdownTimer;
//   int _countdown = 20;
//   late WifiDirectPayload _currentPayload;

//   @override
//   void initState() {
//     super.initState();
//     _currentPayload = widget.payload ?? _generateNewPayload();
//     _startRefreshTimer();
//   }

//   @override
//   void didChangeDependencies() {
//     super.didChangeDependencies();
//     _loadData();
//   }

//   @override
//   void dispose() {
//     _refreshTimer?.cancel();
//     _countdownTimer?.cancel();
//     super.dispose();
//   }

//   String _generateRandomPassword() {
//     const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
//     final random = Random.secure();
//     return List.generate(8, (index) => chars[random.nextInt(chars.length)]).join();
//   }

//   WifiDirectPayload _generateNewPayload() {
//     final password = _generateRandomPassword();
//     return WifiDirectPayload(
//       sessionId: widget.session.id.toString(),
//       courseCode: widget.course.code,
//       courseName: widget.course.name,
//       ssid: 'DIRECT-${widget.course.code}-${widget.session.id}',
//       psk: password,
//     );
//   }

//   void _startRefreshTimer() {
//     // Countdown timer - updates every second
//     _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
//       if (mounted) {
//         setState(() {
//           if (_countdown > 0) {
//             _countdown--;
//           } else {
//             _countdown = 20;
//           }
//         });
//       }
//     });

//     // Refresh timer - generates new QR code every 20 seconds
//     _refreshTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
//       if (mounted) {
//         setState(() {
//           _currentPayload = _generateNewPayload();
//           _countdown = 20;
//         });
//       }
//     });
//   }

//   void _loadData() {
//     final db = DatabaseProvider.of(context);
//     _attendanceFuture = db.getAttendanceWithStudentForSession(widget.session.id);
//   }

//   @override
//   Widget build(BuildContext context) {
//     return PopScope(
//       canPop: false, // Prevent back button
//       child: Scaffold(
//         backgroundColor: const Color(0xFFF5F5F5),
//         appBar: AppBar(
//           backgroundColor: const Color(0xFF0D47A1),
//           elevation: 0,
//           automaticallyImplyLeading: false, // Remove back button
//           title: Text(
//             widget.course.code,
//             style: const TextStyle(
//               color: Colors.white,
//               fontSize: 20,
//               fontWeight: FontWeight.bold,
//             ),
//           ),
//           actions: [
//             if (widget.session.status == 'active')
//               Padding(
//                 padding: const EdgeInsets.all(16),
//                 child: Center(
//                   child: Container(
//                     padding: const EdgeInsets.symmetric(
//                       horizontal: 12,
//                       vertical: 6,
//                     ),
//                     decoration: BoxDecoration(
//                       color: Colors.red,
//                       borderRadius: BorderRadius.circular(20),
//                     ),
//                     child: const Row(
//                       mainAxisSize: MainAxisSize.min,
//                       children: [
//                         Icon(Icons.circle, size: 8, color: Colors.white),
//                         SizedBox(width: 6),
//                         Text(
//                           'LIVE',
//                           style: TextStyle(
//                             color: Colors.white,
//                             fontSize: 12,
//                             fontWeight: FontWeight.bold,
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ),
//               ),
//           // ],
//         ),
//         body: SafeArea(
//           child: SingleChildScrollView(
//           padding: const EdgeInsets.all(20),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               // Course Info
//               Text(
//                 widget.course.code,
//                 style: const TextStyle(
//                   fontSize: 28,
//                   fontWeight: FontWeight.bold,
//                   color: Colors.black,
//                 ),
//               ),
//               const SizedBox(height: 4),
//               Text(
//                 DateFormat('MMM dd, yyyy').format(widget.session.startTime),
//                 style: const TextStyle(
//                   fontSize: 16,
//                   color: Colors.grey,
//                 ),
//               ),
//               const SizedBox(height: 24),

//               // QR Code Card
//               Container(
//                 width: double.infinity,
//                 padding: const EdgeInsets.all(24),
//                 decoration: BoxDecoration(
//                   color: Colors.white,
//                   borderRadius: BorderRadius.circular(20),
//                   boxShadow: [
//                     BoxShadow(
//                       color: Colors.black.withOpacity(0.05),
//                       blurRadius: 10,
//                       offset: const Offset(0, 4),
//                     ),
//                   ],
//                 ),
//                 child: Column(
//                   children: [
//                     // QR Code
//                     Container(
//                       padding: const EdgeInsets.all(16),
//                       decoration: BoxDecoration(
//                         color: const Color(0xFFF5F5F5),
//                         borderRadius: BorderRadius.circular(16),
//                         border: Border.all(
//                           color: Colors.grey.withOpacity(0.2),
//                           width: 2,
//                           strokeAlign: BorderSide.strokeAlignOutside,
//                         ),
//                       ),
//                       child: QrImageView(
//                         data: jsonEncode(_currentPayload.toJson()),
//                         version: QrVersions.auto,
//                         size: 200.0,
//                         backgroundColor: const Color(0xFFFFFFFF),
//                         errorCorrectionLevel: QrErrorCorrectLevel.H,
//                       ),
//                     ),
//                       const SizedBox(height: 16),
//                       const Text(
//                         'Scan to mark attendance',
//                         style: TextStyle(
//                           fontSize: 16,
//                           fontWeight: FontWeight.w600,
//                           color: Colors.black,
//                         ),
//                       ),
//                       const SizedBox(height: 8),
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.center,
//                         children: [
//                           const Icon(
//                             Icons.access_time,
//                             size: 16,
//                             color: Colors.grey,
//                           ),
//                           const SizedBox(width: 6),
//                           Text(
//                             'Code refreshes in ${_countdown}s',
//                             style: const TextStyle(
//                               fontSize: 14,
//                               color: Colors.grey,
//                             ),
//                           ),
//                         ],
//                       ),
//                   ],
//                 ),
//               ),

//               const SizedBox(height: 32),

//               // Students Joined Section
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   FutureBuilder<List<AttendanceWithStudent>>(
//                     future: _attendanceFuture,
//                     builder: (context, snapshot) {
//                       final count = snapshot.data?.length ?? 0;
//                       return Text(
//                         'Students Joined ($count)',
//                         style: const TextStyle(
//                           fontSize: 18,
//                           fontWeight: FontWeight.bold,
//                           color: Colors.black,
//                         ),
//                       );
//                     },
//                   ),
//                   FutureBuilder<List<AttendanceWithStudent>>(
//                     future: _attendanceFuture,
//                     builder: (context, snapshot) {
//                       if (!snapshot.hasData) {
//                         return const SizedBox.shrink();
//                       }
//                       return TextButton(
//                         onPressed: null, // Disabled for now
//                         child: const Text(
//                           'View All',
//                           style: TextStyle(
//                             color: Color(0xFF0D47A1),
//                             fontWeight: FontWeight.w600,
//                           ),
//                         ),
//                       );
//                     },
//                   ),
//                 ],
//               ),

//               const SizedBox(height: 16),

//               // Students List
//               FutureBuilder<List<AttendanceWithStudent>>(
//                 future: _attendanceFuture,
//                 builder: (context, snapshot) {
//                   if (snapshot.connectionState == ConnectionState.waiting) {
//                     return const Center(child: CircularProgressIndicator());
//                   }

//                   if (!snapshot.hasData || snapshot.data!.isEmpty) {
//                     return Container(
//                       padding: const EdgeInsets.all(24),
//                       decoration: BoxDecoration(
//                         color: Colors.white,
//                         borderRadius: BorderRadius.circular(16),
//                       ),
//                       child: const Center(
//                         child: Text(
//                           'No students joined yet',
//                           style: TextStyle(
//                             color: Colors.grey,
//                             fontSize: 14,
//                           ),
//                         ),
//                       ),
//                     );
//                   }

//                   final attendance = snapshot.data!;
//                   // Show only first 5
//                   final displayed = attendance.take(5).toList();

//                   return Column(
//                     children: [
//                       ...displayed.asMap().entries.map((entry) {
//                         final record = entry.value;
//                         final student = record.student;
//                         final initials = student.name
//                             .split(' ')
//                             .map((n) => n.isNotEmpty ? n[0] : '')
//                             .join()
//                             .toUpperCase()
//                             .substring(0, 2.clamp(0, 2));

//                         return Container(
//                           margin: const EdgeInsets.only(bottom: 12),
//                           padding: const EdgeInsets.all(16),
//                           decoration: BoxDecoration(
//                             color: Colors.white,
//                             borderRadius: BorderRadius.circular(12),
//                             boxShadow: [
//                               BoxShadow(
//                                 color: Colors.black.withOpacity(0.03),
//                                 blurRadius: 4,
//                                 offset: const Offset(0, 2),
//                               ),
//                             ],
//                           ),
//                           child: Row(
//                             children: [
//                               Container(
//                                 width: 48,
//                                 height: 48,
//                                 decoration: BoxDecoration(
//                                   color: _getColorForInitials(initials),
//                                   borderRadius: BorderRadius.circular(12),
//                                 ),
//                                 child: Center(
//                                   child: Text(
//                                     initials,
//                                     style: const TextStyle(
//                                       color: Colors.white,
//                                       fontWeight: FontWeight.bold,
//                                       fontSize: 14,
//                                     ),
//                                   ),
//                                 ),
//                               ),
//                               const SizedBox(width: 12),
//                               Expanded(
//                                 child: Column(
//                                   crossAxisAlignment: CrossAxisAlignment.start,
//                                   children: [
//                                     Text(
//                                       student.externalId ?? 'N/A',
//                                       style: const TextStyle(
//                                         fontSize: 14,
//                                         fontWeight: FontWeight.bold,
//                                         color: Colors.black,
//                                       ),
//                                     ),
//                                     const SizedBox(height: 2),
//                                     Text(
//                                       student.department ?? 'N/A',
//                                       style: const TextStyle(
//                                         fontSize: 12,
//                                         color: Colors.grey,
//                                       ),
//                                     ),
//                                   ],
//                                 ),
//                               ),
//                               Container(
//                                 padding: const EdgeInsets.all(8),
//                                 decoration: BoxDecoration(
//                                   color: const Color(0xFF4CAF50).withOpacity(0.1),
//                                   borderRadius: BorderRadius.circular(8),
//                                 ),
//                                 child: const Icon(
//                                   Icons.check,
//                                   color: Color(0xFF4CAF50),
//                                   size: 20,
//                                 ),
//                               ),
//                             ],
//                           ),
//                         );
//                       }),
//                       if (attendance.length > 5)
//                         Container(
//                           padding: const EdgeInsets.all(12),
//                           decoration: BoxDecoration(
//                             color: Colors.white,
//                             borderRadius: BorderRadius.circular(12),
//                           ),
//                           child: Text(
//                             '+${attendance.length - 5} more students',
//                             style: const TextStyle(
//                               color: Color(0xFF0D47A1),
//                               fontWeight: FontWeight.w600,
//                             ),
//                           ),
//                         ),
//                     ],
//                   );
//                 },
//               ),
//             ],
//           ),
//         ),
//         ),
//       ),
//     ); // End of PopScope
//   }

//   Color _getColorForInitials(String initials) {
//     final colors = [
//       const Color(0xFF0D47A1),
//       const Color(0xFFE53935),
//       const Color(0xFF7B1FA2),
//       const Color(0xFF00796B),
//       const Color(0xFF5E35B1),
//       const Color(0xFFF57C00),
//     ];
//     return colors[initials.hashCode % colors.length];
//   }
// }
