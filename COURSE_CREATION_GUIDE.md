# Course Creation Feature

## ✅ What's Been Implemented

### **Backend (Python/FastAPI)**
- ✅ `POST /courses/create` - Create a new course (lecturer only)
- ✅ `GET /courses/my-courses` - Get courses for authenticated user
- ✅ Validation for duplicate course codes
- ✅ Authorization check (only lecturers can create)
- ✅ Proper error responses (409 for duplicate, 403 for non-lecturers)

### **Frontend (Flutter)**
- ✅ `CreateCourseScreen` with full UI
- ✅ Course code and name input fields
- ✅ Optional description field
- ✅ Loading state during submission
- ✅ Success/error notifications
- ✅ Auto-refresh courses list after creation
- ✅ Input validation

### **Database**
- ✅ `Courses` table already defined with local storage
- ✅ `insertCourse()` method available
- ✅ Sync queue integration ready

---

## 🔄 How It Works

### **User Flow**

1. **Lecturer opens dashboard**
2. **Taps "Create New Course" FAB**
3. **CreateCourseScreen opens**
4. **Fills in:**
   - Course Code (required, e.g., "CS101")
   - Course Name (required, e.g., "Data Structures")
   - Description (optional)
5. **Taps "Create Course"**
6. **App sends request to backend:**
   ```json
   POST /courses/create
   {
     "course_code": "CS101",
     "course_name": "Data Structures",
     "description": "..."
   }
   ```
7. **Backend validates and creates course**
8. **App shows success message**
9. **Course list refreshes automatically**

---

## 📝 Course Code Format

Course codes should be:
- **Unique** (backend enforces this)
- **2-4 letters + 3 digits**: CS101, MTH202, PHY101, ENG201
- **Automatically converted to uppercase**

Examples:
- ✅ CS101 → CS101
- ✅ cs101 → CS101
- ✅ mth202 → MTH202

---

## 🛠️ Backend Endpoints

### **Create Course**
```
POST /courses/create
Authorization: Bearer {firebase_id_token}
Content-Type: application/json

{
  "course_code": "CS101",
  "course_name": "Data Structures",
  "description": "Learn fundamental data structures"  // optional
}

Response (200):
{
  "course_id": 1,
  "course_code": "CS101",
  "course_name": "Data Structures",
  "lecturer_id": 5
}
```

**Error Responses:**
- `400` - Invalid request (missing required fields)
- `403` - Only lecturers can create courses
- `404` - Lecturer profile not found
- `409` - Course code already exists
- `500` - Server error

### **Get My Courses**
```
GET /courses/my-courses
Authorization: Bearer {firebase_id_token}

Response (200):
{
  "courses": [
    {
      "course_id": 1,
      "course_code": "CS101",
      "course_name": "Data Structures",
      "lecturer_id": 5
    },
    ...
  ]
}
```

---

## 🧪 Testing the Feature

### **Test 1: Create First Course**
- [ ] Log in as lecturer
- [ ] Tap "Create New Course" FAB
- [ ] Enter code: "CS101"
- [ ] Enter name: "Data Structures"
- [ ] Tap "Create Course"
- [ ] Verify success message
- [ ] Verify course appears in list

### **Test 2: Duplicate Course Code**
- [ ] Try to create another course with same code "CS101"
- [ ] Should show error: "Course code already exists"
- [ ] Try with different code "CS102" - should succeed

### **Test 3: Missing Required Fields**
- [ ] Try to create with empty course code
- [ ] Should show error: "Course code and name are required"
- [ ] Try with empty name - should also fail

### **Test 4: Backend URL Handling**
- [ ] Turn off network while creating
- [ ] Should show: "Backend is unreachable..."
- [ ] Restore network and try again - should work

### **Test 5: Offline Behavior**
- [ ] Create course online ✓
- [ ] Go offline
- [ ] Course should still be visible in dashboard (from local cache)
- [ ] Go online - should sync

---

## 📊 Course Creation Flow Diagram

```
Lecturer Dashboard
        ↓
   FAB Tapped
        ↓
 CreateCourseScreen
        ↓
  User enters:
  - Code: "CS101"
  - Name: "Data Structures"
  - Description: (optional)
        ↓
   User taps "Create"
        ↓
  Validate locally
  (code & name required)
        ↓
  POST /courses/create
  (with Firebase token)
        ↓
     Backend checks:
     - User is lecturer?
     - Code is unique?
     - Has profile?
        ↓
  Create in PostgreSQL
        ↓
    Return 200 ✓
        ↓
  Show success message
        ↓
  Refresh courses list
        ↓
  Close modal
```

---

## 🔐 Security Notes

- ✅ Only lecturers can create courses (role check on backend)
- ✅ Firebase token required for all requests
- ✅ Course code uniqueness enforced at database level
- ✅ CORS enabled for frontend communication
- ✅ All inputs sanitized (trimmed/uppercase)

---

## 🚀 Future Enhancements

1. **Batch upload** - Upload course list from CSV
2. **Course description templates** - Pre-filled descriptions
3. **Course settings** - Capacity, semester, schedule
4. **Student enrollment** - Add students to courses
5. **Course deletion** - Remove courses (with confirmation)
6. **Course editing** - Update course details
7. **QR code generation** - Auto-generate QR for enrollment

---

## 💡 Next Steps

After verifying course creation works:

1. ✅ Course creation (DONE)
2. **Course listing** - Get courses from backend
3. **Student enrollment** - Let students join courses
4. **Session creation** - Create attendance sessions
5. **Attendance marking** - Mark attendance
6. **Face recognition** - Add face verification

---

## 📱 Testing via Swagger

Once backend is running, test endpoints at:
```
http://localhost:8000/docs
```

Or production:
```
https://att-back-0xvj.onrender.com/docs
```

Try the "Create Course" endpoint with:
```json
{
  "course_code": "TEST101",
  "course_name": "Test Course"
}
```
