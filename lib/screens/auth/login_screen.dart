import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _obscurePassword = true;
  
  final FocusNode _identifierFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _identifierFocus.addListener(() => setState(() {}));
    _passwordFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _identifierFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    
    FocusScope.of(context).unfocus();

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(
      identifier: _identifierController.text.trim(),
      password: _passwordController.text,
    );

    if (success && mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Custom colors based on the mockup
    const bgColor = Color(0xFF0C1014);
    const cardColor = Color(0xFF14181B);
    const fieldBgColor = Color(0xFF14181B);
    const fieldBorderColor = Color(0xFF2D3236);
    const primaryGreen = Color(0xFF55A549); // Mockup green
    const textGray = Color(0xFF8B9298);
    const textWhite = Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full Screen Background Image
          Image.asset(
            'assets/illustrations/login_bg_new.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
          // Dark Overlay for readability
          Container(color: Colors.black.withValues(alpha: 0.5)),
          
          // Scrollable Form Content
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Space to push form down (adjust as needed based on image)
                  SizedBox(height: MediaQuery.of(context).size.height * 0.52),
                  
                  // Form Area
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    // Welcome Text
                    RichText(
                      text: const TextSpan(
                        text: 'Welcome back, ',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: textWhite,
                          letterSpacing: -0.5,
                        ),
                        children: [
                          TextSpan(
                            text: 'explorer.',
                            style: TextStyle(color: primaryGreen),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Sign in to continue your journey with your group.',
                      style: TextStyle(
                        fontSize: 14,
                        color: textWhite,
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Form Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: fieldBorderColor, width: 1),
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Email Field
                            _buildTextField(
                              controller: _identifierController,
                              focusNode: _identifierFocus,
                              hintText: 'Email address',
                              icon: Icons.mail_outline_rounded,
                              keyboardType: TextInputType.emailAddress,
                              borderColor: fieldBorderColor,
                              focusColor: primaryGreen,
                              fillColor: fieldBgColor,
                              textColor: textWhite,
                              hintColor: textGray,
                            ),
                            const SizedBox(height: 16),
                            
                            // Password Field
                            _buildTextField(
                              controller: _passwordController,
                              focusNode: _passwordFocus,
                              hintText: 'Password',
                              icon: Icons.lock_outline_rounded,
                              obscureText: _obscurePassword,
                              borderColor: fieldBorderColor,
                              focusColor: primaryGreen,
                              fillColor: fieldBgColor,
                              textColor: textWhite,
                              hintColor: textGray,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  color: textGray,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() => _obscurePassword = !_obscurePassword);
                                },
                              ),
                            ),
                            

                            const SizedBox(height: 16),
                            
                            // Error message
                            Consumer<AuthProvider>(
                              builder: (context, auth, _) {
                                if (auth.errorMessage != null) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: Text(
                                      auth.errorMessage!,
                                      style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                                      textAlign: TextAlign.center,
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),

                            // Sign In Button
                            Consumer<AuthProvider>(
                              builder: (context, auth, _) {
                                return SizedBox(
                                  height: 52,
                                  child: ElevatedButton(
                                    onPressed: auth.isLoading ? null : _handleLogin,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primaryGreen,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: auth.isLoading
                                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                        : const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                'Sign In',
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              SizedBox(width: 8),
                                              Icon(Icons.arrow_forward_rounded, size: 20),
                                            ],
                                          ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 24),
                            
                            // Divider
                            Row(
                              children: [
                                Expanded(child: Divider(color: fieldBorderColor, thickness: 1)),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16),
                                  child: Text(
                                    'or continue with',
                                    style: TextStyle(color: textGray, fontSize: 12),
                                  ),
                                ),
                                Expanded(child: Divider(color: fieldBorderColor, thickness: 1)),
                              ],
                            ),
                            const SizedBox(height: 24),
                            
                            // Google Button
                            Consumer<AuthProvider>(
                              builder: (context, auth, _) {
                                return SizedBox(
                                  height: 52,
                                  child: OutlinedButton(
                                    onPressed: auth.isLoading
                                        ? null
                                        : () async {
                                            final result = await auth.loginWithGoogle();
                                            if (result['success'] == true && context.mounted) {
                                              if (result['requiresPhone'] == true) {
                                                Navigator.of(context).pushReplacementNamed(
                                                  '/register',
                                                  arguments: result['googleData'],
                                                );
                                              } else {
                                                Navigator.of(context).pushReplacementNamed('/home');
                                              }
                                            }
                                          },
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      side: const BorderSide(color: fieldBorderColor),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: auth.isLoading
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Image.asset(
                                                'assets/google_logo.png',
                                                width: 24,
                                                height: 24,
                                              ),
                                              const SizedBox(width: 12),
                                              const Text(
                                                'Continue with Google',
                                                style: TextStyle(
                                                  color: textWhite,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                );
                              }
                            ),
                            const SizedBox(height: 24),
                            
                            // Security Note
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.verified_user_outlined, color: primaryGreen, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'We keep your data safe and secure',
                                  style: TextStyle(color: textGray.withValues(alpha: 0.8), fontSize: 11),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // Create Account Link
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          context.read<AuthProvider>().clearError();
                          Navigator.of(context).pushReplacementNamed('/register');
                        },
                        child: RichText(
                          text: const TextSpan(
                            text: 'New to RoUniity? ',
                            style: TextStyle(color: textGray, fontSize: 13),
                            children: [
                              TextSpan(
                                text: 'Create account ',
                                style: TextStyle(
                                  color: primaryGreen,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              WidgetSpan(
                                child: Icon(Icons.arrow_forward_rounded, size: 14, color: primaryGreen),
                                alignment: PlaceholderAlignment.middle,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  ),
);
}

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required IconData icon,
    required Color borderColor,
    required Color focusColor,
    required Color fillColor,
    required Color textColor,
    required Color hintColor,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
  }) {
    final isFocused = focusNode.hasFocus;
    
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: TextStyle(color: textColor, fontSize: 14),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: hintColor, fontSize: 14),
        prefixIcon: Icon(
          icon,
          color: isFocused ? focusColor : hintColor,
          size: 20,
        ),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: fillColor,
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: borderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: focusColor, width: 1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return 'Required';
        return null;
      },
    );
  }

}
