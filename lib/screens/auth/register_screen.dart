import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/app_colors.dart';
import '../../core/legal_docs.dart';
import 'document_viewer_screen.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

/// Ultra-Premium register screen with deep glassmorphism and organic masking.
class RegisterScreen extends StatefulWidget {
  final Map<String, dynamic>? googleData;
  const RegisterScreen({super.key, this.googleData});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  String _completePhoneNumber = '';
  
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreedToTerms = false;

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmPasswordFocus = FocusNode();

  late AnimationController _enterController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  
  late AnimationController _floatController;
  late Animation<Offset> _floatAnim;

  @override
  void initState() {
    super.initState();
    
    _enterController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _enterController, curve: Curves.easeOut),
    );
    
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _enterController, curve: Curves.easeOutCubic),
    );

    _floatController = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    )..repeat(reverse: true);
    
    _floatAnim = Tween<Offset>(begin: const Offset(0, -0.03), end: const Offset(0, 0.03)).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOutSine),
    );

    _nameFocus.addListener(() => setState(() {}));
    _emailFocus.addListener(() => setState(() {}));
    _phoneFocus.addListener(() => setState(() {}));
    _passwordFocus.addListener(() => setState(() {}));
    _confirmPasswordFocus.addListener(() => setState(() {}));

    if (widget.googleData != null) {
      _nameController.text = widget.googleData!['name'] ?? '';
      _emailController.text = widget.googleData!['email'] ?? '';
    }

    _enterController.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    _enterController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  Future<void> _initiateRegistration() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please agree to the Terms and Privacy Policy to continue.')),
      );
      return;
    }
    
    FocusScope.of(context).unfocus();

    final authProvider = context.read<AuthProvider>();
    
    // Bypass OTP Verification for now
    bool registered = await authProvider.register(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _completePhoneNumber.isEmpty ? _phoneController.text.trim() : _completePhoneNumber,
      password: _passwordController.text,
      otp: "123456", // dummy otp
    );
    
    if (registered && mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  void _showOtpSheet(BuildContext context) {
    final otpController = TextEditingController();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colors = AppColors.of(context);
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.primaryBackground,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: colors.borderColor.withValues(alpha: 0.2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Verify Phone Number',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter the OTP sent to ${_completePhoneNumber.isEmpty ? _phoneController.text : _completePhoneNumber}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: otpController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
                  maxLength: 6,
                  decoration: InputDecoration(
                    counterText: "",
                    filled: true,
                    fillColor: colors.surfaceColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 24),
                Consumer<AuthProvider>(
                  builder: (context, auth, _) {
                    return SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: auth.isLoading
                            ? null
                            : () async {
                                final otp = otpController.text.trim();
                                if (otp.length < 6) return;
                                
                                // Verify OTP
                                bool otpVerified = await auth.verifyOtp(otp);
                                if (otpVerified && mounted) {
                                  // Register user
                                  bool registered = await auth.register(
                                    name: _nameController.text.trim(),
                                    email: _emailController.text.trim(),
                                    phone: _completePhoneNumber.isEmpty ? _phoneController.text.trim() : _completePhoneNumber,
                                    password: _passwordController.text,
                                    otp: otp, // Pass the OTP string for backwards compatibility or leave empty
                                  );
                                  
                                  if (registered && mounted) {
                                    Navigator.pop(ctx); // Close sheet
                                    Navigator.pushReplacementNamed(context, '/home');
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.accentPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: auth.isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Verify & Create Account', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    );
                  }
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  void _openDocument(String title, String content) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DocumentViewerScreen(title: title, content: content),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: colors.primaryBackground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(decoration: BoxDecoration(color: colors.primaryBackground)),
          
          // Immersive Background Illustration
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.45,
            child: ShaderMask(
              shaderCallback: (rect) {
                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black, Colors.black.withValues(alpha: 0.8), Colors.transparent],
                  stops: const [0.0, 0.6, 1.0],
                ).createShader(rect);
              },
              blendMode: BlendMode.dstIn,
              child: Image.asset(
                'assets/illustrations/login_bg_new.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
          
          Positioned(bottom: -100, left: -100, child: _buildBlurOrb(colors.accentSecondary, 350)),
          Positioned(top: MediaQuery.of(context).size.height * 0.15, right: -120, child: _buildBlurOrb(colors.accentPrimary, 300)),

          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Builder(
                  builder: (context) {
                    final size = MediaQuery.sizeOf(context);
                    final isLandscape = size.width > size.height && size.width > 480;

                    Widget headerContent = Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 32),
                        Text(
                          'Create Account',
                          style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: colors.textPrimary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Join RoUniity and explore together',
                          style: theme.textTheme.bodyLarge?.copyWith(color: colors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    );

                    Widget formContent = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildGlassForm(colors, theme),
                        const SizedBox(height: 32),
                        Center(
                          child: GestureDetector(
                            onTap: () {
                              context.read<AuthProvider>().clearError();
                              Navigator.of(context).pushReplacementNamed('/login');
                            },
                            child: RichText(
                              text: TextSpan(
                                text: "Already have an account? ",
                                style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                                children: [
                                  TextSpan(
                                    text: 'Sign In',
                                    style: theme.textTheme.bodyMedium?.copyWith(color: colors.accentPrimary, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    );

                    return SingleChildScrollView(
                      padding: EdgeInsets.symmetric(horizontal: isLandscape ? 40 : 28),
                      physics: const BouncingScrollPhysics(),
                      child: isLandscape
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 32, top: 40),
                                      child: headerContent,
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: formContent,
                                  ),
                                ],
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 20),
                                headerContent,
                                const SizedBox(height: 32),
                                formContent,
                              ],
                            ),
                    );
                  }
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlurOrb(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: Container(color: Colors.transparent),
      ),
    );
  }

  Widget _buildGlassForm(AppColorScheme colors, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: colors.surfaceColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 40, spreadRadius: -5),
          BoxShadow(color: colors.accentPrimary.withValues(alpha: 0.05), blurRadius: 40, spreadRadius: 10),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _buildGlowingTextField(
                  controller: _nameController,
                  focusNode: _nameFocus,
                  colors: colors,
                  theme: theme,
                  label: 'Full Name',
                  icon: Icons.person_outline,
                  textCapitalization: TextCapitalization.words,
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                _buildGlowingTextField(
                  controller: _emailController,
                  focusNode: _emailFocus,
                  colors: colors,
                  theme: theme,
                  label: 'Email',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Required';
                    if (!value.contains('@')) return 'Invalid email';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: _phoneFocus.hasFocus ? [BoxShadow(color: colors.accentPrimary.withValues(alpha: 0.1), blurRadius: 12, spreadRadius: 0)] : [],
                  ),
                  child: IntlPhoneField(
                    controller: _phoneController,
                    focusNode: _phoneFocus,
                    style: theme.textTheme.bodyLarge?.copyWith(color: colors.textPrimary),
                    dropdownTextStyle: theme.textTheme.bodyLarge?.copyWith(color: colors.textPrimary),
                    dropdownIcon: Icon(Icons.arrow_drop_down, color: colors.textTertiary),
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      labelStyle: theme.textTheme.bodyMedium?.copyWith(color: _phoneFocus.hasFocus ? colors.accentPrimary : colors.textTertiary),
                      filled: true,
                      fillColor: colors.surfaceColor.withValues(alpha: _phoneFocus.hasFocus ? 0.2 : 0.05),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.borderColor.withValues(alpha: 0.1))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.borderColor.withValues(alpha: 0.1))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.accentPrimary.withValues(alpha: 0.5), width: 1.5)),
                      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.accentDanger)),
                      counterText: '',
                    ),
                    initialCountryCode: 'IN', // Default country code (can be modified if needed)
                    onChanged: (phone) {
                      _completePhoneNumber = phone.completeNumber;
                    },
                  ),
                ),
                const SizedBox(height: 16),
                _buildGlowingTextField(
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  colors: colors,
                  theme: theme,
                  label: 'Password',
                  icon: Icons.lock_outline,
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Required';
                    if (value.length < 6) return 'Must be at least 6 characters';
                    return null;
                  },
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: colors.textTertiary),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                const SizedBox(height: 16),
                _buildGlowingTextField(
                  controller: _confirmPasswordController,
                  focusNode: _confirmPasswordFocus,
                  colors: colors,
                  theme: theme,
                  label: 'Confirm Password',
                  icon: Icons.lock_outline,
                  obscureText: _obscureConfirmPassword,
                  validator: (value) {
                    if (value != _passwordController.text) return 'Passwords do not match';
                    return null;
                  },
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility, color: colors.textTertiary),
                    onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                  ),
                ),
                const SizedBox(height: 20),
                
                // Terms and Conditions Checkbox
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: _agreedToTerms,
                        activeColor: colors.accentPrimary,
                        onChanged: (val) => setState(() => _agreedToTerms = val ?? false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {},
                        child: RichText(
                          text: TextSpan(
                            style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary, height: 1.5),
                            children: [
                              const TextSpan(text: 'I agree to the '),
                              WidgetSpan(
                                child: GestureDetector(
                                  onTap: () => _openDocument('Terms and Conditions', LegalDocs.termsAndConditions),
                                  child: Text('Terms and Conditions', style: TextStyle(color: colors.accentPrimary, fontWeight: FontWeight.bold)),
                                )
                              ),
                              const TextSpan(text: ' and '),
                              WidgetSpan(
                                child: GestureDetector(
                                  onTap: () => _openDocument('Privacy Policy', LegalDocs.privacyPolicy),
                                  child: Text('Privacy Policy', style: TextStyle(color: colors.accentPrimary, fontWeight: FontWeight.bold)),
                                )
                              ),
                            ]
                          )
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 28),
                Consumer<AuthProvider>(
                  builder: (context, auth, _) {
                    if (auth.errorMessage != null) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.accentDanger.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colors.accentDanger.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: colors.accentDanger, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(auth.errorMessage!, style: theme.textTheme.bodySmall?.copyWith(color: colors.accentDanger)),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                Consumer<AuthProvider>(
                  builder: (context, auth, _) {
                    return _buildTactileButton(
                      colors: colors,
                      theme: theme,
                      isLoading: auth.isLoading,
                      onPressed: auth.isLoading ? null : _initiateRegistration,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlowingTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required AppColorScheme colors,
    required ThemeData theme,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
    Widget? suffixIcon,
  }) {
    final isFocused = focusNode.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: isFocused ? [BoxShadow(color: colors.accentPrimary.withValues(alpha: 0.1), blurRadius: 12, spreadRadius: 0)] : [],
      ),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        style: theme.textTheme.bodyLarge?.copyWith(color: colors.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: theme.textTheme.bodyMedium?.copyWith(color: isFocused ? colors.accentPrimary : colors.textTertiary),
          prefixIcon: Icon(icon, color: isFocused ? colors.accentPrimary : colors.textTertiary),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: colors.surfaceColor.withValues(alpha: isFocused ? 0.2 : 0.05),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.borderColor.withValues(alpha: 0.1))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.borderColor.withValues(alpha: 0.1))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.accentPrimary.withValues(alpha: 0.5), width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.accentDanger)),
        ),
        validator: validator,
      ),
    );
  }

  Widget _buildTactileButton({
    required AppColorScheme colors,
    required ThemeData theme,
    required bool isLoading,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Container(
        decoration: BoxDecoration(
          gradient: colors.accentGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: colors.accentPrimary.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8)),
            BoxShadow(color: colors.accentPrimary.withValues(alpha: 0.2), blurRadius: 40, offset: const Offset(0, 0)),
          ],
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: isLoading
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Colors.white)))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Create Account', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 1.2)),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                  ],
                ),
        ),
      ),
    );
  }
}
