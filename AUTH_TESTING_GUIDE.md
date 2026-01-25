# Authentication Testing Guide

## ✅ Fixed Issues

### 1. **Google Sign-In API Update**
- Updated from deprecated `signIn()` to `authenticate()` (google_sign_in 7.2.0)
- Added proper error handling for `GoogleSignInException` with cancel detection
- Ensured `initialize()` is called before authentication

### 2. **Sign-Out Flow**
- Fixed imports in both dashboards for proper navigation after sign-out
- Properly clears both Firebase Auth and Google Sign-In sessions
- Navigates back to AuthGate (which shows RoleSelectionPage)

### 3. **Code Cleanup**
- Removed unused `_profileCompleted` variable
- Fixed all compile errors
- Consistent error handling across all auth screens

---

## 🔄 Complete Authentication Flow

### **New User Journey**

1. **App Launch** → `AuthGate`
   - Checks Firebase auth state
   - If not logged in → `RoleSelectionPage`

2. **Role Selection**
   - User selects Student or Lecturer
   - Taps "Continue as [Role]" → `AuthScreen(role: selectedRole)`

3. **Sign Up/Sign In (AuthScreen)**
   
   **Option A: Google Sign-In**
   - Tap "Continue with Google"
   - Google auth flow
   - Calls backend `/auth/bootstrap` with role
   - If profile incomplete → `CompleteProfileScreen`
   - If profile complete → Dashboard

   **Option B: Email/Password Sign-In**
   - Enter email and password
   - Sign in with Firebase Auth
   - Calls backend `/auth/bootstrap` with role
   - If profile incomplete → `CompleteProfileScreen`
   - If profile complete → Dashboard

   **Option C: Register**
   - Tap "Register" → `RegisterScreen(role: role)`
   - Fill in first name, last name, ID, department, email, password
   - Google Sign-Up also available
   - Creates Firebase account
   - Calls backend `/auth/bootstrap`
   - Goes to → `CompleteProfileScreen` OR Dashboard

4. **Complete Profile** (if needed)
   - Enter Student/Lecturer ID
   - Select Department
   - Calls backend `/profile/complete`
   - → Dashboard

5. **Dashboard**
   - **Lecturer Dashboard** - manage courses and sessions
   - **Student Dashboard** - view classes and attendance

### **Returning User Journey**

1. **App Launch** → `AuthGate`
   - Detects existing Firebase session
   - → `DashboardSelector`

2. **DashboardSelector**
   - Checks local database for cached user
   - If found → Navigate to appropriate dashboard immediately
   - Refreshes from backend in background
   - If no cache → Fetches from `/profile/info`
   - Saves to local database
   - → Dashboard

### **Sign Out Journey**

1. **User taps profile icon** in dashboard
2. **Profile sheet opens** with user info
3. **Tap "Sign out"**
4. Clears Firebase Auth session
5. Clears Google Sign-In session
6. Navigates to `AuthGate` (shows RoleSelectionPage)

---

## 🧪 Testing Checklist

### **Test 1: New User - Google Sign-In**
- [ ] Launch app
- [ ] Select role (Student/Lecturer)
- [ ] Tap "Continue with Google"
- [ ] Complete Google authentication
- [ ] Verify backend bootstrap call
- [ ] Complete profile if needed
- [ ] Verify dashboard loads with correct role

### **Test 2: New User - Email/Password**
- [ ] Launch app
- [ ] Select role
- [ ] Tap "Register"
- [ ] Fill all fields and submit
- [ ] Verify account created
- [ ] Complete profile
- [ ] Verify dashboard loads

### **Test 3: Returning User**
- [ ] Close app
- [ ] Reopen app
- [ ] Verify auto-login to correct dashboard
- [ ] Check user name displays correctly

### **Test 4: Sign Out**
- [ ] From dashboard, tap profile icon
- [ ] Tap "Sign out"
- [ ] Verify navigates to role selection
- [ ] Verify can sign in again

### **Test 5: Offline Handling**
- [ ] Turn off network
- [ ] Launch app as returning user
- [ ] Should load from local cache
- [ ] Should show dashboard immediately
- [ ] Turn on network
- [ ] Verify background sync

### **Test 6: Error Scenarios**
- [ ] Cancel Google sign-in → Shows "cancelled" message
- [ ] Wrong email/password → Shows error
- [ ] Network timeout → Graceful fallback
- [ ] Backend down → Shows helpful error message

---

## 🔧 Backend Dependencies

The app expects these endpoints:

1. **POST `/auth/bootstrap`**
   - Headers: `Authorization: Bearer {firebase_id_token}`
   - Body: `{"role": "student" | "lecturer"}`
   - Returns: `{"profile_completed": boolean, ...user data}`

2. **POST `/profile/complete`**
   - Headers: `Authorization: Bearer {firebase_id_token}`
   - Body: `{"external_id": string, "department": string}`
   - Returns: Updated user data

3. **GET `/profile/info`**
   - Headers: `Authorization: Bearer {firebase_id_token}`
   - Returns: Full user profile

### Backend URL Configuration
- Default: `https://att-back-0xvj.onrender.com`
- Override: Set `BACKEND_URL` environment variable
- For local testing: Use `--dart-define=BACKEND_URL=http://YOUR_IP:8000`

---

## 🚀 Next Steps After Auth Testing

Once authentication is solid:

1. **Course Management**
   - Create course flow
   - View courses
   - Enroll students

2. **Attendance Sessions**
   - Create session UI
   - Mark attendance (manual)
   - View attendance records

3. **Offline Sync**
   - Test sync queue
   - Conflict resolution
   - Background sync

4. **Face Recognition** (Last)
   - Camera integration
   - ML model
   - Face verification flow

---

## 📱 How to Run

```bash
# Basic run
flutter run

# With custom backend URL (for local testing)
flutter run --dart-define=BACKEND_URL=http://192.168.1.100:8000

# Clean build if issues
flutter clean
flutter pub get
flutter run
```

---

## 🐛 Known Issues / TODO

- [ ] Student dashboard shows dummy course data (needs real data from backend)
- [ ] Lecturer dashboard shows "0 students" (needs enrollment count)
- [ ] Profile images show placeholder icons (need avatar upload)
- [ ] "Manage your Google Account" button is placeholder

---

## 📝 Notes

- All auth flows now use google_sign_in 7.2.0 API (`authenticate()`)
- Sign-out properly clears both Firebase and Google sessions
- Local database caching improves offline experience
- Error messages are user-friendly and specific
