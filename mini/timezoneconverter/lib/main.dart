import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';

// TIMEZONE API SERVICE - NEW ADDITION
class TimezoneApiService {
  // Using ipapi.co - free API that provides timezone info based on IP
  static const String _apiUrl = 'https://ipapi.co/json/';

  // Get user's timezone from their IP address
  static Future<Map<String, dynamic>?> getUserTimezone() async {
    try {
      final response = await http.get(Uri.parse(_apiUrl));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'timezone': data['timezone'], // e.g., 'America/New_York'
          'city': data['city'],
          'country': data['country_name'],
          'latitude': data['latitude'],
          'longitude': data['longitude'],
          'utc_offset': data['utc_offset'], // e.g., '-0500'
        };
      }
    } catch (e) {
      print('Error fetching timezone: $e');
    }
    return null;
  }

  // Alternative: Get timezone by coordinates (if user allows location access)
  static Future<String?> getTimezoneByCoordinates(double lat, double lon) async {
    try {
      // Using TimeZoneDB API (requires free API key from timezonedb.com)
      // Replace 'YOUR_API_KEY' with actual key
      const apiKey = '3K5K5UGCLN3D';
      final url = 'http://api.timezonedb.com/v2.1/get-time-zone?key=$apiKey&format=json&by=position&lat=$lat&lng=$lon';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['zoneName'];
      }
    } catch (e) {
      print('Error fetching timezone by coordinates: $e');
    }
    return null;
  }
}

// IMPORTANT: Replace this with your generated firebase_options.dart
// Run: flutterfire configure
class DefaultFirebaseOptions {
static FirebaseOptions get currentPlatform {
return const FirebaseOptions(
apiKey: 'your-api-key',
appId: 'your-app-id',
messagingSenderId: 'your-sender-id',
projectId: 'your-project-id',
);
}
}

void main() async {
WidgetsFlutterBinding.ensureInitialized();
try {
await Firebase.initializeApp(
options: DefaultFirebaseOptions.currentPlatform,
);
print('Firebase initialized successfully');
} catch (e) {
print('Firebase initialization error: $e');
}
tz.initializeTimeZones();
runApp(const TimezoneConverterApp());
}

// Auth Service
class AuthService {
final FirebaseAuth _auth = FirebaseAuth.instance;
GoogleSignIn? _googleSignIn;

User? get currentUser => _auth.currentUser;
Stream<User?> get authStateChanges => _auth.authStateChanges();

// Initialize GoogleSignIn lazily
GoogleSignIn _getGoogleSignIn() {
_googleSignIn ??= GoogleSignIn(
scopes: ['email'],
signInOption: SignInOption.standard,
);
return _googleSignIn!;
}

// Email & Password Sign Up
Future<UserCredential?> signUpWithEmail(String email, String password) async {
try {
final userCredential = await _auth.createUserWithEmailAndPassword(
email: email,
password: password,
);
print('Sign up successful: ${userCredential.user?.uid}');
return userCredential;
} on FirebaseAuthException catch (e) {
print('Sign up error: ${e.code} - ${e.message}');
throw _handleAuthException(e);
} catch (e) {
print('Sign up unknown error: $e');
throw 'Sign up failed: $e';
}
}

// Email & Password Sign In
Future<UserCredential?> signInWithEmail(String email, String password) async {
try {
final userCredential = await _auth.signInWithEmailAndPassword(
email: email,
password: password,
);
print('Sign in successful: ${userCredential.user?.uid}');
return userCredential;
} on FirebaseAuthException catch (e) {
print('Sign in error: ${e.code} - ${e.message}');
throw _handleAuthException(e);
} catch (e) {
print('Sign in unknown error: $e');
throw 'Sign in failed: $e';
}
}

// Google Sign In - Completely rewritten to fix type cast error
Future<UserCredential?> signInWithGoogle() async {
try {
print('Starting Google Sign In...');

final googleSignIn = _getGoogleSignIn();

// Disconnect any existing session
if (await googleSignIn.isSignedIn()) {
await googleSignIn.disconnect();
}

// Trigger the authentication flow
final GoogleSignInAccount? googleUser = await googleSignIn.signIn().catchError((error) {
print('Google signIn error: $error');
throw 'Failed to sign in with Google: $error';
});

if (googleUser == null) {
print('Google sign in cancelled by user');
return null;
}

print('Google user obtained: ${googleUser.email}');

// Obtain the auth details from the request
final GoogleSignInAuthentication googleAuth = await googleUser.authentication.catchError((error) {
print('Google authentication error: $error');
throw 'Failed to get Google authentication: $error';
});

print('Access token obtained: ${googleAuth.accessToken != null}');
print('ID token obtained: ${googleAuth.idToken != null}');

if (googleAuth.accessToken == null && googleAuth.idToken == null) {
throw 'Failed to obtain authentication tokens from Google';
}

// Create a new credential
final credential = GoogleAuthProvider.credential(
accessToken: googleAuth.accessToken,
idToken: googleAuth.idToken,
);

print('Credential created, signing in to Firebase...');

// Sign in to Firebase with the Google credential
final UserCredential userCredential = await _auth.signInWithCredential(credential).catchError((error) {
print('Firebase signInWithCredential error: $error');
throw 'Failed to sign in to Firebase: $error';
});

print('Google sign in successful: ${userCredential.user?.uid}');
print('User email: ${userCredential.user?.email}');
print('User display name: ${userCredential.user?.displayName}');

return userCredential;

} on FirebaseAuthException catch (e) {
print('FirebaseAuthException: ${e.code} - ${e.message}');
throw _handleAuthException(e);
} catch (e) {
print('Google sign in caught error: $e');
print('Error type: ${e.runtimeType}');
throw 'Google sign in failed. Please try again.';
}
}

// Phone Sign In - Send verification code
Future<void> verifyPhoneNumber({
required String phoneNumber,
required Function(String verificationId) codeSent,
required Function(String error) verificationFailed,
}) async {
await _auth.verifyPhoneNumber(
phoneNumber: phoneNumber,
verificationCompleted: (PhoneAuthCredential credential) async {
await _auth.signInWithCredential(credential);
},
verificationFailed: (FirebaseAuthException e) {
verificationFailed(_handleAuthException(e));
},
codeSent: (String verificationId, int? resendToken) {
codeSent(verificationId);
},
codeAutoRetrievalTimeout: (String verificationId) {},
);
}

// Phone Sign In - Verify code
Future<UserCredential?> signInWithPhone(String verificationId, String smsCode) async {
try {
final credential = PhoneAuthProvider.credential(
verificationId: verificationId,
smsCode: smsCode,
);
return await _auth.signInWithCredential(credential);
} on FirebaseAuthException catch (e) {
throw _handleAuthException(e);
}
}

// Guest Sign In
Future<UserCredential?> signInAnonymously() async {
try {
print('Starting anonymous sign in...');
final userCredential = await _auth.signInAnonymously();
print('Anonymous sign in successful: ${userCredential.user?.uid}');
return userCredential;
} on FirebaseAuthException catch (e) {
print('Anonymous sign in error: ${e.code} - ${e.message}');
throw _handleAuthException(e);
} catch (e) {
print('Anonymous sign in unknown error: $e');
throw 'Anonymous sign in failed: $e';
}
}

// Sign Out
Future<void> signOut() async {
try {
final googleSignIn = _getGoogleSignIn();
if (await googleSignIn.isSignedIn()) {
await googleSignIn.disconnect();
await googleSignIn.signOut();
}
await _auth.signOut();
print('Sign out successful');
} catch (e) {
print('Sign out error: $e');
// Still sign out from Firebase even if Google sign out fails
await _auth.signOut();
}
}

// Reset Password
Future<void> resetPassword(String email) async {
try {
await _auth.sendPasswordResetEmail(email: email);
} on FirebaseAuthException catch (e) {
throw _handleAuthException(e);
}
}

String _handleAuthException(FirebaseAuthException e) {
switch (e.code) {
case 'weak-password':
return 'The password is too weak. Use at least 6 characters.';
case 'email-already-in-use':
return 'An account already exists with this email.';
case 'invalid-email':
return 'Invalid email address format.';
case 'user-not-found':
return 'No account found with this email.';
case 'wrong-password':
return 'Incorrect password. Please try again.';
case 'user-disabled':
return 'This account has been disabled.';
case 'too-many-requests':
return 'Too many failed attempts. Please try again later.';
case 'operation-not-allowed':
return 'This sign-in method is not enabled.';
case 'invalid-verification-code':
return 'Invalid verification code. Please try again.';
case 'invalid-phone-number':
return 'Invalid phone number format. Include country code (e.g., +1).';
case 'invalid-credential':
return 'Invalid credentials. Please check your information.';
case 'account-exists-with-different-credential':
return 'An account already exists with this email using a different sign-in method.';
case 'credential-already-in-use':
return 'This credential is already linked to another account.';
default:
return e.message ?? 'Authentication error occurred. Please try again.';
}
}
}

final authService = AuthService();

// Premium Status Manager
class PremiumManager extends ChangeNotifier {
bool _isPremium = false;

bool get isPremium => _isPremium;

void setPremium(bool value) {
_isPremium = value;
notifyListeners();
}

static const int maxFreeFavorites = 5;
}

final premiumManager = PremiumManager();

// Theme Manager
class ThemeManager extends ChangeNotifier {
ThemeMode _themeMode = ThemeMode.system;
Color _seedColor = Colors.blue;
String _selectedIcon = 'public';

ThemeMode get themeMode => _themeMode;
Color get seedColor => _seedColor;
String get selectedIcon => _selectedIcon;

void setThemeMode(ThemeMode mode) {
_themeMode = mode;
notifyListeners();
}

void setSeedColor(Color color) {
_seedColor = color;
notifyListeners();
}

void setIcon(String icon) {
_selectedIcon = icon;
notifyListeners();
}
}

final themeManager = ThemeManager();

