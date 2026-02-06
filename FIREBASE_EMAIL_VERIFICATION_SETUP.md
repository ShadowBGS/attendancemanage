# Email Verification Setup Guide for Firebase

This guide will help you configure email verification in Firebase for your attendance app.

## Overview

The email verification system works as follows:
1. When a user signs up with email/password, they're redirected to the **EmailVerificationScreen**
2. Firebase sends a verification email to their address
3. User clicks the link in their email to verify
4. The app automatically detects verification and proceeds to the next step

---

## Step 1: Enable Email Sign-In in Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project (Smart Attendance)
3. Navigate to **Authentication** → **Sign-in method**
4. Click on **Email/Password** provider
5. Enable **Email/Password** toggle
6. ✅ Optionally enable "Email link (passwordless sign-in)" if needed
7. Click **Save**

---

## Step 2: Configure Email Templates in Firebase

### Setting Up the Verification Email Template

1. In Firebase Console, go to **Authentication** → **Templates**
2. Click on **Verification email**
3. Update the email template with:

**Language:** English (or your preferred language)

**Subject:**
```
Verify your email for Smart Attendance
```

**Custom Template** (HTML):
```html
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; color: #333; }
    .container { max-width: 600px; margin: 0 auto; }
    .header { background: linear-gradient(135deg, #0D47A1 0%, #1565C0 100%); color: white; padding: 20px; text-align: center; }
    .content { padding: 20px; }
    .button { 
      background-color: #0D47A1; 
      color: white; 
      padding: 12px 30px; 
      text-decoration: none; 
      border-radius: 5px; 
      display: inline-block; 
      margin: 20px 0;
    }
    .footer { text-align: center; color: #999; font-size: 12px; margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>Verify Your Email</h1>
    </div>
    <div class="content">
      <p>Hi there,</p>
      <p>Thank you for registering for Smart Attendance. Please verify your email address by clicking the button below:</p>
      <center>
        <a href="%%LINK%%" class="button">Verify Email Address</a>
      </center>
      <p style="color: #999; font-size: 12px;">Or copy this link in your browser:</p>
      <p style="word-break: break-all; color: #0D47A1; font-size: 12px;">%%LINK%%</p>
      <p>This link will expire in 24 hours.</p>
      <p>If you didn't create this account, you can safely ignore this email.</p>
    </div>
    <div class="footer">
      <p>Smart Attendance System © 2024</p>
      <p>This is an automated email. Please do not reply directly.</p>
    </div>
  </div>
</body>
</html>
```

4. Click **Save**

---

## Step 3: Configure Authorized Domains

1. In Firebase Console, go to **Authentication** → **Settings**
2. Under **Authorized domains**, add your app's domains:
   - `localhost:8080` (for local testing)
   - `your-domain.com` (for production)
   - `att-back-0xvj.onrender.com` (your backend domain, if applicable)

3. Click **Save**

---

## Step 4: Update Flutter Code Configuration

Your Flutter code is already configured to handle email verification! Here's what happens:

### In `register_screen.dart`:
- After user creates account → **EmailVerificationScreen** is shown
- User receives verification email
- User clicks email link

### In `email_verification_screen.dart`:
- Sends verification email
- Automatically checks every 2 seconds if email is verified
- Shows countdown timer for resend (60 seconds)
- Once verified, proceeds to next step

### In `auth_screen.dart`:
- When logging in with email/password, checks if email is verified
- If not verified → shows **EmailVerificationScreen**
- If verified → proceeds to bootstrap and dashboard

---

## Step 5: Test Email Verification Locally

### Option A: Using Firebase Emulator (Recommended for Testing)

1. Install Firebase CLI:
```bash
npm install -g firebase-tools
```

2. Initialize Firebase in your project root:
```bash
firebase init emulators
```

3. Start the emulator:
```bash
firebase emulators:start
```

4. In your Flutter app's `main.dart`, add this before `Firebase.initializeApp()`:

```dart
import 'package:firebase_auth/firebase_auth.dart';

// Add this in main() before Firebase initialization
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Use Firebase Emulator for testing (remove in production!)
  if (kDebugMode) {
    try {
      await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    } catch (e) {
      // Error handling
    }
  }
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  database = AppDatabase();
  runApp(const SmartAttendanceApp());
}
```

5. Test signup → You'll see the "Email verified" option immediately in emulator

### Option B: Using Real Firebase (Production)

