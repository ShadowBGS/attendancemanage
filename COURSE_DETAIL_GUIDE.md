# Course Detail Screen Guide

## ✅ What's Been Implemented

### **Course Detail Screen**
A comprehensive course management interface that displays:

- **Course Header**
  - Large course code display (e.g., CS101)
  - Course name
  - Course ID reference

- **Course Statistics**
  - Enrolled students count
  - Active sessions count
  - Visual stat tiles with icons

- **Quick Actions**
  - View Roster - See all enrolled students
  - Session History - View past attendance sessions
  - Course Settings - Configure course options

- **Start Class Button**
  - Green button at the bottom for starting a new attendance session
  - Loading state during operation
  - Feedback messages on success/error

- **Edit Course**
  - Edit icon in top app bar
  - Allows modifying course details
  - Placeholder for future implementation

---

## 🔄 User Flow

### **From Dashboard to Course Detail**

1. **Lecturer Dashboard** displays list of courses
2. **Tap any course card** (entire card is clickable)
3. **CourseDetailScreen opens** with:
   - Course name and code
   - Key statistics
   - Action options
   - Start Class button

### **Start Class Flow**

1. **Lecturer taps "Start Class"** button
2. **Loading state appears** (spinner in button)
3. **Backend creates a new session** (coming soon)
4. **Success message** shows "Class started successfully!"
5. **Navigate to attendance marking screen** (future)

---

## 📊 Screen Layout

```
┌─────────────────────────────────┐
│ Course Details        [Edit]    │  ← AppBar with edit button
├─────────────────────────────────┤
│                                 │
│  ╔═══════════════════════════╗  │
│  ║      CS101              ║  │  ← Course header with gradient
│  ║  Data Structures        ║  │
│  ║  Course ID: 1           ║  │
│  ╚═══════════════════════════╝  │
│                                 │
│  ┌──────────────┬──────────────┐│
│  │     👥  0    │    📅  0     ││  ← Statistics
│  │ Enrolled     │ Active       ││
│  │ Students     │ Sessions     ││
│  └──────────────┴──────────────┘│
│                                 │
│  Quick Actions                  │
│  ─────────────                  │
│  ┌─────────────────────────────┐│
│  │ 📋 View Roster              ││
│  │   See enrolled students  →  ││
│  └─────────────────────────────┘│
│  ┌─────────────────────────────┐│
│  │ 📜 Session History          ││
│  │   View past sessions     →  ││
│  └─────────────────────────────┘│
│  ┌─────────────────────────────┐│
│  │ ⚙️ Course Settings          ││
│  │   Configure options      →  ││
│  └─────────────────────────────┘│
│                                 │
│  ℹ️ Tap "Start Class" to begin  │
│     an attendance session.      │
│                                 │
├─────────────────────────────────┤
│  ▶️  START CLASS                 │  ← Bottom button
└─────────────────────────────────┘
```

---

## 🧪 Testing

### **Test 1: Navigate to Course Detail**
- [ ] Open Lecturer Dashboard
- [ ] Tap on a course card (anywhere on the card)
- [ ] Course Detail Screen should open
- [ ] Verify course code, name, and ID are displayed

### **Test 2: View Course Information**
- [ ] Check that statistics are visible
- [ ] Verify icons and labels display correctly
- [ ] Check that all action tiles are clickable
- [ ] Tap edit button - should show success message

### **Test 3: Start Class Button**
- [ ] Tap "Start Class" button
- [ ] Loading spinner should appear
- [ ] Wait for success message
- [ ] Success message should say "Class started successfully!"

### **Test 4: Quick Actions**
- [ ] Tap "View Roster" - show success message (future: navigate to roster)
- [ ] Tap "Session History" - show success message (future: navigate to history)
- [ ] Tap "Course Settings" - show success message (future: navigate to edit)

### **Test 5: Navigation**
- [ ] Tap back arrow in app bar - should return to dashboard
- [ ] Verify course list is still there
- [ ] Verify no data loss

---

## 🔐 Features

### **Current Implementation**
- ✅ Course information display
- ✅ Statistics placeholders
- ✅ Quick action tiles
- ✅ Start Class button (placeholder action)
- ✅ Edit button (placeholder)
- ✅ Professional UI with gradients
- ✅ Responsive design