class TimezoneConverterApp extends StatelessWidget {
const TimezoneConverterApp({super.key});

@override
Widget build(BuildContext context) {
return AnimatedBuilder(
animation: themeManager,
builder: (context, child) {
return MaterialApp(
title: 'Timezone Converter',
debugShowCheckedModeBanner: false,
themeMode: themeManager.themeMode,
theme: ThemeData(
colorScheme: ColorScheme.fromSeed(
seedColor: themeManager.seedColor,
brightness: Brightness.light,
),
useMaterial3: true,
),
darkTheme: ThemeData(
colorScheme: ColorScheme.fromSeed(
seedColor: themeManager.seedColor,
brightness: Brightness.dark,
),
useMaterial3: true,
),
home: const AuthWrapper(),
);
},
);
}
}

// Auth Wrapper - Determines which screen to show
class AuthWrapper extends StatelessWidget {
const AuthWrapper({super.key});

@override
Widget build(BuildContext context) {
print('AuthWrapper building...');
return StreamBuilder<User?>(
stream: authService.authStateChanges,
builder: (context, snapshot) {
print('Auth state: ${snapshot.connectionState}, hasData: ${snapshot.hasData}, user: ${snapshot.data?.uid}');

if (snapshot.connectionState == ConnectionState.waiting) {
return const Scaffold(
body: Center(
child: Column(
mainAxisAlignment: MainAxisAlignment.center,
children: [
CircularProgressIndicator(),
SizedBox(height: 16),
Text('Loading...'),
],
),
),
);
}

if (snapshot.hasError) {
print('Auth error: ${snapshot.error}');
return Scaffold(
body: Center(
child: Column(
mainAxisAlignment: MainAxisAlignment.center,
children: [
const Icon(Icons.error, size: 64, color: Colors.red),
const SizedBox(height: 16),
Text('Error: ${snapshot.error}'),
const SizedBox(height: 16),
ElevatedButton(
onPressed: () {
// Try to reload
},
child: const Text('Retry'),
),
],
),
),
);
}

if (snapshot.hasData && snapshot.data != null) {
print('User authenticated, showing main screen');
return const MainScreen();
}

print('No user, showing login screen');
return const LoginScreen();
},
);
}
}

// Login Screen
class LoginScreen extends StatefulWidget {
const LoginScreen({super.key});

@override
State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
bool _isSignUp = false;

@override
Widget build(BuildContext context) {
return Scaffold(
body: SafeArea(
child: SingleChildScrollView(
padding: const EdgeInsets.all(24),
child: Column(
crossAxisAlignment: CrossAxisAlignment.stretch,
children: [
const SizedBox(height: 40),
Icon(
Icons.public,
size: 80,
color: Theme.of(context).colorScheme.primary,
),
const SizedBox(height: 16),
Text(
'Timezone Converter',
textAlign: TextAlign.center,
style: Theme.of(context).textTheme.headlineMedium?.copyWith(
fontWeight: FontWeight.bold,
),
),
const SizedBox(height: 8),
Text(
'Convert time across the globe',
textAlign: TextAlign.center,
style: Theme.of(context).textTheme.bodyLarge?.copyWith(
color: Theme.of(context).colorScheme.onSurfaceVariant,
),
),
const SizedBox(height: 48),
if (_isSignUp)
const EmailSignUpForm()
else
const EmailSignInForm(),
const SizedBox(height: 16),
TextButton(
onPressed: () {
setState(() {
_isSignUp = !_isSignUp;
});
},
child: Text(
_isSignUp
? 'Already have an account? Sign In'
    : 'Don\'t have an account? Sign Up',
),
),
const SizedBox(height: 24),
Row(
children: [
const Expanded(child: Divider()),
Padding(
padding: const EdgeInsets.symmetric(horizontal: 16),
child: Text(
'OR',
style: Theme.of(context).textTheme.bodySmall,
),
),
const Expanded(child: Divider()),
],
),
const SizedBox(height: 24),
// Google Sign In
OutlinedButton.icon(
onPressed: () async {
try {
print('Google button pressed');
final result = await authService.signInWithGoogle();
if (result != null && mounted) {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text('✅ Google sign in successful!'),
backgroundColor: Colors.green,
),
);
}
} catch (e) {
print('Google sign in button error: $e');
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text(e.toString()),
backgroundColor: Colors.red,
),
);
}
}
},
icon: const Icon(Icons.g_mobiledata, size: 32),
label: const Text('Continue with Google'),
style: OutlinedButton.styleFrom(
padding: const EdgeInsets.all(16),
),
),
const SizedBox(height: 12),
// Phone Sign In
OutlinedButton.icon(
onPressed: () {
Navigator.push(
context,
MaterialPageRoute(
builder: (context) => const PhoneSignInScreen(),
),
);
},
icon: const Icon(Icons.phone),
label: const Text('Continue with Phone'),
style: OutlinedButton.styleFrom(
padding: const EdgeInsets.all(16),
),
),
const SizedBox(height: 12),
// Guest Sign In
OutlinedButton.icon(
onPressed: () async {
try {
print('Guest button pressed');
final result = await authService.signInAnonymously();
if (result != null && mounted) {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text('✅ Signed in as guest!'),
backgroundColor: Colors.green,
),
);
}
} catch (e) {
print('Guest sign in button error: $e');
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text(e.toString()),
backgroundColor: Colors.red,
),
);
}
}
},
icon: const Icon(Icons.person_outline),
label: const Text('Continue as Guest'),
style: OutlinedButton.styleFrom(
padding: const EdgeInsets.all(16),
),
),
],
),
),
),
);
}
}

// Email Sign In Form
class EmailSignInForm extends StatefulWidget {
const EmailSignInForm({super.key});

@override
State<EmailSignInForm> createState() => _EmailSignInFormState();
}

class _EmailSignInFormState extends State<EmailSignInForm> {
final _formKey = GlobalKey<FormState>();
final _emailController = TextEditingController();
final _passwordController = TextEditingController();
bool _isLoading = false;
bool _obscurePassword = true;

@override
void dispose() {
_emailController.dispose();
_passwordController.dispose();
super.dispose();
}

Future<void> _signIn() async {
if (!_formKey.currentState!.validate()) return;

setState(() => _isLoading = true);

try {
print('Attempting to sign in with: ${_emailController.text.trim()}');
final result = await authService.signInWithEmail(
_emailController.text.trim(),
_passwordController.text,
);
print('Sign in result: ${result?.user?.uid}');

if (result != null && mounted) {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text('✅ Sign in successful!'),
backgroundColor: Colors.green,
),
);
}
} catch (e) {
print('Sign in failed with error: $e');
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text(e.toString()),
backgroundColor: Colors.red,
),
);
}
} finally {
if (mounted) setState(() => _isLoading = false);
}
}

@override
Widget build(BuildContext context) {
return Form(
key: _formKey,
child: Column(
children: [
TextFormField(
controller: _emailController,
decoration: const InputDecoration(
labelText: 'Email',
prefixIcon: Icon(Icons.email),
border: OutlineInputBorder(),
),
keyboardType: TextInputType.emailAddress,
validator: (value) {
if (value == null || value.isEmpty) {
return 'Please enter your email';
}
if (!value.contains('@')) {
return 'Please enter a valid email';
}
return null;
},
),
const SizedBox(height: 16),
TextFormField(
controller: _passwordController,
decoration: InputDecoration(
labelText: 'Password',
prefixIcon: const Icon(Icons.lock),
border: const OutlineInputBorder(),
suffixIcon: IconButton(
icon: Icon(
_obscurePassword ? Icons.visibility : Icons.visibility_off,
),
onPressed: () {
setState(() => _obscurePassword = !_obscurePassword);
},
),
),
obscureText: _obscurePassword,
validator: (value) {
if (value == null || value.isEmpty) {
return 'Please enter your password';
}
return null;
},
),
const SizedBox(height: 8),
Align(
alignment: Alignment.centerRight,
child: TextButton(
onPressed: () {
Navigator.push(
context,
MaterialPageRoute(
builder: (context) => const ForgotPasswordScreen(),
),
);
},
child: const Text('Forgot Password?'),
),
),
const SizedBox(height: 16),
FilledButton(
onPressed: _isLoading ? null : _signIn,
style: FilledButton.styleFrom(
padding: const EdgeInsets.all(16),
minimumSize: const Size.fromHeight(50),
),
child: _isLoading
? const SizedBox(
height: 20,
width: 20,
child: CircularProgressIndicator(strokeWidth: 2),
)
    : const Text('Sign In'),
),
],
),
);
}
}

// Email Sign Up Form
class EmailSignUpForm extends StatefulWidget {
const EmailSignUpForm({super.key});

@override
State<EmailSignUpForm> createState() => _EmailSignUpFormState();
}

class _EmailSignUpFormState extends State<EmailSignUpForm> {
final _formKey = GlobalKey<FormState>();
final _emailController = TextEditingController();
final _passwordController = TextEditingController();
final _confirmPasswordController = TextEditingController();
bool _isLoading = false;
bool _obscurePassword = true;
bool _obscureConfirmPassword = true;

@override
void dispose() {
_emailController.dispose();
_passwordController.dispose();
_confirmPasswordController.dispose();
super.dispose();
}

Future<void> _signUp() async {
if (!_formKey.currentState!.validate()) return;

setState(() => _isLoading = true);

try {
print('Attempting to sign up with: ${_emailController.text.trim()}');
final result = await authService.signUpWithEmail(
_emailController.text.trim(),
_passwordController.text,
);
print('Sign up result: ${result?.user?.uid}');

if (result != null && mounted) {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text('✅ Account created successfully!'),
backgroundColor: Colors.green,
),
);
}
} catch (e) {
print('Sign up failed with error: $e');
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text(e.toString()),
backgroundColor: Colors.red,
),
);
}
} finally {
if (mounted) setState(() => _isLoading = false);
}
}

