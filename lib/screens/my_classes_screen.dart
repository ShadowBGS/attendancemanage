import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../db/database_provider.dart';
import '../db/database.dart';
import '../theme/app_colors.dart';
import 'student_course_detail_screen.dart';

class MyClassesScreen extends StatefulWidget {
  const MyClassesScreen({super.key});

  @override
  State<MyClassesScreen> createState() => _MyClassesScreenState();
}

class _MyClassesScreenState extends State<MyClassesScreen> {
  List<Course> _allClasses = [];
  List<Course> _filteredClasses = [];
  final TextEditingController _searchController = TextEditingController();
  int _currentNavIndex = 1; // Classes tab selected
  bool _didLoadInitialData = false;
  bool _isInitialLoadDone = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterClassesDebounced);
  }

  void _filterClassesDebounced() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), _filterClasses);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoadInitialData) {
      _didLoadInitialData = true;
      _performInitialLoad();
    }
  }

  Future<void> _performInitialLoad() async {
    await _loadClasses();
    if (mounted) {
      setState(() => _isInitialLoadDone = true);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final db = DatabaseProvider.of(context);
      final cachedUser = await db.getUserByFirebaseUid(user.uid);
      if (cachedUser == null) return;

      final classes = await db.getCoursesForStudent(cachedUser.id);
      if (mounted) {
        setState(() {
          _allClasses = classes;
          _filteredClasses = classes;
        });
      }
    } catch (_) {
      // Handle error
    }
  }

  void _filterClasses() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredClasses = _allClasses;
      } else {
        _filteredClasses = _allClasses.where((course) {
          return course.code.toLowerCase().contains(query) ||
                 course.name.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show loading screen until initial data is loaded
    if (!_isInitialLoadDone) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
          ),
        ),
      );
    }
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Blue Header
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 20, 24),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.arrow_back, color: Theme.of(context).cardColor),
                      ),
                      Expanded(
                        child: Text(
                          'My Courses',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).cardColor,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48), // Balance the back button
                    ],
                  ),
                ),
              ),
            ),
            
            // Search Bar
            Padding(
              padding: const EdgeInsets.all(20),
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
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name or code...',
                    hintStyle: TextStyle(color: Theme.of(context).hintColor),
                    prefixIcon: Icon(Icons.search, color: Theme.of(context).hintColor),
                    suffixIcon: Icon(Icons.tune, color: Theme.of(context).hintColor),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                ),
              ),
            ),

            // Classes List
            Expanded(
              child: _filteredClasses.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.school_outlined,
                            size: 64,
                            color: Theme.of(context).hintColor.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchController.text.isEmpty
                                ? 'No courses enrolled yet'
                                : 'No results for "${_searchController.text}"',
                            style: TextStyle(
                              color: Theme.of(context).textTheme.bodyMedium?.color,
                              fontSize: 16,
                            ),
                          ),
                          if (_searchController.text.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: ElevatedButton(
                                onPressed: _loadClasses,
                                child: const Text('Refresh'),
                              ),
                            ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadClasses,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        cacheExtent: 1000,
                        itemCount: _filteredClasses.length,
                        itemBuilder: (context, index) {
                          final course = _filteredClasses[index];
                          return _ClassCard(
                            course: course,
                            index: index,
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  final Course course;
  final int index;

  const _ClassCard({
    required this.course,
    required this.index,
  });

  IconData _getIconForCourse() {
    final codeLower = course.code.toLowerCase();
    if (codeLower.contains('cs') || codeLower.contains('csc') || codeLower.contains('cpe')) {
      return Icons.computer;
    } else if (codeLower.contains('mth') || codeLower.contains('mat')) {
      return Icons.functions;
    } else if (codeLower.contains('phy') || codeLower.contains('phys')) {
      return Icons.flash_on;
    } else if (codeLower.contains('chm') || codeLower.contains('chem')) {
      return Icons.science;
    } else if (codeLower.contains('his') || codeLower.contains('hist')) {
      return Icons.menu_book;
    } else if (codeLower.contains('art')) {
      return Icons.palette;
    } else if (codeLower.contains('eng') || codeLower.contains('engl')) {
      return Icons.book;
    } else if (codeLower.contains('bio')) {
      return Icons.biotech;
    }
    return Icons.school;
  }

  Color _getColorForIndex() {
    final colors = [
      const Color(0xFFE3F2FD), // Light blue
      const Color(0xFFE0F2F1), // Light teal
      const Color(0xFFFFF3E0), // Light orange
      const Color(0xFFFCE4EC), // Light pink
      const Color(0xFFFFF9C4), // Light yellow
      const Color(0xFFF3E5F5), // Light purple
    ];
    return colors[index % colors.length];
  }

  Color _getIconColorForIndex() {
    final colors = [
      const Color(0xFF1976D2), // Blue
      const Color(0xFF00897B), // Teal
      const Color(0xFFF57C00), // Orange
      const Color(0xFFD81B60), // Pink
      const Color(0xFFF9A825), // Yellow
      const Color(0xFF8E24AA), // Purple
    ];
    return colors[index % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => StudentCourseDetailScreen(course: course),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _getColorForIndex(),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    _getIconForCourse(),
                    color: _getIconColorForIndex(),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.code,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _getIconColorForIndex(),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        course.name,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF0D47A1) : Colors.grey,
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? const Color(0xFF0D47A1) : Colors.grey,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterQRButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CenterQRButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFF0D47A1),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0D47A1).withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.qr_code_scanner,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }
}