1. Sign up with email/password
2. Check your actual email inbox (and spam folder!)
3. Click the verification link
4. App automatically detects verification and continues

---

## Step 6: Customize Email Verification Behavior (Optional)

### Change Resend Countdown
Edit `email_verification_screen.dart` line 68:
```dart
void _startResendCountdown() {
  _timer?.cancel();
  setState(() => _resendCountdown = 60); // Change 60 to your desired seconds
```

### Change Auto-Check Interval
Edit `email_verification_screen.dart` line 83:
```dart
Timer.periodic(const Duration(seconds: 2), (timer) async { // Change 2 to your desired seconds
```

### Change Email Template
Go back to Firebase Console → **Authentication** → **Templates** → **Verification email**

---

## Step 7: Production Checklist

Before deploying to production:

- [ ] Email verification is enabled in Firebase Console
- [ ] Email templates are customized with your branding
- [ ] Authorized domains include your production domain
- [ ] Remove Firebase Emulator code from `main.dart`
- [ ] Test email delivery (check spam folder configuration)
- [ ] Set up email sending limits in Firebase (optional, in Settings)

---

## Troubleshooting

### Issue: Verification email not received

**Solution:**
1. Check spam/junk folder
2. Verify the email address is correct
3. Wait a few seconds (email delivery takes time)
4. Click "Resend" button after 60 seconds
5. Check Firebase → Authentication → Users → email sending logs

### Issue: "Resend" button stays disabled

**Solution:**
- The 60-second countdown is intentional to prevent spam
- Wait for the countdown to reach 0
- Edit the duration in `_startResendCountdown()` if needed

### Issue: User can't proceed after verifying

**Solution:**
1. Check that user actually clicked verification link
2. Try clicking "I've Verified My Email" button
3. Force refresh by pulling down on dashboard
4. If still stuck, user should logout and login again

### Issue: Verification email has old content

**Solution:**
1. Go to Firebase Console → Authentication → Templates
2. Delete any unused language versions
3. Update English template
4. Wait a few minutes for cache to refresh
5. Test with a new account

---

## Email Authentication Flow Diagram

```
┌─────────────────┐
│  User Signs Up  │
└────────┬────────┘
         │
         ▼
┌──────────────────────────┐
│ Create Firebase Account  │
└────────┬─────────────────┘
         │
         ▼
┌──────────────────────────┐
│ Show Verification Screen │
└────────┬─────────────────┘
         │
         ▼
┌──────────────────────────────────┐
│ Firebase sends verification      │
│ email (automatic)                │
└────────┬─────────────────────────┘
         │
         ▼
┌──────────────────────────────────┐
│ User clicks email link           │
│ (verifies in browser/Firebase)   │
└────────┬─────────────────────────┘
         │
         ▼
┌──────────────────────────────────┐
│ App detects verification (every  │
│ 2 seconds via idTokenChanges)    │
└────────┬─────────────────────────┘
         │
         ▼
┌──────────────────────────────────┐
│ Complete Profile Screen          │
│ (or Dashboard if profile exists) │
└──────────────────────────────────┘
```

---

## Key Features Implemented

✅ **Automatic Email Sending** - Firebase automatically sends verification emails

✅ **Auto-Detection** - App checks every 2 seconds if email is verified

✅ **Resend Capability** - Users can resend email after 60 seconds

✅ **Clear UI** - Shows email address and instructions

✅ **Fallback Options** - Users can manually check or use different email

✅ **Security** - Prevents access until email is verified

✅ **Works Offline** - Uses local cache while checking verification status

---

## API Reference

### EmailVerificationScreen

**Purpose:** Handle email verification after signup or login

**Parameters:**
- `role` (String): 'student' or 'lecturer'
- `user` (FirebaseUser): The user that needs verification

**Key Methods:**
- `_sendVerificationEmail()` - Sends verification email
- `_checkVerification()` - Manually check if verified
- `_startEmailVerificationCheck()` - Auto-check every 2 seconds
- `_startResendCountdown()` - Manage resend button cooldown

**Return Value:**
- Returns `true` if verification completed
- Returns `false` if user cancelled
- `null` if no decision made

---

## Support

For Firebase documentation, visit:
- [Firebase Authentication Docs](https://firebase.google.com/docs/auth)
- [Firebase Email Templates](https://firebase.google.com/docs/auth/custom-email-handler)
- [Firebase Emulator Suite](https://firebase.google.com/docs/emulator-suite)