@override
Widget build(BuildContext context) {
return Form(
key: _formKey,
child: Column(
children: [
TextFormField(
controller: _emailController,
decoration: const InputDecoration(
labelText: 'Email',
prefixIcon: Icon(Icons.email),
border: OutlineInputBorder(),
),
keyboardType: TextInputType.emailAddress,
validator: (value) {
if (value == null || value.isEmpty) {
return 'Please enter your email';
}
if (!value.contains('@')) {
return 'Please enter a valid email';
}
return null;
},
),
const SizedBox(height: 16),
TextFormField(
controller: _passwordController,
decoration: InputDecoration(
labelText: 'Password',
prefixIcon: const Icon(Icons.lock),
border: const OutlineInputBorder(),
suffixIcon: IconButton(
icon: Icon(
_obscurePassword ? Icons.visibility : Icons.visibility_off,
),
onPressed: () {
setState(() => _obscurePassword = !_obscurePassword);
},
),
),
obscureText: _obscurePassword,
validator: (value) {
if (value == null || value.isEmpty) {
return 'Please enter a password';
}
if (value.length < 6) {
return 'Password must be at least 6 characters';
}
return null;
},
),
const SizedBox(height: 16),
TextFormField(
controller: _confirmPasswordController,
decoration: InputDecoration(
labelText: 'Confirm Password',
prefixIcon: const Icon(Icons.lock_outline),
border: const OutlineInputBorder(),
suffixIcon: IconButton(
icon: Icon(
_obscureConfirmPassword
? Icons.visibility
    : Icons.visibility_off,
),
onPressed: () {
setState(() =>
_obscureConfirmPassword = !_obscureConfirmPassword);
},
),
),
obscureText: _obscureConfirmPassword,
validator: (value) {
if (value == null || value.isEmpty) {
return 'Please confirm your password';
}
if (value != _passwordController.text) {
return 'Passwords do not match';
}
return null;
},
),
const SizedBox(height: 24),
FilledButton(
onPressed: _isLoading ? null : _signUp,
style: FilledButton.styleFrom(
padding: const EdgeInsets.all(16),
minimumSize: const Size.fromHeight(50),
),
child: _isLoading
? const SizedBox(
height: 20,
width: 20,
child: CircularProgressIndicator(strokeWidth: 2),
)
    : const Text('Sign Up'),
),
],
),
);
}
}

// Phone Sign In Screen
class PhoneSignInScreen extends StatefulWidget {
const PhoneSignInScreen({super.key});

@override
State<PhoneSignInScreen> createState() => _PhoneSignInScreenState();
}

class _PhoneSignInScreenState extends State<PhoneSignInScreen> {
final _phoneController = TextEditingController();
final _codeController = TextEditingController();
String? _verificationId;
bool _isLoading = false;
bool _codeSent = false;

@override
void dispose() {
_phoneController.dispose();
_codeController.dispose();
super.dispose();
}

Future<void> _sendCode() async {
if (_phoneController.text.isEmpty) {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(content: Text('Please enter your phone number')),
);
return;
}

setState(() => _isLoading = true);

await authService.verifyPhoneNumber(
phoneNumber: _phoneController.text.trim(),
codeSent: (verificationId) {
if (mounted) {
setState(() {
_verificationId = verificationId;
_codeSent = true;
_isLoading = false;
});
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(content: Text('Verification code sent!')),
);
}
},
verificationFailed: (error) {
if (mounted) {
setState(() => _isLoading = false);
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(content: Text(error)),
);
}
},
);
}

Future<void> _verifyCode() async {
if (_codeController.text.isEmpty || _verificationId == null) {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(content: Text('Please enter the verification code')),
);
return;
}

setState(() => _isLoading = true);

try {
await authService.signInWithPhone(_verificationId!, _codeController.text);
if (mounted) {
Navigator.of(context).pop();
}
} catch (e) {
if (mounted) {
setState(() => _isLoading = false);
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(content: Text(e.toString())),
);
}
}
}

@override
Widget build(BuildContext context) {
return Scaffold(
appBar: AppBar(
title: const Text('Phone Sign In'),
),
body: Padding(
padding: const EdgeInsets.all(24),
child: Column(
crossAxisAlignment: CrossAxisAlignment.stretch,
children: [
const Icon(Icons.phone, size: 64),
const SizedBox(height: 24),
Text(
_codeSent
? 'Enter Verification Code'
    : 'Enter Your Phone Number',
textAlign: TextAlign.center,
style: Theme.of(context).textTheme.headlineSmall,
),
const SizedBox(height: 8),
Text(
_codeSent
? 'We sent a code to ${_phoneController.text}'
    : 'Include country code (e.g., +1234567890)',
textAlign: TextAlign.center,
style: Theme.of(context).textTheme.bodyMedium?.copyWith(
color: Theme.of(context).colorScheme.onSurfaceVariant,
),
),
const SizedBox(height: 32),
if (!_codeSent) ...[
TextField(
controller: _phoneController,
decoration: const InputDecoration(
labelText: 'Phone Number',
prefixIcon: Icon(Icons.phone),
border: OutlineInputBorder(),
hintText: '+1234567890',
),
keyboardType: TextInputType.phone,
),
const SizedBox(height: 24),
FilledButton(
onPressed: _isLoading ? null : _sendCode,
style: FilledButton.styleFrom(
padding: const EdgeInsets.all(16),
),
child: _isLoading
? const SizedBox(
height: 20,
width: 20,
child: CircularProgressIndicator(strokeWidth: 2),
)
    : const Text('Send Code'),
),
] else ...[
TextField(
controller: _codeController,
decoration: const InputDecoration(
labelText: 'Verification Code',
prefixIcon: Icon(Icons.sms),
border: OutlineInputBorder(),
),
keyboardType: TextInputType.number,
),
const SizedBox(height: 24),
FilledButton(
onPressed: _isLoading ? null : _verifyCode,
style: FilledButton.styleFrom(
padding: const EdgeInsets.all(16),
),
child: _isLoading
? const SizedBox(
height: 20,
width: 20,
child: CircularProgressIndicator(strokeWidth: 2),
)
    : const Text('Verify'),
),
const SizedBox(height: 16),
TextButton(
onPressed: _isLoading
? null
    : () {
setState(() {
_codeSent = false;
_codeController.clear();
});
},
child: const Text('Change Phone Number'),
),
],
],
),
),
);
}
}

// Forgot Password Screen
class ForgotPasswordScreen extends StatefulWidget {
const ForgotPasswordScreen({super.key});

@override
State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
final _emailController = TextEditingController();
bool _isLoading = false;
bool _emailSent = false;

@override
void dispose() {
_emailController.dispose();
super.dispose();
}

Future<void> _resetPassword() async {
if (_emailController.text.isEmpty) {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(content: Text('Please enter your email')),
);
return;
}

setState(() => _isLoading = true);

try {
await authService.resetPassword(_emailController.text.trim());
if (mounted) {
setState(() {
_isLoading = false;
_emailSent = true;
});
}
} catch (e) {
if (mounted) {
setState(() => _isLoading = false);
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(content: Text(e.toString())),
);
}
}
}

@override
Widget build(BuildContext context) {
return Scaffold(
appBar: AppBar(
title: const Text('Reset Password'),
),
body: Padding(
padding: const EdgeInsets.all(24),
child: Column(
crossAxisAlignment: CrossAxisAlignment.stretch,
children: [
const Icon(Icons.lock_reset, size: 64),
const SizedBox(height: 24),
Text(
_emailSent ? 'Check Your Email' : 'Forgot Password?',
textAlign: TextAlign.center,
style: Theme.of(context).textTheme.headlineSmall,
),
const SizedBox(height: 8),
Text(
_emailSent
? 'We sent a password reset link to ${_emailController.text}'
    : 'Enter your email and we\'ll send you a reset link',
textAlign: TextAlign.center,
style: Theme.of(context).textTheme.bodyMedium?.copyWith(
color: Theme.of(context).colorScheme.onSurfaceVariant,
),
),
const SizedBox(height: 32),
if (!_emailSent) ...[
TextField(
controller: _emailController,
decoration: const InputDecoration(
labelText: 'Email',
prefixIcon: Icon(Icons.email),
border: OutlineInputBorder(),
),
keyboardType: TextInputType.emailAddress,
),
const SizedBox(height: 24),
FilledButton(
onPressed: _isLoading ? null : _resetPassword,
style: FilledButton.styleFrom(
padding: const EdgeInsets.all(16),
),
child: _isLoading
? const SizedBox(
height: 20,
width: 20,
child: CircularProgressIndicator(strokeWidth: 2),
)
    : const Text('Send Reset Link'),
),
] else ...[
FilledButton(
onPressed: () => Navigator.pop(context),
style: FilledButton.styleFrom(
padding: const EdgeInsets.all(16),
),
child: const Text('Back to Sign In'),
),
],
],
),
),
);
}
}

class MainScreen extends StatefulWidget {
const MainScreen({super.key});

@override
State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
@override
Widget build(BuildContext context) {
return Scaffold(
appBar: AppBar(
title: Row(
mainAxisSize: MainAxisSize.min,
children: [
const Text('Timezone Converter'),
AnimatedBuilder(
animation: premiumManager,
builder: (context, child) {
if (premiumManager.isPremium) {
return Row(
children: [
const SizedBox(width: 8),
Container(
padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
decoration: BoxDecoration(
gradient: const LinearGradient(
colors: [Colors.amber, Colors.orange],
),
borderRadius: BorderRadius.circular(12),
),
child: const Text(
'PRO',
style: TextStyle(
fontSize: 10,
fontWeight: FontWeight.bold,
color: Colors.white,
),
),
),
],
);
}
return const SizedBox.shrink();
},
),
],
),
centerTitle: true,
elevation: 2,
actions: [
IconButton(
icon: const Icon(Icons.add_circle_outline),
tooltip: 'Add Timezone',
onPressed: () {
Navigator.push(
context,
MaterialPageRoute(
builder: (context) => const SearchTimezoneTab(),
),
);
},
),
],
),
body: const TimezoneConverterHome(),
drawer: const AppDrawer(),
);
}
}

