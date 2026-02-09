import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_colors.dart';
import 'wifi_direct_scan_screen.dart';

/// Loading screen that checks permissions and services before starting QR scan
class StudentScanStartupScreen extends StatefulWidget {
  const StudentScanStartupScreen({super.key});

  @override
  State<StudentScanStartupScreen> createState() => _StudentScanStartupScreenState();
}

class _StudentScanStartupScreenState extends State<StudentScanStartupScreen> {
  String _statusMessage = 'Preparing to scan QR code...';
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndStart();
  }

  Future<void> _checkPermissionsAndStart() async {
    try {
      // Check Camera permissions
      setState(() => _statusMessage = 'Checking camera permissions...');
      await _ensurePermissionsForScanning();

      // All checks passed, navigate to the actual scan screen
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const WifiDirectScanScreen(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _ensurePermissionsForScanning() async {
    try {
      setState(() => _statusMessage = 'Requesting camera permissions...');
      final cameraStatus = await Permission.camera.request();
      
      if (cameraStatus.isDenied) {
        throw Exception('Camera permission is required to scan QR codes');
      } else if (cameraStatus.isPermanentlyDenied) {
        throw Exception('Camera permission is permanently denied. Please enable it in app settings.');
      }

      setState(() => _statusMessage = 'Checking Wi-Fi Direct connection...');
      await Future.delayed(const Duration(milliseconds: 500));

      setState(() => _statusMessage = 'All permissions granted! Ready to scan.');
      await Future.delayed(const Duration(milliseconds: 500));
    } on Exception catch (e) {
      throw e.toString();
    }
  }

  void _retryCheckPermissions() {
    setState(() {
      _statusMessage = 'Preparing to scan QR code...';
      _hasError = false;
      _errorMessage = '';
    });
    _checkPermissionsAndStart();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryBlue.withOpacity(0.1),
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner,
                    size: 60,
                    color: AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(height: 32),

                // Title
                Text(
                  _hasError ? 'Permission Issue' : 'Preparing Scanner',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),

                // Status or Error Message
                Text(
                  _hasError ? _errorMessage : _statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: _hasError ? Colors.red : Colors.grey,
                  ),
                ),
                const SizedBox(height: 32),

                // Loading indicator or error details
                if (!_hasError)
                  Column(
                    children: [
                      const CircularProgressIndicator(
                        color: AppColors.primaryBlue,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'This may take a moment...',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      // Error icon
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 48,
                        color: Colors.red[400],
                      ),
                      const SizedBox(height: 24),

                      // Retry button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _retryCheckPermissions,
                          icon: const Icon(Icons.refresh, color: Colors.white),
                          label: const Text(
                            'Retry',
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
                      const SizedBox(height: 12),

                      // Back button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'Go Back',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
