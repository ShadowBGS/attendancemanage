import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'student_dashboard.dart';
import 'my_classes_screen.dart';
import 'profile_screen.dart';

class StudentMainWrapper extends StatefulWidget {
  const StudentMainWrapper({super.key});

  @override
  State<StudentMainWrapper> createState() => _StudentMainWrapperState();
}

class _StudentMainWrapperState extends State<StudentMainWrapper> {
  int _currentIndex = 0;
  
  // GlobalKeys to preserve navigation state for each tab
  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(), // Home
    GlobalKey<NavigatorState>(), // Classes
    GlobalKey<NavigatorState>(), // Alerts
    GlobalKey<NavigatorState>(), // Profile
  ];

  // Build a Navigator for each tab to allow independent navigation
  Widget _buildNavigator(int index) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (RouteSettings settings) {
        return MaterialPageRoute(
          settings: settings,
          builder: (BuildContext context) {
            switch (index) {
              case 0:
                return const StudentDashboard();
              case 1:
                return const MyClassesScreen();
              case 2:
                // Placeholder for Alerts screen
                return const Center(
                  child: Text(
                    'Alerts Screen',
                    style: TextStyle(fontSize: 24),
                  ),
                );
              case 3:
                return const ProfileScreen();
              default:
                return const StudentDashboard();
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // We always handle the back button ourselves
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        
        // Try to pop the current tab's navigator first
        final NavigatorState? navigator = _navigatorKeys[_currentIndex].currentState;
        if (navigator != null && navigator.canPop()) {
          // If the current tab has pages in its stack, pop one
          navigator.pop();
        } else if (_currentIndex != 0) {
          // If we can't pop and we're not on Home, go to Home
          setState(() {
            _currentIndex = 0;
          });
        } else {
          // If we're on Home tab with no sub-pages, allow exit
          // This will close the app or go back to previous screen
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _buildNavigator(0), // Home
            _buildNavigator(1), // Classes
            _buildNavigator(2), // Alerts
            _buildNavigator(3), // Profile
          ],
        ),
      ),
    );
  }
}