// App Drawer
class AppDrawer extends StatelessWidget {
const AppDrawer({super.key});

@override
Widget build(BuildContext context) {
final user = authService.currentUser;
final isAnonymous = user?.isAnonymous ?? false;

return Drawer(
child: Column(
children: [
// Drawer Header with User Info
AnimatedBuilder(
animation: premiumManager,
builder: (context, child) {
return UserAccountsDrawerHeader(
decoration: BoxDecoration(
gradient: LinearGradient(
colors: premiumManager.isPremium
? [Colors.amber, Colors.orange]
    : [
Theme.of(context).colorScheme.primary,
Theme.of(context).colorScheme.primaryContainer,
],
begin: Alignment.topLeft,
end: Alignment.bottomRight,
),
),
currentAccountPicture: CircleAvatar(
backgroundColor: Colors.white,
child: user?.photoURL != null
? ClipOval(
child: Image.network(
user!.photoURL!,
width: 72,
height: 72,
fit: BoxFit.cover,
errorBuilder: (context, error, stackTrace) {
return Icon(
isAnonymous ? Icons.person_outline : Icons.person,
size: 40,
color: Theme.of(context).colorScheme.primary,
);
},
),
)
    : Icon(
isAnonymous ? Icons.person_outline : Icons.person,
size: 40,
color: Theme.of(context).colorScheme.primary,
),
),
accountName: Row(
children: [
Text(
isAnonymous ? 'Guest User' : (user?.displayName ?? 'User'),
style: const TextStyle(
fontWeight: FontWeight.bold,
fontSize: 18,
),
),
if (premiumManager.isPremium) ...[
const SizedBox(width: 8),
Container(
padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
decoration: BoxDecoration(
color: Colors.white,
borderRadius: BorderRadius.circular(12),
),
child: const Row(
mainAxisSize: MainAxisSize.min,
children: [
Icon(Icons.star, size: 12, color: Colors.amber),
SizedBox(width: 2),
Text(
'PRO',
style: TextStyle(
fontSize: 10,
fontWeight: FontWeight.bold,
color: Colors.amber,
),
),
],
),
),
],
],
),
accountEmail: user?.email != null
? Text(user!.email!)
    : Text(isAnonymous ? 'Temporary Account' : 'No email'),
);
},
),

// Drawer Menu Items
Expanded(
child: ListView(
padding: EdgeInsets.zero,
children: [
ListTile(
leading: const Icon(Icons.person),
title: const Text('Profile'),
subtitle: const Text('View and edit profile'),
trailing: const Icon(Icons.chevron_right),
onTap: () {
Navigator.pop(context);
Navigator.push(
context,
MaterialPageRoute(
builder: (context) => const ProfileTab(),
),
);
},
),
const Divider(),
AnimatedBuilder(
animation: premiumManager,
builder: (context, child) {
return ListTile(
leading: Stack(
children: [
const Icon(Icons.star),
if (!premiumManager.isPremium)
Positioned(
right: 0,
top: 0,
child: Container(
padding: const EdgeInsets.all(2),
decoration: const BoxDecoration(
color: Colors.red,
shape: BoxShape.circle,
),
constraints: const BoxConstraints(
minWidth: 8,
minHeight: 8,
),
),
),
],
),
title: const Text('Premium'),
subtitle: Text(
premiumManager.isPremium
? 'Active • Manage settings'
    : 'Upgrade for unlimited features',
),
trailing: premiumManager.isPremium
? const Icon(Icons.check_circle, color: Colors.green)
    : const Icon(Icons.chevron_right),
onTap: () {
Navigator.pop(context);
Navigator.push(
context,
MaterialPageRoute(
builder: (context) => const PremiumTab(),
),
);
},
);
},
),
const Divider(),
ListTile(
leading: const Icon(Icons.settings),
title: const Text('Settings'),
subtitle: const Text('App preferences'),
trailing: const Icon(Icons.chevron_right),
onTap: () {
Navigator.pop(context);
_showSettingsSheet(context);
},
),
ListTile(
leading: const Icon(Icons.help_outline),
title: const Text('Help & Support'),
trailing: const Icon(Icons.chevron_right),
onTap: () {
Navigator.pop(context);
_showHelpDialog(context);
},
),
ListTile(
leading: const Icon(Icons.info_outline),
title: const Text('About'),
trailing: const Icon(Icons.chevron_right),
onTap: () {
Navigator.pop(context);
_showAboutDialog(context);
},
),
],
),
),

// Sign Out Button at Bottom
const Divider(),
ListTile(
leading: Icon(
Icons.logout,
color: Theme.of(context).colorScheme.error,
),
title: Text(
'Sign Out',
style: TextStyle(
color: Theme.of(context).colorScheme.error,
fontWeight: FontWeight.w500,
),
),
onTap: () async {
Navigator.pop(context);
final confirm = await showDialog<bool>(
context: context,
builder: (context) => AlertDialog(
title: const Text('Sign Out'),
content: const Text('Are you sure you want to sign out?'),
actions: [
TextButton(
onPressed: () => Navigator.pop(context, false),
child: const Text('Cancel'),
),
FilledButton(
onPressed: () => Navigator.pop(context, true),
style: FilledButton.styleFrom(
backgroundColor: Theme.of(context).colorScheme.error,
),
child: const Text('Sign Out'),
),
],
),
);

if (confirm == true) {
await authService.signOut();
}
},
),
const SizedBox(height: 8),
],
),
);
}

void _showSettingsSheet(BuildContext context) {
showModalBottomSheet(
context: context,
isScrollControlled: true,
builder: (context) => DraggableScrollableSheet(
initialChildSize: 0.6,
minChildSize: 0.4,
maxChildSize: 0.9,
expand: false,
builder: (context, scrollController) {
return Container(
padding: const EdgeInsets.all(20),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Row(
children: [
Text(
'Settings',
style: Theme.of(context).textTheme.headlineSmall?.copyWith(
fontWeight: FontWeight.bold,
),
),
const Spacer(),
IconButton(
icon: const Icon(Icons.close),
onPressed: () => Navigator.pop(context),
),
],
),
const SizedBox(height: 16),
Expanded(
child: ListView(
controller: scrollController,
children: [
const Text(
'General',
style: TextStyle(
fontWeight: FontWeight.bold,
fontSize: 16,
),
),
const SizedBox(height: 8),
SwitchListTile(
title: const Text('Notifications'),
subtitle: const Text('Receive app notifications'),
value: true,
onChanged: (value) {},
),
SwitchListTile(
title: const Text('Auto-sync'),
subtitle: const Text('Sync data automatically'),
value: true,
onChanged: (value) {},
),
const SizedBox(height: 16),
const Text(
'Data',
style: TextStyle(
fontWeight: FontWeight.bold,
fontSize: 16,
),
),
const SizedBox(height: 8),
ListTile(
leading: const Icon(Icons.cloud_download),
title: const Text('Backup Data'),
subtitle: const Text('Save your timezones'),
onTap: () {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(content: Text('Data backed up!')),
);
},
),
ListTile(
leading: const Icon(Icons.delete_sweep),
title: const Text('Clear Cache'),
subtitle: const Text('Free up storage space'),
onTap: () {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(content: Text('Cache cleared!')),
);
},
),
],
),
),
],
),
);
},
),
);
}

void _showHelpDialog(BuildContext context) {
showDialog(
context: context,
builder: (context) => AlertDialog(
title: const Text('Help & Support'),
content: const SingleChildScrollView(
child: Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
'How to use:',
style: TextStyle(fontWeight: FontWeight.bold),
),
SizedBox(height: 8),
Text('• Add timezones from the Add tab'),
Text('• Mark favorites by tapping the star icon'),
Text('• Delete timezones by long-pressing'),
Text('• Upgrade to Premium for unlimited features'),
SizedBox(height: 16),
Text(
'Contact:',
style: TextStyle(fontWeight: FontWeight.bold),
),
SizedBox(height: 8),
Text('Email: support@timezoneapp.com'),
Text('Website: www.timezoneapp.com'),
],
),
),
actions: [
TextButton(
onPressed: () => Navigator.pop(context),
child: const Text('Close'),
),
],
),
);
}

void _showAboutDialog(BuildContext context) {
showDialog(
context: context,
builder: (context) => AlertDialog(
title: const Text('About'),
content: const Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
'Timezone Converter',
style: TextStyle(
fontSize: 18,
fontWeight: FontWeight.bold,
),
),
SizedBox(height: 8),
Text('Version 1.0.0'),
SizedBox(height: 16),
Text(
'Convert time across different timezones with ease. Built with Flutter and Firebase.',
),
SizedBox(height: 16),
Text(
'© 2025 Timezone Converter',
style: TextStyle(fontSize: 12),
),
],
),
actions: [
TextButton(
onPressed: () => Navigator.pop(context),
child: const Text('Close'),
),
],
),
);
}
}

class TimezoneConverterHome extends StatefulWidget {
const TimezoneConverterHome({super.key});

@override
State<TimezoneConverterHome> createState() => _TimezoneConverterHomeState();
}

class _TimezoneConverterHomeState extends State<TimezoneConverterHome> {
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

String get userId => authService.currentUser?.uid ?? 'guest';

@override
Widget build(BuildContext context) {
return Column(
children: [
const TimePickerWidget(),
const Divider(height: 1),
Expanded(child: _buildTimezoneList()),
],
);
}

Widget _buildTimezoneList() {
return StreamBuilder<QuerySnapshot>(
stream: _firestore
    .collection('users')
    .doc(userId)
    .collection('timezones')
    .snapshots(),
builder: (context, snapshot) {
if (snapshot.hasError) {
return Center(child: Text('Error: ${snapshot.error}'));
}

if (snapshot.connectionState == ConnectionState.waiting) {
return const Center(child: CircularProgressIndicator());
}

if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
return Center(
child: Column(
mainAxisAlignment: MainAxisAlignment.center,
children: [
Icon(
Icons.public_off,
size: 64,
color: Theme.of(context).colorScheme.secondary,
),
const SizedBox(height: 16),
Text(
'No timezones added yet',
style: Theme.of(context).textTheme.titleLarge,
),
const SizedBox(height: 8),
Text(
'Tap the Add tab below to add your first timezone',
style: Theme.of(context).textTheme.bodyMedium,
textAlign: TextAlign.center,
),
],
),
);
}

final docs = snapshot.data!.docs;
final sortedDocs = docs.toList()..sort((a, b) {
final aData = a.data() as Map<String, dynamic>;
final bData = b.data() as Map<String, dynamic>;
final aFav = aData['isFavorite'] ?? false;
final bFav = bData['isFavorite'] ?? false;

if (aFav && !bFav) return -1;
if (!aFav && bFav) return 1;
return 0;
});

return ListView.builder(
padding: const EdgeInsets.only(bottom: 80),
itemCount: sortedDocs.length,
itemBuilder: (context, index) {
final doc = sortedDocs[index];
final data = doc.data() as Map<String, dynamic>;
return TimezoneCard(
docId: doc.id,
data: data,
onDelete: () => _deleteTimezone(doc.id),
onToggleFavorite: () => _toggleFavorite(doc.id, data),
);
},
);
},
);
}

