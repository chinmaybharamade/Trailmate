import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/constants.dart';

/// User model
class UserModel {
  final String id;
  final String name;
  final String email;
  final String? avatar;
  final String? phone;
  final int trips;
  final int kmTravelled;
  final int badges;
  final String title;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.avatar,
    this.phone,
    this.trips = 0,
    this.kmTravelled = 0,
    this.badges = 0,
    this.title = 'Novice Traveler',
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['_id'] ?? json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      avatar: json['avatar'],
      phone: json['phone'],
      trips: json['trips'] ?? 0,
      kmTravelled: json['kmTravelled'] ?? 0,
      badges: json['badges'] ?? 0,
      title: json['title'] ?? 'Novice Traveler',
    );
  }
}

/// Authentication Service
///
/// Handles registration, login, token storage, and auto-login.
class AuthService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String? _token;
  UserModel? _currentUser;

  String? get token => _token;
  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _token != null;

  /// Get authorization headers
  Map<String, String> get authHeaders => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  String? _verificationId;

  /// Send OTP to a phone number using Firebase
  Future<void> sendOtp(
    String phone, {
    required Function(String) onCodeSent,
    required Function(String) onFailed,
  }) async {
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) {},
        verificationFailed: (FirebaseAuthException e) {
          debugPrint('Firebase Auth Error: ${e.message}');
          onFailed(e.message ?? 'Verification failed');
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
      );
    } catch (e) {
      debugPrint('Send OTP error: $e');
      onFailed(e.toString());
    }
  }

  /// Verify OTP using Firebase
  Future<bool> verifyOtp(String otp) async {
    if (_verificationId == null) return false;
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      // At this point, the user is signed in to Firebase.
      return true;
    } catch (e) {
      debugPrint('Verify OTP error: $e');
      return false;
    }
  }

  /// Register a new user
  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String otp,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.serverBaseUrl}/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'email': email,
          'phone': phone,
          'password': password,
          'otp': otp,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        _token = data['token'];
        _currentUser = UserModel.fromJson(data['user']);
        await _saveCredentials();
        return {'success': true, 'user': _currentUser};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Registration failed'};
      }
    } catch (e) {
      debugPrint('Register error: $e');
      return {'success': false, 'error': 'Network error. Is the server running?'};
    }
  }

  /// Login with email/phone and password
  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.serverBaseUrl}/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'identifier': identifier,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        _token = data['token'];
        _currentUser = UserModel.fromJson(data['user']);
        await _saveCredentials();
        return {'success': true, 'user': _currentUser};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Login failed'};
      }
    } catch (e) {
      debugPrint('Login error: $e');
      return {'success': false, 'error': 'Network error. Is the server running?'};
    }
  }

  /// Try to restore session from secure storage
  Future<bool> tryAutoLogin() async {
    try {
      _token = await _storage.read(key: AppConstants.tokenKey);
      if (_token == null) return false;

      // Also restore user info from storage so the app is usable even if
      // the server is unreachable (e.g. offline or server cold-starting).
      final storedId    = await _storage.read(key: AppConstants.userIdKey);
      final storedName  = await _storage.read(key: AppConstants.userNameKey);
      final storedEmail = await _storage.read(key: AppConstants.userEmailKey);
      if (storedId != null && storedName != null && storedEmail != null) {
        _currentUser = UserModel(
          id: storedId,
          name: storedName,
          email: storedEmail,
          phone: '',
          trips: 0,
          kmTravelled: 0,
          badges: 0,
          title: 'Novice Traveler',
        );
      }

      // Try to verify token & refresh user profile from server.
      // If the server is unreachable (timeout / network error), keep the
      // locally-stored token/user — the user stays logged in.
      try {
        final response = await http.get(
          Uri.parse('${AppConstants.serverBaseUrl}${AppConstants.profileEndpoint}'),
          headers: authHeaders,
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          _currentUser = UserModel.fromJson(data['user']);
          await _saveCredentials(); // refresh stored name/email
          return true;
        } else if (response.statusCode == 401) {
          // Token is genuinely invalid/expired — clear session
          await logout();
          return false;
        }
        // Any other HTTP error (5xx etc.) — keep token, return true
        return _currentUser != null;
      } catch (networkError) {
        // Network timeout or no connectivity — keep token & cached user
        debugPrint('Auto-login: server unreachable, using cached session: $networkError');
        return _currentUser != null;
      }
    } catch (e) {
      debugPrint('Auto-login error: $e');
      return false;
    }
  }

  /// Logout — clear token and user data
  Future<void> logout() async {
    _token = null;
    _currentUser = null;
    await _storage.deleteAll();
  }

  /// Save credentials to secure storage
  Future<void> _saveCredentials() async {
    if (_token != null) {
      await _storage.write(key: AppConstants.tokenKey, value: _token);
    }
    if (_currentUser != null) {
      await _storage.write(key: AppConstants.userIdKey, value: _currentUser!.id);
      await _storage.write(key: AppConstants.userNameKey, value: _currentUser!.name);
      await _storage.write(key: AppConstants.userEmailKey, value: _currentUser!.email);
    }
  }

  static bool _googleSignInInitialized = false;

  /// Ensure GoogleSignIn is initialized exactly once (required by v7.x API).
  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) return;
    await GoogleSignIn.instance.initialize(
      serverClientId: '876773622898-s8godvt47lb0omfnnguog8vko0bed0k6.apps.googleusercontent.com',
    );
    _googleSignInInitialized = true;
  }

  /// Login with Google
  Future<Map<String, dynamic>> loginWithGoogle() async {
    try {
      await _ensureGoogleSignInInitialized();
      
      final GoogleSignInAccount googleUser = await GoogleSignIn.instance.authenticate(
        scopeHint: ['email'],
      );

      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null) {
        return {'success': false, 'error': 'Failed to get Google ID token'};
      }

      final response = await http.post(
        Uri.parse('${AppConstants.serverBaseUrl}/api/auth/google'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'idToken': idToken,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        _token = data['token'];
        _currentUser = UserModel.fromJson(data['user']);
        await _saveCredentials();
        return {'success': true, 'user': _currentUser};
      } else if (response.statusCode == 202) {
        return {
          'success': true,
          'requiresPhone': true,
          'googleData': data['googleData'],
          'idToken': idToken,
        };
      } else {
        return {'success': false, 'error': data['error'] ?? 'Google login failed'};
      }
    } on GoogleSignInException catch (e) {
      debugPrint('Google Sign-In exception: ${e.code} - $e');
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return {'success': false, 'error': 'Sign in aborted'};
      }
      return {'success': false, 'error': 'Google Sign-In failed: ${e.code}'};
    } catch (e) {
      debugPrint('Google Login error: $e');
      return {'success': false, 'error': 'Failed to connect. Please try again.'};
    }
  }

  /// Register a new user with Google ID Token and Phone Number
  Future<Map<String, dynamic>> registerWithGoogle({
    required String idToken,
    required String phone,
    required String otp,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.serverBaseUrl}/api/auth/register-google'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'idToken': idToken,
          'phone': phone,
          'otp': otp,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        _token = data['token'];
        _currentUser = UserModel.fromJson(data['user']);
        await _saveCredentials();
        return {'success': true, 'user': _currentUser};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Registration failed'};
      }
    } catch (e) {
      debugPrint('Register Google error: $e');
      return {'success': false, 'error': 'Network error. Is the server running?'};
    }
  }
}
