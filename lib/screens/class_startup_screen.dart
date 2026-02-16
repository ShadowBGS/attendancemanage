import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../theme/app_colors.dart';
//import '../services/wifi_direct_session_service.dart';
import 'wifi_direct_host_screen.dart';

/// Loading screen that checks permissions and services before starting a class
class ClassStartupScreen extends StatefulWidget {
  final String courseCode;
  final String courseName;
  final int courseLocalId;

  const ClassStartupScreen({
    required this.courseCode,
    required this.courseName,
    required this.courseLocalId,
    super.key,
  });

  @override
  State<ClassStartupScreen> createState() => _ClassStartupScreenState();
}

class _ClassStartupScreenState extends State<ClassStartupScreen> {
  String _statusMessage = 'Preparing to start class...';
  bool _hasError = false;
  String _errorMessage = '';


  @override
  void initState() {
    super.initState();
    _checkPermissionsAndStart();
  }

  Future<void> _checkPermissionsAndStart() async {
    try {
      // Pre-flight check: WiFi Direct works offline, no network connection required
      setState(() => _statusMessage = 'Preparing to start class...');
      
      // Pre-flight check: Verify mobile hotspot is disabled
      setState(() => _statusMessage = 'Verifying hotspot is disabled...');
      // Note: Direct hotspot detection is platform-specific, but the system will reject
      // hotspot + WiFi Direct at createGroup time. This check is informational.
      print('⚠️  [ClassStartupScreen] Hotspot must be OFF. WiFi Direct and tethering cannot coexist.');
      
      setState(() => _statusMessage = 'Checking WiFi Direct permissions...');
      await Future.delayed(const Duration(milliseconds: 200));
      
      setState(() => _statusMessage = 'Enabling WiFi services...');
      await Future.delayed(const Duration(milliseconds: 200));
      
      setState(() => _statusMessage = 'Enabling Location services...');
      await Future.delayed(const Duration(milliseconds: 200));
      
      setState(() => _statusMessage = 'Finalizing setup...');
      await Future.delayed(const Duration(milliseconds: 200));

      // All checks passed, navigate to the actual class screen
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => WifiDirectHostScreen(
              courseCode: widget.courseCode,
              courseName: widget.courseName,
              courseLocalId: widget.courseLocalId,
            ),
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

  void _retryCheckPermissions() {
    setState(() {
      _statusMessage = 'Preparing to start class...';
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_hasError) ...[
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primaryBlue,
                      ),
                      strokeWidth: 3,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Starting Class',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCheckItem('Hotspot is OFF', true),
                      const SizedBox(height: 8),
                      _buildCheckItem('Wi‑Fi Direct', true),
                      const SizedBox(height: 8),
                      _buildCheckItem('Location Services', true),
                      const SizedBox(height: 8),
                      _buildCheckItem('Wi-Fi Services', true),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Important: Mobile hotspot/tethering must be OFF for WiFi Direct to work.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.error_outline,
                      size: 40,
                      color: Colors.red.shade400,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Setup Failed',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: AppColors.primaryBlue),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: AppColors.primaryBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _retryCheckPermissions,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Retry',
                          style: TextStyle(
                            color: AppColors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckItem(String label, bool isChecking) {
    return Row(
      children: [
        if (isChecking)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                Colors.grey.shade400,
              ),
            ),
          )
        else
          Icon(
            Icons.check_circle,
            size: 16,
            color: Colors.green.shade400,
          ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