Future<void> _toggleFavorite(String docId, Map<String, dynamic> data) async {
final currentFavorite = data['isFavorite'] ?? false;

if (!premiumManager.isPremium && !currentFavorite) {
final snapshot = await _firestore
    .collection('users')
    .doc(userId)
    .collection('timezones')
    .where('isFavorite', isEqualTo: true)
    .get();

if (snapshot.docs.length >= PremiumManager.maxFreeFavorites) {
showDialog(
context: context,
builder: (context) => AlertDialog(
title: const Row(
children: [
Icon(Icons.lock, color: Colors.amber),
SizedBox(width: 8),
Text('Limit Reached'),
],
),
content: Text(
'Free users can only have ${PremiumManager.maxFreeFavorites} favorites. Upgrade to Premium for unlimited favorites!',
),
actions: [
TextButton(
onPressed: () => Navigator.pop(context),
child: const Text('Cancel'),
),
FilledButton(
onPressed: () {
Navigator.pop(context);
if (context.findAncestorStateOfType<_MainScreenState>() != null) {
Navigator.pop(context);
Navigator.push(
context,
MaterialPageRoute(
builder: (context) => const PremiumTab(),
),
);
}
},
style: FilledButton.styleFrom(backgroundColor: Colors.amber),
child: const Text('View Premium'),
),
],
),
);
return;
}
}

try {
await _firestore
    .collection('users')
    .doc(userId)
    .collection('timezones')
    .doc(docId)
    .update({'isFavorite': !currentFavorite});
} catch (e) {
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(content: Text('Error updating favorite: $e')),
);
}
}
}

Future<void> _deleteTimezone(String docId) async {
final confirm = await showDialog<bool>(
context: context,
builder: (context) => AlertDialog(
title: const Text('Delete Timezone'),
content: const Text('Are you sure you want to delete this timezone?'),
actions: [
TextButton(
onPressed: () => Navigator.pop(context, false),
child: const Text('Cancel'),
),
FilledButton(
onPressed: () => Navigator.pop(context, true),
style: FilledButton.styleFrom(
backgroundColor: Theme.of(context).colorScheme.error,
),
child: const Text('Delete'),
),
],
),
);

if (confirm == true) {
try {
await _firestore
    .collection('users')
    .doc(userId)
    .collection('timezones')
    .doc(docId)
    .delete();

if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(content: Text('Timezone deleted')),
);
}
} catch (e) {
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(content: Text('Error deleting timezone: $e')),
);
}
}
}
}
}

class SearchTimezoneTab extends StatefulWidget {
const SearchTimezoneTab({super.key});

@override
State<SearchTimezoneTab> createState() => _SearchTimezoneTabState();
}

class _SearchTimezoneTabState extends State<SearchTimezoneTab> {
final FirebaseFirestore _firestore = FirebaseFirestore.instance;
String get userId => authService.currentUser?.uid ?? 'guest';
final TextEditingController _searchController = TextEditingController();
List<Map<String, String>> _filteredTimezones = [];

final List<Map<String, String>> _allTimezones = [
// Africa
  {'name': 'Abidjan', 'tz': 'Africa/Abidjan', 'region': 'Africa'},
  {'name': 'Accra', 'tz': 'Africa/Accra', 'region': 'Africa'},
  {'name': 'Addis Ababa', 'tz': 'Africa/Addis_Ababa', 'region': 'Africa'},
  {'name': 'Algiers', 'tz': 'Africa/Algiers', 'region': 'Africa'},
  {'name': 'Cairo', 'tz': 'Africa/Cairo', 'region': 'Africa'},
  {'name': 'Casablanca', 'tz': 'Africa/Casablanca', 'region': 'Africa'},
  {'name': 'Johannesburg', 'tz': 'Africa/Johannesburg', 'region': 'Africa'},
  {'name': 'Lagos', 'tz': 'Africa/Lagos', 'region': 'Africa'},
  {'name': 'Nairobi', 'tz': 'Africa/Nairobi', 'region': 'Africa'},
// America
  {'name': 'New York', 'tz': 'America/New_York', 'region': 'America'},
  {'name': 'Chicago', 'tz': 'America/Chicago', 'region': 'America'},
  {'name': 'Denver', 'tz': 'America/Denver', 'region': 'America'},
  {'name': 'Los Angeles', 'tz': 'America/Los_Angeles', 'region': 'America'},
  {'name': 'Mexico City', 'tz': 'America/Mexico_City', 'region': 'America'},
  {'name': 'Toronto', 'tz': 'America/Toronto', 'region': 'America'},
  {'name': 'Vancouver', 'tz': 'America/Vancouver', 'region': 'America'},
  {'name': 'Buenos Aires', 'tz': 'America/Argentina/Buenos_Aires', 'region': 'America'},
  {'name': 'Sao Paulo', 'tz': 'America/Sao_Paulo', 'region': 'America'},
// Asia
  {'name': 'Tokyo', 'tz': 'Asia/Tokyo', 'region': 'Asia'},
  {'name': 'Shanghai', 'tz': 'Asia/Shanghai', 'region': 'Asia'},
  {'name': 'Hong Kong', 'tz': 'Asia/Hong_Kong', 'region': 'Asia'},
  {'name': 'Singapore', 'tz': 'Asia/Singapore', 'region': 'Asia'},
  {'name': 'Seoul', 'tz': 'Asia/Seoul', 'region': 'Asia'},
  {'name': 'Dubai', 'tz': 'Asia/Dubai', 'region': 'Asia'},
  {'name': 'Mumbai', 'tz': 'Asia/Kolkata', 'region': 'Asia'},
  {'name': 'Bangkok', 'tz': 'Asia/Bangkok', 'region': 'Asia'},
  {'name': 'Jakarta', 'tz': 'Asia/Jakarta', 'region': 'Asia'},
// Europe
  {'name': 'London', 'tz': 'Europe/London', 'region': 'Europe'},
  {'name': 'Paris', 'tz': 'Europe/Paris', 'region': 'Europe'},
  {'name': 'Berlin', 'tz': 'Europe/Berlin', 'region': 'Europe'},
  {'name': 'Rome', 'tz': 'Europe/Rome', 'region': 'Europe'},
  {'name': 'Madrid', 'tz': 'Europe/Madrid', 'region': 'Europe'},
  {'name': 'Amsterdam', 'tz': 'Europe/Amsterdam', 'region': 'Europe'},
  {'name': 'Moscow', 'tz': 'Europe/Moscow', 'region': 'Europe'},
// Australia
  {'name': 'Sydney', 'tz': 'Australia/Sydney', 'region': 'Australia'},
  {'name': 'Melbourne', 'tz': 'Australia/Melbourne', 'region': 'Australia'},
  {'name': 'Brisbane', 'tz': 'Australia/Brisbane', 'region': 'Australia'},
  {'name': 'Perth', 'tz': 'Australia/Perth', 'region': 'Australia'},
// Pacific
  {'name': 'Auckland', 'tz': 'Pacific/Auckland', 'region': 'Pacific'},
  {'name': 'Fiji', 'tz': 'Pacific/Fiji', 'region': 'Pacific'},
  {'name': 'Honolulu', 'tz': 'Pacific/Honolulu', 'region': 'Pacific'},
];

@override
void initState() {
super.initState();
_filteredTimezones = _allTimezones;
_searchController.addListener(_filterTimezones);
}

@override
void dispose() {
_searchController.dispose();
super.dispose();
}

void _filterTimezones() {
final query = _searchController.text.toLowerCase();
setState(() {
if (query.isEmpty) {
_filteredTimezones = _allTimezones;
} else {
_filteredTimezones = _allTimezones.where((tz) {
return tz['name']!.toLowerCase().contains(query) ||
tz['tz']!.toLowerCase().contains(query);
}).toList();
}
});
}

Future<void> _addTimezone(String name, String timezone) async {
try {
await _firestore
    .collection('users')
    .doc(userId)
    .collection('timezones')
    .add({
'name': name,
'timezone': timezone,
'isFavorite': false,
'addedAt': FieldValue.serverTimestamp(),
});

if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text('$name added successfully'),
backgroundColor: Colors.green,
duration: const Duration(seconds: 2),
),
);
}
} catch (e) {
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(content: Text('Error adding timezone: $e')),
);
}
}
}

@override
Widget build(BuildContext context) {
final groupedTimezones = <String, List<Map<String, String>>>{};
for (var tz in _filteredTimezones) {
final region = tz['region']!;
groupedTimezones.putIfAbsent(region, () => []).add(tz);
}

return Scaffold(
appBar: AppBar(
title: const Text('Add Timezone'),
centerTitle: true,
elevation: 2,
),
body: Column(
children: [
Padding(
padding: const EdgeInsets.all(16),
child: TextField(
controller: _searchController,
decoration: InputDecoration(
hintText: 'Search cities or timezones...',
prefixIcon: const Icon(Icons.search),
suffixIcon: _searchController.text.isNotEmpty
? IconButton(
icon: const Icon(Icons.clear),
onPressed: () {
_searchController.clear();
},
)
    : null,
border: OutlineInputBorder(
borderRadius: BorderRadius.circular(12),
),
filled: true,
),
),
),
Expanded(
child: _searchController.text.isNotEmpty
? _buildSearchResults()
    : _buildGroupedTimezones(groupedTimezones),
),
],
),
);
}

