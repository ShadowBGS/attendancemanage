import 'package:flutter/material.dart';
import '../db/database_provider.dart';
import '../db/database.dart';
import '../theme/app_colors.dart';
import 'course_detail_screen.dart';
import 'lecturer_profile_screen.dart';

class LecturerCoursesScreen extends StatefulWidget {
  const LecturerCoursesScreen({super.key});

  @override
  State<LecturerCoursesScreen> createState() => _LecturerCoursesScreenState();
}

class _LecturerCoursesScreenState extends State<LecturerCoursesScreen> {
  static const Color _primaryBlue = Color(0xFF0D47A1);
  List<Course> _allCourses = [];
  List<Course> _filteredCourses = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  bool _hasLoaded = false;
  bool _isInitialLoadDone = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterCourses);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasLoaded) {
      _hasLoaded = true;
      _loadCourses();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCourses() async {
    try {
      final db = DatabaseProvider.of(context);
      final courses = await db.getAllCourses();
      
      // Deduplicate courses by ID to prevent UI duplication
      final seen = <int>{};
      final uniqueCourses = courses.where((course) {
        if (seen.contains(course.id)) return false;
        seen.add(course.id);
        return true;
      }).toList();
      
      if (mounted) {
        setState(() {
          _allCourses = uniqueCourses;
          _filteredCourses = uniqueCourses;
          _isLoading = false;
          _isInitialLoadDone = true;
        });
      }
    } catch (e) {
      print('Error loading courses: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isInitialLoadDone = true;
        });
      }
    }
  }

  void _filterCourses() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredCourses = _allCourses;
      } else {
        _filteredCourses = _allCourses.where((course) {
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
                color: _primaryBlue,
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
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      const Expanded(
                        child: Text(
                          'My Courses',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name or code...',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                    suffixIcon: Icon(Icons.tune, color: Colors.grey[400]),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                ),
              ),
            ),

            // Courses List
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadCourses,
                child: _filteredCourses.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                          Center(
                            child: Text(
                              _searchController.text.isEmpty
                                  ? 'No courses found'
                                  : 'No results for "${_searchController.text}"',
                              style: const TextStyle(color: Colors.grey, fontSize: 16),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _filteredCourses.length,
                      itemBuilder: (context, index) {
                        final course = _filteredCourses[index];
                        return _CourseCard(
                          code: course.code,
                          name: course.name,
                          courseLocalId: course.id,
                          courseServerId: course.serverId,
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

class _CourseCard extends StatelessWidget {
  final String code;
  final String name;
  final int courseLocalId;
  final String? courseServerId;
  final int index;

  const _CourseCard({
    required this.code,
    required this.name,
    required this.courseLocalId,
    required this.courseServerId,
    required this.index,
  });

  Color _getIconColor() {
    final colors = [
      const Color(0xFF0D47A1), // Blue
      const Color(0xFF7B1FA2), // Purple
      const Color(0xFFE65100), // Orange
      const Color(0xFF00796B), // Teal
    ];
    return colors[code.hashCode % colors.length];
  }

  Color _getCodeColor() {
    final colors = [
      const Color(0xFF0D47A1), // Blue
      const Color(0xFF7B1FA2), // Purple
      const Color(0xFFE65100), // Orange
      const Color(0xFF00796B), // Teal
    ];
    return colors[code.hashCode % colors.length];
  }

  IconData _getCourseIcon() {
    // final upperCode = code.toUpperCase();
    // if (upperCode.contains('CS') || upperCode.contains('COSC')) {
    //   return Icons.computer;
    // } else if (upperCode.contains('MTH') || upperCode.contains('MATH')) {
    //   return Icons.calculate;
    // } else if (upperCode.contains('PHY')) {
    //   return Icons.bolt;
    // } else if (upperCode.contains('CHM') || upperCode.contains('CHEM')) {
    //   return Icons.science;
    // } else if (upperCode.contains('HIS')) {
    //   return Icons.history_edu;
    // } else if (upperCode.contains('ART')) {
    //   return Icons.palette;
    // }
    return Icons.book;
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = _getIconColor();
    final codeColor = _getCodeColor();

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CourseDetailScreen(
              courseCode: code,
              courseName: name,
              courseLocalId: courseLocalId,
              courseServerId: courseServerId,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getCourseIcon(),
                color: iconColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: codeColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      code,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: codeColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    name,
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.grey[400],
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
