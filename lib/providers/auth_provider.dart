import 'package:flutter/material.dart';
import '../services/auth_service.dart';

/// Auth state management using ChangeNotifier (Provider pattern)
class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _isInitialized = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  bool get isLoggedIn => _authService.isLoggedIn;
  String? get errorMessage => _errorMessage;
  UserModel? get currentUser => _authService.currentUser;
  String? get token => _authService.token;
  AuthService get authService => _authService;

  /// Initialize — try auto-login from stored credentials
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    await _authService.tryAutoLogin();

    _isLoading = false;
    _isInitialized = true;
    notifyListeners();
  }

  /// Send OTP
  Future<void> sendOtp({
    required String phone,
    required Function(String) onCodeSent,
    required Function(String) onFailed,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    await _authService.sendOtp(
      phone,
      onCodeSent: (id) {
        _isLoading = false;
        notifyListeners();
        onCodeSent(id);
      },
      onFailed: (error) {
        _errorMessage = error;
        _isLoading = false;
        notifyListeners();
        onFailed(error);
      },
    );
  }

  /// Verify OTP
  Future<bool> verifyOtp(String otp) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    bool success = await _authService.verifyOtp(otp);

    _isLoading = false;
    if (!success) {
      _errorMessage = 'Invalid OTP. Please try again.';
    }
    notifyListeners();
    return success;
  }

  /// Register a new account
  Future<bool> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String otp,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _authService.register(
      name: name,
      email: email,
      phone: phone,
      password: password,
      otp: otp,
    );

    _isLoading = false;

    if (result['success'] == true) {
      notifyListeners();
      return true;
    } else {
      _errorMessage = result['error'];
      notifyListeners();
      return false;
    }
  }

  /// Login
  Future<bool> login({
    required String identifier,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _authService.login(
      identifier: identifier,
      password: password,
    );

    _isLoading = false;

    if (result['success'] == true) {
      notifyListeners();
      return true;
    } else {
      _errorMessage = result['error'];
      notifyListeners();
      return false;
    }
  }

  /// Logout
  Future<void> logout() async {
    await _authService.logout();
    _errorMessage = null;
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Login with Google
  Future<Map<String, dynamic>> loginWithGoogle() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _authService.loginWithGoogle();

    _isLoading = false;

    if (result['success'] == true) {
      notifyListeners();
      return result;
    } else {
      _errorMessage = result['error'];
      notifyListeners();
      return result;
    }
  }

  /// Register with Google (requires phone and otp)
  Future<bool> registerWithGoogle({
    required String idToken,
    required String phone,
    required String otp,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _authService.registerWithGoogle(
      idToken: idToken,
      phone: phone,
      otp: otp,
    );

    _isLoading = false;

    if (result['success'] == true) {
      notifyListeners();
      return true;
    } else {
      _errorMessage = result['error'];
      notifyListeners();
      return false;
    }
  }
}