Widget _buildSearchResults() {
if (_filteredTimezones.isEmpty) {
return Center(
child: Column(
mainAxisAlignment: MainAxisAlignment.center,
children: [
Icon(
Icons.search_off,
size: 64,
color: Theme.of(context).colorScheme.secondary,
),
const SizedBox(height: 16),
Text(
'No timezones found',
style: Theme.of(context).textTheme.titleLarge,
),
const SizedBox(height: 8),
Text(
'Try a different search term',
style: Theme.of(context).textTheme.bodyMedium,
),
],
),
);
}

return ListView.builder(
itemCount: _filteredTimezones.length,
itemBuilder: (context, index) {
final tz = _filteredTimezones[index];
return _buildTimezoneListTile(tz);
},
);
}

Widget _buildGroupedTimezones(Map<String, List<Map<String, String>>> groupedTimezones) {
final sortedRegions = groupedTimezones.keys.toList()..sort();

return ListView.builder(
itemCount: sortedRegions.length,
itemBuilder: (context, index) {
final region = sortedRegions[index];
final timezones = groupedTimezones[region]!;

return Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Padding(
padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
child: Text(
region,
style: Theme.of(context).textTheme.titleMedium?.copyWith(
fontWeight: FontWeight.bold,
color: Theme.of(context).colorScheme.primary,
),
),
),
...timezones.map((tz) => _buildTimezoneListTile(tz)).toList(),
],
);
},
);
}

Widget _buildTimezoneListTile(Map<String, String> tz) {
return Card(
margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
child: ListTile(
leading: CircleAvatar(
backgroundColor: Theme.of(context).colorScheme.primaryContainer,
child: Icon(
Icons.public,
color: Theme.of(context).colorScheme.onPrimaryContainer,
),
),
title: Text(
tz['name']!,
style: const TextStyle(fontWeight: FontWeight.bold),
),
subtitle: Text(
tz['tz']!,
style: TextStyle(
fontSize: 12,
color: Theme.of(context).colorScheme.onSurfaceVariant,
),
),
trailing: IconButton(
icon: const Icon(Icons.add_circle),
color: Theme.of(context).colorScheme.primary,
onPressed: () {
_addTimezone(tz['name']!, tz['tz']!);
},
tooltip: 'Add timezone',
),
),
);
}
}

// Premium Tab
class PremiumTab extends StatefulWidget {
const PremiumTab({super.key});

@override
State<PremiumTab> createState() => _PremiumTabState();
}

class _PremiumTabState extends State<PremiumTab> {
@override
Widget build(BuildContext context) {
return Scaffold(
appBar: AppBar(
title: const Text('Premium'),
centerTitle: true,
elevation: 2,
),
body: AnimatedBuilder(
animation: premiumManager,
builder: (context, child) {
if (premiumManager.isPremium) {
return _buildPremiumActive();
} else {
return _buildUpgradeScreen();
}
},
),
);
}

Widget _buildUpgradeScreen() {
return SingleChildScrollView(
padding: const EdgeInsets.all(24),
child: Column(
children: [
Container(
padding: const EdgeInsets.all(32),
decoration: BoxDecoration(
gradient: const LinearGradient(
colors: [Colors.amber, Colors.orange],
begin: Alignment.topLeft,
end: Alignment.bottomRight,
),
borderRadius: BorderRadius.circular(24),
),
child: const Column(
children: [
Icon(Icons.star, color: Colors.white, size: 80),
SizedBox(height: 16),
Text(
'Upgrade to Premium',
style: TextStyle(
color: Colors.white,
fontSize: 28,
fontWeight: FontWeight.bold,
),
),
SizedBox(height: 8),
Text(
'Unlock all premium features',
style: TextStyle(
color: Colors.white70,
fontSize: 16,
),
),
],
),
),
const SizedBox(height: 32),
_buildFeatureCard(
Icons.star,
'Unlimited Favorites',
'Mark unlimited timezones as favorites',
'Free: Limited to 5 favorites',
),
const SizedBox(height: 16),
_buildFeatureCard(
Icons.palette,
'Custom Themes',
'Choose from 10 beautiful color themes',
'Personalize your experience',
),
const SizedBox(height: 16),
_buildFeatureCard(
Icons.brightness_6,
'Theme Mode',
'Switch between Light, Dark, and System modes',
'Customize to your preference',
),
const SizedBox(height: 16),
_buildFeatureCard(
Icons.apps,
'Custom Icons',
'Choose from 6 different icon styles',
'Make it truly yours',
),
const SizedBox(height: 16),
_buildFeatureCard(
Icons.sync,
'Cloud Sync',
'Your timezones sync across all devices',
'Never lose your data',
),
const SizedBox(height: 16),
_buildFeatureCard(
Icons.notifications_off,
'Ad-Free Experience',
'Enjoy the app without any interruptions',
'Focus on what matters',
),
const SizedBox(height: 32),
Container(
padding: const EdgeInsets.all(20),
decoration: BoxDecoration(
color: Theme.of(context).colorScheme.surfaceVariant,
borderRadius: BorderRadius.circular(16),
),
child: Column(
children: [
const Text(
'One-time Payment',
style: TextStyle(
fontSize: 16,
fontWeight: FontWeight.w600,
),
),
const SizedBox(height: 8),
const Text(
'\$4.99',
style: TextStyle(
fontSize: 48,
fontWeight: FontWeight.bold,
),
),
const SizedBox(height: 4),
Text(
'Lifetime access to all premium features',
style: TextStyle(
color: Theme.of(context).colorScheme.onSurfaceVariant,
),
),
],
),
),
const SizedBox(height: 24),
SizedBox(
width: double.infinity,
height: 56,
child: FilledButton(
onPressed: () {
_activatePremium();
},
style: FilledButton.styleFrom(
backgroundColor: Colors.amber,
foregroundColor: Colors.black,
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(16),
),
),
child: const Row(
mainAxisAlignment: MainAxisAlignment.center,
children: [
Icon(Icons.star, size: 24),
SizedBox(width: 8),
Text(
'Upgrade Now',
style: TextStyle(
fontSize: 18,
fontWeight: FontWeight.bold,
),
),
],
),
),
),
const SizedBox(height: 16),
Text(
'No subscription • Pay once, use forever',
style: TextStyle(
color: Theme.of(context).colorScheme.onSurfaceVariant,
fontSize: 12,
),
),
const SizedBox(height: 8),
TextButton(
onPressed: () {
_showFeaturesComparison();
},
child: const Text('Compare Free vs Premium'),
),
],
),
);
}

Widget _buildFeatureCard(IconData icon, String title, String description, String benefit) {
return Card(
child: Padding(
padding: const EdgeInsets.all(16),
child: Row(
children: [
Container(
padding: const EdgeInsets.all(12),
decoration: BoxDecoration(
color: Theme.of(context).colorScheme.primaryContainer,
borderRadius: BorderRadius.circular(12),
),
child: Icon(
icon,
color: Theme.of(context).colorScheme.onPrimaryContainer,
size: 32,
),
),
const SizedBox(width: 16),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
title,
style: const TextStyle(
fontSize: 16,
fontWeight: FontWeight.bold,
),
),
const SizedBox(height: 4),
Text(
description,
style: TextStyle(
color: Theme.of(context).colorScheme.onSurfaceVariant,
),
),
const SizedBox(height: 4),
Text(
benefit,
style: TextStyle(
fontSize: 12,
color: Colors.amber[700],
fontStyle: FontStyle.italic,
),
),
],
),
),
],
),
),
);
}

Widget _buildPremiumActive() {
final user = authService.currentUser;

return SingleChildScrollView(
padding: const EdgeInsets.all(24),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Container(
padding: const EdgeInsets.all(20),
decoration: BoxDecoration(
gradient: const LinearGradient(
colors: [Colors.amber, Colors.orange],
),
borderRadius: BorderRadius.circular(16),
),
child: Row(
children: [
const Icon(Icons.star, color: Colors.white, size: 40),
const SizedBox(width: 16),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
const Text(
'Premium Active',
style: TextStyle(
color: Colors.white,
fontSize: 20,
fontWeight: FontWeight.bold,
),
),
Text(
'Thank you for your support!',
style: TextStyle(
color: Colors.white.withOpacity(0.9),
),
),
],
),
),
],
),
),
const SizedBox(height: 24),
Card(
child: Padding(
padding: const EdgeInsets.all(20),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Row(
children: [
CircleAvatar(
backgroundColor: Theme.of(context).colorScheme.primaryContainer,
child: Icon(
Icons.person,
color: Theme.of(context).colorScheme.onPrimaryContainer,
),
),
const SizedBox(width: 12),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
user?.displayName ?? user?.email ?? 'Premium User',
style: const TextStyle(
fontSize: 16,
fontWeight: FontWeight.bold,
),
),
const Text(
'Premium Member',
style: TextStyle(
fontSize: 12,
color: Colors.amber,
),
),
],
),
),
],
),
const SizedBox(height: 16),
const Divider(),
const SizedBox(height: 16),
_buildPremiumFeatureItem(Icons.check_circle, 'Unlimited Favorites', true),
_buildPremiumFeatureItem(Icons.check_circle, 'Custom Themes', true),
_buildPremiumFeatureItem(Icons.check_circle, 'Theme Modes', true),
_buildPremiumFeatureItem(Icons.check_circle, 'Custom Icons', true),
_buildPremiumFeatureItem(Icons.check_circle, 'Cloud Sync', true),
_buildPremiumFeatureItem(Icons.check_circle, 'Ad-Free', true),
],
),
),
),
const SizedBox(height: 32),
Text(
'Customization',
style: Theme.of(context).textTheme.titleLarge?.copyWith(
fontWeight: FontWeight.bold,
),
),
const SizedBox(height: 16),
Card(
child: ListTile(
leading: const Icon(Icons.brightness_6),
title: const Text('Theme Mode'),
subtitle: Text(_getThemeModeText()),
trailing: const Icon(Icons.chevron_right),
onTap: _showThemeModeDialog,
),
),
const SizedBox(height: 8),
Card(
child: ListTile(
leading: Icon(Icons.palette, color: themeManager.seedColor),
title: const Text('Theme Color'),
subtitle: const Text('Customize app colors'),
trailing: const Icon(Icons.chevron_right),
onTap: _showColorPicker,
),
),
const SizedBox(height: 8),
Card(
child: ListTile(
leading: Icon(_getIconData(themeManager.selectedIcon)),
title: const Text('Icon Style'),
subtitle: const Text('Change timezone icons'),
trailing: const Icon(Icons.chevron_right),
onTap: _showIconPicker,
),
),
const SizedBox(height: 32),
Center(
child: TextButton.icon(
onPressed: () {
showDialog(
context: context,
builder: (context) => AlertDialog(
title: const Text('Deactivate Premium'),
content: const Text(
'This is a demo feature. In production, premium would be permanent.\n\nDeactivate premium for testing?',
),
actions: [
TextButton(
onPressed: () => Navigator.pop(context),
child: const Text('Cancel'),
),
FilledButton(
onPressed: () {
premiumManager.setPremium(false);
Navigator.pop(context);
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text('Premium deactivated (Demo)'),
),
);
},
child: const Text('Deactivate'),
),
],
),
);
},
icon: const Icon(Icons.logout),
label: const Text('Deactivate Premium (Demo Only)'),
),
),
],
),
);
}