### **Future Enhancements**

1. **Roster Management**
   ```
   View Roster → Lists all enrolled students
   - Show student names
   - Show attendance percentage
   - Option to manually add/remove students
   ```

2. **Session History**
   ```
   Session History → View all past attendance sessions
   - Session date/time
   - Number of attendees
   - Edit session details
   - Download attendance report
   ```

3. **Course Settings**
   ```
   Edit Course → Modify course details
   - Change course name
   - Update description
   - Set attendance policy
   - Configure late penalty
   - Delete course
   ```

4. **Start Class Implementation**
   ```
   When "Start Class" is tapped:
   1. Create session in backend
   2. Generate QR code for attendance
   3. Navigate to attendance marking screen
   4. Show real-time attendance updates
   5. End session when complete
   ```

---

## 🔌 Backend Integration (TODO)

### **Endpoints to Implement**

**1. Get Course Details**
```
GET /courses/{course_id}
Authorization: Bearer {token}

Response:
{
  "course_id": 1,
  "course_code": "CS101",
  "course_name": "Data Structures",
  "description": "...",
  "lecturer_id": 5,
  "enrolled_students": 45,
  "active_sessions": 2,
  "created_at": "2024-01-15"
}
```

**2. Create Attendance Session**
```
POST /sessions/create
Authorization: Bearer {token}
Content-Type: application/json

{
  "course_id": 1,
  "session_type": "lecture",  // lecture|lab|tutorial
  "location": "Room 101",
  "start_time": "2024-01-25T10:00:00Z"
}

Response (201):
{
  "session_id": 42,
  "course_id": 1,
  "qr_code": "...",
  "status": "active"
}
```

**3. Get Course Roster**
```
GET /courses/{course_id}/roster
Authorization: Bearer {token}

Response:
{
  "course_id": 1,
  "students": [
    {
      "student_id": 10,
      "name": "John Doe",
      "matric_no": "2024/CS/001",
      "attendance_rate": 85
    },
    ...
  ]
}
```

**4. Get Session History**
```
GET /courses/{course_id}/sessions
Authorization: Bearer {token}

Response:
{
  "sessions": [
    {
      "session_id": 42,
      "start_time": "2024-01-25T10:00:00Z",
      "end_time": "2024-01-25T11:00:00Z",
      "attendees": 42,
      "status": "completed"
    },
    ...
  ]
}
```

---

## 📝 Code Structure

### **File: `course_detail_screen.dart`**

**Widgets:**
- `CourseDetailScreen` (StatefulWidget)
  - Main screen containing all course information
  - Handles navigation and state

- `_StatTile` (Custom Widget)
  - Displays individual statistics
  - Shows icon, value, and label

- `_ActionTile` (Custom Widget)
  - Clickable action button
  - Shows icon, title, subtitle, and arrow

**Methods:**
- `_loadCourseDetails()` - Fetch data from backend
- `_startClass()` - Create new attendance session
- `_editCourse()` - Open edit course dialog

---

## 🎨 Design Details

### **Colors**
- Primary: `Colors.blue` (course header, stats)
- Success: `Color(0xFF4CAF50)` (Start Class button)
- Info: `Colors.orange` (alternative stats)
- Text: `Colors.black87` (main), `Colors.grey[500]` (secondary)

### **Spacing**
- Padding: 24px (main content)
- Card margins: 16px bottom
- Icon size: 28px (stats), 14px (trailing arrows)

### **Gradients**
- Course header: Blue → Light blue (top-left to bottom-right)
- Info card: Light blue background with border

---

## 🚀 Integration Checklist

- [ ] Implement `/courses/{course_id}` endpoint
- [ ] Implement `/sessions/create` endpoint
- [ ] Implement `/courses/{course_id}/roster` endpoint
- [ ] Implement `/courses/{course_id}/sessions` endpoint
- [ ] Update `_loadCourseDetails()` to fetch from backend
- [ ] Update `_startClass()` to create session
- [ ] Add Navigation to Roster screen
- [ ] Add Navigation to Session History screen
- [ ] Add Navigation to Course Edit screen
- [ ] Add QR code generation
- [ ] Add attendance marking flow