Widget _buildPremiumFeatureItem(IconData icon, String title, bool isActive) {
return Padding(
padding: const EdgeInsets.symmetric(vertical: 8),
child: Row(
children: [
Icon(
icon,
color: isActive ? Colors.green : Colors.grey,
size: 20,
),
const SizedBox(width: 12),
Text(
title,
style: TextStyle(
fontSize: 14,
color: isActive ? null : Colors.grey,
),
),
],
),
);
}

void _showFeaturesComparison() {
showDialog(
context: context,
builder: (context) => AlertDialog(
title: const Text('Free vs Premium'),
content: SingleChildScrollView(
child: Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.start,
children: [
_buildComparisonRow('Favorites', '5', 'Unlimited'),
_buildComparisonRow('Themes', '1', '10'),
_buildComparisonRow('Theme Modes', '❌', '✅'),
_buildComparisonRow('Custom Icons', '❌', '✅'),
_buildComparisonRow('Cloud Sync', '✅', '✅'),
_buildComparisonRow('Ads', 'Some', 'None'),
],
),
),
actions: [
TextButton(
onPressed: () => Navigator.pop(context),
child: const Text('Close'),
),
FilledButton(
onPressed: () {
Navigator.pop(context);
_activatePremium();
},
style: FilledButton.styleFrom(
backgroundColor: Colors.amber,
foregroundColor: Colors.black,
),
child: const Text('Upgrade'),
),
],
),
);
}

Widget _buildComparisonRow(String feature, String free, String premium) {
return Padding(
padding: const EdgeInsets.symmetric(vertical: 8),
child: Row(
children: [
Expanded(
flex: 2,
child: Text(
feature,
style: const TextStyle(fontWeight: FontWeight.bold),
),
),
Expanded(
child: Text(
free,
textAlign: TextAlign.center,
style: const TextStyle(color: Colors.grey),
),
),
Expanded(
child: Text(
premium,
textAlign: TextAlign.center,
style: const TextStyle(
color: Colors.amber,
fontWeight: FontWeight.bold,
),
),
),
],
),
);
}

void _activatePremium() {
showDialog(
context: context,
builder: (context) => AlertDialog(
title: const Row(
children: [
Icon(Icons.star, color: Colors.amber),
SizedBox(width: 8),
Text('Confirm Purchase'),
],
),
content: const Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
'This is a demo. In production, this would process a real payment.\n',
style: TextStyle(fontStyle: FontStyle.italic),
),
Text('Premium Features:', style: TextStyle(fontWeight: FontWeight.bold)),
SizedBox(height: 8),
Text('• Unlimited favorites'),
Text('• 10 color themes'),
Text('• Light/Dark/System modes'),
Text('• 6 icon styles'),
Text('• Ad-free experience'),
SizedBox(height: 16),
Text(
'One-time payment: \$4.99',
style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
),
],
),
actions: [
TextButton(
onPressed: () => Navigator.pop(context),
child: const Text('Cancel'),
),
FilledButton(
onPressed: () {
premiumManager.setPremium(true);
Navigator.pop(context);
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text('🎉 Premium activated! Enjoy all features.'),
backgroundColor: Colors.green,
duration: Duration(seconds: 3),
),
);
},
style: FilledButton.styleFrom(
backgroundColor: Colors.amber,
foregroundColor: Colors.black,
),
child: const Text('Activate Premium'),
),
],
),
);
}

String _getThemeModeText() {
switch (themeManager.themeMode) {
case ThemeMode.light:
return 'Light';
case ThemeMode.dark:
return 'Dark';
case ThemeMode.system:
return 'System Default';
}
}

void _showThemeModeDialog() {
showDialog(
context: context,
builder: (context) {
return AlertDialog(
title: const Text('Select Theme Mode'),
content: Column(
mainAxisSize: MainAxisSize.min,
children: [
RadioListTile<ThemeMode>(
title: const Text('Light'),
value: ThemeMode.light,
groupValue: themeManager.themeMode,
onChanged: (value) {
themeManager.setThemeMode(value!);
Navigator.pop(context);
},
),
RadioListTile<ThemeMode>(
title: const Text('Dark'),
value: ThemeMode.dark,
groupValue: themeManager.themeMode,
onChanged: (value) {
themeManager.setThemeMode(value!);
Navigator.pop(context);
},
),
RadioListTile<ThemeMode>(
title: const Text('System Default'),
value: ThemeMode.system,
groupValue: themeManager.themeMode,
onChanged: (value) {
themeManager.setThemeMode(value!);
Navigator.pop(context);
},
),
],
),
);
},
);
}

void _showColorPicker() {
final colors = [
Colors.blue,
Colors.red,
Colors.green,
Colors.purple,
Colors.orange,
Colors.teal,
Colors.pink,
Colors.indigo,
Colors.amber,
Colors.cyan,
];

showDialog(
context: context,
builder: (context) {
return AlertDialog(
title: const Text('Select Theme Color'),
content: Wrap(
spacing: 12,
runSpacing: 12,
children: colors.map((color) {
return InkWell(
onTap: () {
themeManager.setSeedColor(color);
Navigator.pop(context);
},
child: Container(
width: 50,
height: 50,
decoration: BoxDecoration(
color: color,
shape: BoxShape.circle,
border: Border.all(
color: themeManager.seedColor == color
? Colors.white
    : Colors.transparent,
width: 3,
),
),
child: themeManager.seedColor == color
? const Icon(Icons.check, color: Colors.white)
    : null,
),
);
}).toList(),
),
);
},
);
}

void _showIconPicker() {
final icons = {
'public': Icons.public,
'language': Icons.language,
'schedule': Icons.schedule,
'access_time': Icons.access_time,
'travel_explore': Icons.travel_explore,
'location_on': Icons.location_on,
};

showDialog(
context: context,
builder: (context) {
return AlertDialog(
title: const Text('Select Icon Style'),
content: Column(
mainAxisSize: MainAxisSize.min,
children: icons.entries.map((entry) {
return RadioListTile<String>(
title: Row(
children: [
Icon(entry.value),
const SizedBox(width: 12),
Text(entry.key),
],
),
value: entry.key,
groupValue: themeManager.selectedIcon,
onChanged: (value) {
themeManager.setIcon(value!);
Navigator.pop(context);
},
);
}).toList(),
),
);
},
);
}

IconData _getIconData(String iconName) {
final icons = {
'public': Icons.public,
'language': Icons.language,
'schedule': Icons.schedule,
'access_time': Icons.access_time,
'travel_explore': Icons.travel_explore,
'location_on': Icons.location_on,
};
return icons[iconName] ?? Icons.public;
}
}

// Profile Tab - Simplified version
class ProfileTab extends StatefulWidget {
const ProfileTab({super.key});

@override
State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
@override
Widget build(BuildContext context) {
final user = authService.currentUser;
final isAnonymous = user?.isAnonymous ?? false;

return Scaffold(
appBar: AppBar(
title: const Text('Profile'),
centerTitle: true,
elevation: 2,
),
body: SingleChildScrollView(
padding: const EdgeInsets.all(24),
child: Column(
children: [
CircleAvatar(
radius: 50,
backgroundColor: Theme.of(context).colorScheme.primaryContainer,
child: user?.photoURL != null
? ClipOval(
child: Image.network(
user!.photoURL!,
width: 100,
height: 100,
fit: BoxFit.cover,
errorBuilder: (context, error, stackTrace) {
return Icon(
isAnonymous ? Icons.person_outline : Icons.person,
size: 50,
color: Theme.of(context).colorScheme.onPrimaryContainer,
);
},
),
)
    : Icon(
isAnonymous ? Icons.person_outline : Icons.person,
size: 50,
color: Theme.of(context).colorScheme.onPrimaryContainer,
),
),
const SizedBox(height: 16),
Text(
isAnonymous ? 'Guest User' : (user?.displayName ?? 'User'),
style: Theme.of(context).textTheme.headlineSmall?.copyWith(
fontWeight: FontWeight.bold,
),
),
if (!isAnonymous && user?.email != null) ...[
const SizedBox(height: 4),
Text(
user!.email!,
style: Theme.of(context).textTheme.bodyMedium?.copyWith(
color: Theme.of(context).colorScheme.onSurfaceVariant,
),
),
],
if (!isAnonymous && user?.phoneNumber != null) ...[
const SizedBox(height: 4),
Text(
user!.phoneNumber!,
style: Theme.of(context).textTheme.bodyMedium?.copyWith(
color: Theme.of(context).colorScheme.onSurfaceVariant,
),
),
],
const SizedBox(height: 8),
AnimatedBuilder(
animation: premiumManager,
builder: (context, child) {
if (premiumManager.isPremium) {
return Container(
padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
decoration: BoxDecoration(
gradient: const LinearGradient(
colors: [Colors.amber, Colors.orange],
),
borderRadius: BorderRadius.circular(20),
),
child: const Row(
mainAxisSize: MainAxisSize.min,
children: [
Icon(Icons.star, color: Colors.white, size: 16),
SizedBox(width: 4),
Text(
'Premium Member',
style: TextStyle(
color: Colors.white,
fontWeight: FontWeight.bold,
),
),
],
),
);
}
return const SizedBox.shrink();
},
),
const SizedBox(height: 32),
Card(
child: Column(
children: [
ListTile(
leading: const Icon(Icons.person),
title: const Text('Account Type'),
subtitle: Text(isAnonymous ? 'Guest Account' : 'Registered Account'),
trailing: isAnonymous
? TextButton(
onPressed: () {
_showConvertAccountDialog();
},
child: const Text('Upgrade'),
)
    : null,
),
const Divider(height: 1),
ListTile(
leading: const Icon(Icons.star_outline),
title: const Text('Premium Status'),
subtitle: AnimatedBuilder(
animation: premiumManager,
builder: (context, child) {
return Text(
premiumManager.isPremium ? 'Active' : 'Free',
style: TextStyle(
color: premiumManager.isPremium ? Colors.amber : null,
),
);
},
),
trailing: const Icon(Icons.chevron_right),
onTap: () {
// Navigate to premium tab
if (context.findAncestorStateOfType<_MainScreenState>() != null) {
context.findAncestorStateOfType<_MainScreenState>()!.setState(() {
context.findAncestorStateOfType<_MainScreenState>()!._currentIndex = 2;
});
}
},
),
],
),
),
const SizedBox(height: 16),
Card(
child: Column(
children: [
ListTile(
leading: const Icon(Icons.help_outline),
title: const Text('Help & Support'),
trailing: const Icon(Icons.chevron_right),
onTap: () {
_showHelpDialog();
},
),
const Divider(height: 1),
ListTile(
leading: const Icon(Icons.privacy_tip_outlined),
title: const Text('Privacy Policy'),
trailing: const Icon(Icons.chevron_right),
onTap: () {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(content: Text('Privacy Policy')),
);
},
),
const Divider(height: 1),
ListTile(
leading: const Icon(Icons.info_outline),
title: const Text('About'),
trailing: const Icon(Icons.chevron_right),
onTap: () {
_showAboutDialog();
},
),
],
),
),
const SizedBox(height: 16),
Card(
child: ListTile(
leading: Icon(
Icons.logout,
color: Theme.of(context).colorScheme.error,
),
title: Text(
'Sign Out',
style: TextStyle(
color: Theme.of(context).colorScheme.error,
),
),
onTap: () async {
final confirm = await showDialog<bool>(
context: context,
builder: (context) => AlertDialog(
title: const Text('Sign Out'),
content: const Text('Are you sure you want to sign out?'),
actions: [
TextButton(
onPressed: () => Navigator.pop(context, false),
child: const Text('Cancel'),
),
FilledButton(
onPressed: () => Navigator.pop(context, true),
style: FilledButton.styleFrom(
backgroundColor: Theme.of(context).colorScheme.error,
),
child: const Text('Sign Out'),
),
],
),
);

if (confirm == true) {
await authService.signOut();
}
},
),
),
],
),
),
);
}

void _showConvertAccountDialog() {
showDialog(
context: context,
builder: (context) => AlertDialog(
title: const Text('Upgrade Account'),
content: const Text(
'Convert your guest account to a permanent account by linking an email or phone number.\n\nThis will preserve all your data.',
),
actions: [
TextButton(
onPressed: () => Navigator.pop(context),
child: const Text('Later'),
),
FilledButton(
onPressed: () {
Navigator.pop(context);
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text('Account conversion coming soon!'),
),
);
},
child: const Text('Upgrade'),
),
],
),
);
}

void _showHelpDialog() {
showDialog(
context: context,
builder: (context) => AlertDialog(
title: const Text('Help & Support'),
content: const SingleChildScrollView(
child: Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
'How to use:',
style: TextStyle(fontWeight: FontWeight.bold),
),
SizedBox(height: 8),
Text('• Add timezones from the Add tab'),
Text('• Mark favorites by tapping the star icon'),
Text('• Delete timezones by long-pressing'),
Text('• Upgrade to Premium for unlimited features'),
SizedBox(height: 16),
Text(
'Contact:',
style: TextStyle(fontWeight: FontWeight.bold),
),
SizedBox(height: 8),
Text('Email: support@timezoneapp.com'),
],
),
),
actions: [
TextButton(
onPressed: () => Navigator.pop(context),
child: const Text('Close'),
),
],
),
);
}

void _showAboutDialog() {
showDialog(
context: context,
builder: (context) => AlertDialog(
title: const Text('About'),
content: const Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
'Timezone Converter',
style: TextStyle(
fontSize: 18,
fontWeight: FontWeight.bold,
),
),
SizedBox(height: 8),
Text('Version 1.0.0'),
SizedBox(height: 16),
Text(
'Convert time across different timezones with ease. Built with Flutter and Firebase.',
),
],
),
actions: [
TextButton(
onPressed: () => Navigator.pop(context),
child: const Text('Close'),
),
],
),
);
}
}

extension on _MainScreenState {
set _currentIndex(int _currentIndex) {}
}

// Time Picker Widget
class TimePickerWidget extends StatefulWidget {
const TimePickerWidget({super.key});

@override
State<TimePickerWidget> createState() => _TimePickerWidgetState();
}

class _TimePickerWidgetState extends State<TimePickerWidget> {
late DateTime currentTime;
Timer? _timer;

@override
void initState() {
super.initState();
currentTime = DateTime.now();
_timer = Timer.periodic(const Duration(seconds: 1), (timer) {
setState(() {
currentTime = DateTime.now();
});
});
}

@override
void dispose() {
_timer?.cancel();
super.dispose();
}

@override
Widget build(BuildContext context) {
return Container(
padding: const EdgeInsets.all(20),
child: Column(
children: [
Text(
'Current Time',
style: Theme.of(context).textTheme.titleMedium,
),
const SizedBox(height: 12),
Card(
elevation: 0,
color: Theme.of(context).colorScheme.surfaceVariant,
child: Padding(
padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
child: Row(
mainAxisSize: MainAxisSize.min,
children: [
Icon(
Icons.access_time,
color: Theme.of(context).colorScheme.primary,
),
const SizedBox(width: 12),
Text(
DateFormat('hh:mm:ss a').format(currentTime),
style: Theme.of(context).textTheme.headlineSmall?.copyWith(
fontWeight: FontWeight.bold,
),
),
],
),
),
),
const SizedBox(height: 8),
Text(
DateFormat('EEEE, MMMM d, yyyy').format(currentTime),
style: Theme.of(context).textTheme.bodyMedium?.copyWith(
color: Theme.of(context).colorScheme.onSurfaceVariant,
),
),
],
),
);
}
}

// Timezone Card Widget
class TimezoneCard extends StatefulWidget {
final String docId;
final Map<String, dynamic> data;
final VoidCallback onDelete;
final VoidCallback onToggleFavorite;

const TimezoneCard({
super.key,
required this.docId,
required this.data,
required this.onDelete,
required this.onToggleFavorite,
});

@override
State<TimezoneCard> createState() => _TimezoneCardState();
}

class _TimezoneCardState extends State<TimezoneCard> {
late DateTime currentTime;
Timer? _timer;

@override
void initState() {
super.initState();
currentTime = DateTime.now();
_timer = Timer.periodic(const Duration(seconds: 1), (timer) {
setState(() {
currentTime = DateTime.now();
});
});
}

@override
void dispose() {
_timer?.cancel();
super.dispose();
}

IconData _getIconData(String iconName) {
final icons = {
'public': Icons.public,
'language': Icons.language,
'schedule': Icons.schedule,
'access_time': Icons.access_time,
'travel_explore': Icons.travel_explore,
'location_on': Icons.location_on,
};
return icons[iconName] ?? Icons.public;
}

@override
Widget build(BuildContext context) {
final timezoneName = widget.data['timezone'] as String;
final location = tz.getLocation(timezoneName);
final convertedTime = tz.TZDateTime.from(currentTime, location);
final isFavorite = widget.data['isFavorite'] ?? false;

final now = tz.TZDateTime.now(location);
final offset = now.timeZoneOffset;
final offsetHours = offset.inHours;
final offsetMinutes = offset.inMinutes.remainder(60);
final offsetString = 'GMT${offsetHours >= 0 ? '+' : ''}$offsetHours${offsetMinutes != 0 ? ':${offsetMinutes.abs().toString().padLeft(2, '0')}' : ''}';

return Card(
margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
elevation: isFavorite ? 4 : 1,
child: ListTile(
contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
leading: CircleAvatar(
backgroundColor: Theme.of(context).colorScheme.primaryContainer,
child: Icon(
_getIconData(themeManager.selectedIcon),
color: Theme.of(context).colorScheme.onPrimaryContainer,
),
),
title: Row(
children: [
Expanded(
child: Text(
widget.data['name'] as String,
style: const TextStyle(fontWeight: FontWeight.bold),
),
),
IconButton(
icon: Icon(
isFavorite ? Icons.star : Icons.star_border,
color: isFavorite ? Colors.amber : null,
),
onPressed: widget.onToggleFavorite,
tooltip: 'Toggle Favorite',
),
],
),
subtitle: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
const SizedBox(height: 4),
Text(offsetString),
Text(
timezoneName,
style: TextStyle(
fontSize: 11,
color: Theme.of(context).colorScheme.onSurfaceVariant,
),
),
],
),
trailing: Column(
mainAxisAlignment: MainAxisAlignment.center,
crossAxisAlignment: CrossAxisAlignment.end,
children: [
Text(
DateFormat('hh:mm:ss a').format(convertedTime),
style: Theme.of(context).textTheme.titleMedium?.copyWith(
fontWeight: FontWeight.bold,
color: Theme.of(context).colorScheme.primary,
),
),
Text(
DateFormat('MMM d').format(convertedTime),
style: Theme.of(context).textTheme.bodySmall,
),
],
),
onLongPress: widget.onDelete,
),
);
}
}