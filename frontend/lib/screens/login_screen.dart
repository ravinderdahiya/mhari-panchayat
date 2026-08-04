import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_role.dart';
import '../navigation/app_navigation.dart';
import '../navigation/role_navigation.dart';
import '../services/auth_api.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'registration_screen.dart';
import 'splash_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _citizenTab = true;
  UserRole _staffRole = UserRole.officer;
  bool _otpSent = false;
  bool _isSubmitting = false;
  bool _isResending = false;
  bool _passwordVisible = false;
  bool _isEnglish = false;
  int _otpSecondsRemaining = 0;
  int _resendSecondsRemaining = 0;
  DateTime? _otpExpiresAt;
  DateTime? _resendAvailableAt;
  Timer? _otpCountdownTimer;

  /// Returns [english] when the English toggle is active, else [hindi].
  String _t(String hindi, String english) => _isEnglish ? english : hindi;

  final _mobileController = TextEditingController();
  final _userIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpControllers = List.generate(4, (_) => TextEditingController());
  final _otpFocusNodes = List.generate(4, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    for (final node in _otpFocusNodes) {
      node.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _otpCountdownTimer?.cancel();
    _mobileController.dispose();
    _userIdController.dispose();
    _passwordController.dispose();
    for (final controller in _otpControllers) {
      controller.dispose();
    }
    for (final node in _otpFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _selectTab(bool citizen) {
    if (_citizenTab == citizen) return;
    _otpCountdownTimer?.cancel();
    setState(() {
      _citizenTab = citizen;
      _otpSent = false;
      _otpSecondsRemaining = 0;
      _resendSecondsRemaining = 0;
      _otpExpiresAt = null;
      _resendAvailableAt = null;
    });
  }

  int _secondsUntil(DateTime? deadline) {
    if (deadline == null) return 0;
    final milliseconds = deadline.difference(DateTime.now()).inMilliseconds;
    if (milliseconds <= 0) return 0;
    return (milliseconds + 999) ~/ 1000;
  }

  void _startOtpCountdown({
    required int expiresInSeconds,
    required int resendAfterSeconds,
  }) {
    _otpCountdownTimer?.cancel();
    final now = DateTime.now();
    _otpExpiresAt = now.add(Duration(seconds: expiresInSeconds));
    _resendAvailableAt = now.add(Duration(seconds: resendAfterSeconds));
    setState(() {
      _otpSecondsRemaining = expiresInSeconds;
      _resendSecondsRemaining = resendAfterSeconds;
    });

    _otpCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _otpSecondsRemaining = _secondsUntil(_otpExpiresAt);
        _resendSecondsRemaining = _secondsUntil(_resendAvailableAt);
      });

      if (_otpSecondsRemaining == 0 && _resendSecondsRemaining == 0) {
        timer.cancel();
      }
    });
  }

  void _clearOtp() {
    for (final controller in _otpControllers) {
      controller.clear();
    }
  }

  Future<void> _resendOtp() async {
    if (_isSubmitting || _isResending || _resendSecondsRemaining > 0) return;

    final mobile = _mobileController.text.trim();
    setState(() => _isResending = true);
    try {
      final result = await AuthApi.resendOtp(mobile);
      if (!mounted) return;
      _clearOtp();
      _startOtpCountdown(
        expiresInSeconds: result.expiresInSeconds,
        resendAfterSeconds: result.resendAfterSeconds,
      );
      _otpFocusNodes.first.requestFocus();
      _showMessage(result.message);
    } on AuthApiException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  Future<void> _continueAsStaff() async {
    if (_isSubmitting) return;

    final staffId = _userIdController.text.trim();
    final password = _passwordController.text;
    if (staffId.isEmpty || password.isEmpty) {
      _showMessage(
        _t('यूज़र ID और पासवर्ड दर्ज करें', 'Enter User ID and Password'),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final result = await AuthApi.staffLogin(staffId, password);
      final roleKey = result.role.toLowerCase();
      final serverRole = (roleKey == 'engineer' || roleKey == 'surveyor')
          ? UserRole.survey
          : roleKey == 'citizen'
          ? UserRole.citizen
          : UserRole.officer;
      await AuthService.saveLogin(
        role: serverRole,
        token: result.token,
        officerId: result.id,
        officerName: result.name,
        staffId: result.staffId,
        officerProfileId: result.officerProfileId,
      );
      if (!mounted) return;
      pushReplacement(context, dashboardForRole(serverRole));
    } on AuthApiException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.notoSansDevanagari())),
    );
  }

  void _onOtpChanged(int index, String value) {
    if (value.length == 1 && index < 3) {
      _otpFocusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _otpFocusNodes[index - 1].requestFocus();
    }
    setState(() {});
  }

  Future<void> _onCitizenPrimaryTap() async {
    if (_isSubmitting) return;

    final mobile = _mobileController.text.trim();
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(mobile)) {
      _showMessage(
        _t(
          'कृपया 10 अंकों का सही मोबाइल नंबर दर्ज करें',
          'Please enter a valid 10-digit mobile number',
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      if (mobile == '9999999999') {
        final result = await AuthApi.verifyOtp(mobile, '0000');
        await AuthService.saveLogin(
          role: UserRole.citizen,
          token: result.token,
        );
        if (!mounted) return;
        pushReplacement(context, dashboardForRole(UserRole.citizen));
        return;
      }

      if (!_otpSent) {
        final result = await AuthApi.sendOtp(mobile);
        if (!mounted) return;
        setState(() => _otpSent = true);
        _startOtpCountdown(
          expiresInSeconds: result.expiresInSeconds,
          resendAfterSeconds: result.resendAfterSeconds,
        );
        _otpFocusNodes.first.requestFocus();
        _showMessage(result.message);
      } else {
        if (_otpSecondsRemaining == 0) {
          _showMessage(
            _t(
              'ओटीपी की समय-सीमा समाप्त हो गई है। नया ओटीपी भेजें।',
              'OTP has expired. Please resend a new OTP.',
            ),
          );
          return;
        }
        final otp = _otpControllers.map((c) => c.text.trim()).join();
        if (otp.length != 4) {
          _showMessage(
            _t('कृपया पूरा ओटीपी दर्ज करें', 'Please enter the complete OTP'),
          );
          return;
        }
        final result = await AuthApi.verifyOtp(mobile, otp);
        await AuthService.saveLogin(
          role: UserRole.citizen,
          token: result.token,
        );
        if (!mounted) return;
        pushReplacement(context, dashboardForRole(UserRole.citizen));
      }
    } on AuthApiException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.topRight,
                child: _LanguageToggle(
                  isEnglish: _isEnglish,
                  onChanged: (value) => setState(() => _isEnglish = value),
                ),
              ),
              const SizedBox(height: 4),
              const Center(child: MhariPanchayatLogo(size: 64)),
              const SizedBox(height: 12),
              Text(
                'म्हारी पंचायत',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansDevanagari(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _t('लॉगिन', 'Login'),
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansDevanagari(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF212121),
                ),
              ),
              const SizedBox(height: 20),
              _RoleTabs(
                isCitizen: _citizenTab,
                onChanged: _selectTab,
                citizenLabel: _t('नागरिक', 'Citizen'),
                departmentLabel: _t('विभाग', 'Department'),
              ),
              const SizedBox(height: 22),
              if (_citizenTab) ..._buildCitizenForm() else ..._buildStaffForm(),
              const SizedBox(height: 28),
              _TermsFooter(onLinkTap: _showMessage, isEnglish: _isEnglish),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCitizenForm() {
    return [
      Text(
        _t('मोबाइल नंबर से लॉगिन करें', 'Login with mobile number'),
        textAlign: TextAlign.center,
        style: GoogleFonts.notoSansDevanagari(
          fontSize: 13,
          color: AppColors.secondaryText,
        ),
      ),
      const SizedBox(height: 14),
      _buildMobileField(),
      if (_otpSent) ...[
        const SizedBox(height: 16),
        _buildOtpRow(),
        const SizedBox(height: 8),
        _buildOtpStatus(),
      ],
      const SizedBox(height: 18),
      _PrimaryButton(
        onPressed: _isSubmitting ? null : _onCitizenPrimaryTap,
        loading: _isSubmitting,
        loadingLabel: _t('कृपया प्रतीक्षा करें...', 'Please wait...'),
        label: _otpSent
            ? _t('ओटीपी सत्यापित करें', 'Verify OTP')
            : _t('ओटीपी भेजें', 'Send OTP'),
        icon: _otpSent ? Icons.verified_rounded : Icons.send_rounded,
      ),
    ];
  }

  List<Widget> _buildStaffForm() {
    return [
      Text(
        _t(
          'मोबाइल, Emp ID, ईमेल या यूज़र ID और पासवर्ड से लॉगिन करें',
          'Login with mobile, Emp ID, email or User ID and Password',
        ),
        textAlign: TextAlign.center,
        style: GoogleFonts.notoSansDevanagari(
          fontSize: 13,
          color: AppColors.secondaryText,
        ),
      ),
      const SizedBox(height: 14),
      _DepartmentRolePicker(
        selected: _staffRole,
        onChanged: (role) => setState(() => _staffRole = role),
      ),
      const SizedBox(height: 14),
      _buildStaffField(
        label: _t('मोबाइल / Emp ID / ईमेल', 'Mobile / Emp ID / Email'),
        icon: Icons.person_rounded,
        controller: _userIdController,
      ),
      const SizedBox(height: 12),
      _buildStaffField(
        label: _t('पासवर्ड', 'Password'),
        icon: Icons.lock_rounded,
        controller: _passwordController,
        obscure: true,
      ),
      const SizedBox(height: 18),
      _PrimaryButton(
        onPressed: _isSubmitting ? null : _continueAsStaff,
        loading: _isSubmitting,
        loadingLabel: _t('कृपया प्रतीक्षा करें...', 'Please wait...'),
        label: _t('लॉगिन करें', 'Login'),
        icon: Icons.login_rounded,
      ),
      const SizedBox(height: 12),
      Center(
        child: TextButton(
          onPressed: () => push(
            context,
            RegistrationScreen(
              initialRole: _staffRole == UserRole.survey
                  ? RegRole.surveyor
                  : RegRole.officer,
            ),
          ),
          child: Text(
            _t('नया रजिस्ट्रेशन करें', 'New here? Register'),
            style: GoogleFonts.notoSansDevanagari(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.brandBlue,
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildMobileField() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Text(
            '+91',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF212121),
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 24, color: AppColors.border),
          Expanded(
            child: TextField(
              controller: _mobileController,
              enabled: !_otpSent,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              style: GoogleFonts.notoSansDevanagari(fontSize: 14),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                counterText: '',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                hintText: _t('मोबाइल नंबर दर्ज करें', 'Enter mobile number'),
                hintStyle: GoogleFonts.notoSansDevanagari(
                  fontSize: 13,
                  color: AppColors.mutedText,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(4, (index) {
        final focused = _otpFocusNodes[index].hasFocus;
        final filled = _otpControllers[index].text.isNotEmpty;

        return SizedBox(
          width: 44,
          height: 44,
          child: TextField(
            controller: _otpControllers[index],
            focusNode: _otpFocusNodes[index],
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 1,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (value) => _onOtpChanged(index, value),
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: AppColors.background,
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: AppColors.border,
                  width: 1.5,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: focused || filled
                      ? AppColors.brandBlue
                      : AppColors.border,
                  width: focused ? 2 : 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: AppColors.brandBlue,
                  width: 2,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildOtpStatus() {
    final minutes = _otpSecondsRemaining ~/ 60;
    final seconds = _otpSecondsRemaining % 60;
    final time = '$minutes:${seconds.toString().padLeft(2, '0')}';
    final expired = _otpSecondsRemaining == 0;
    final canResend = !_isResending && _resendSecondsRemaining == 0;

    return Row(
      children: [
        Icon(
          expired ? Icons.timer_off_outlined : Icons.timer_outlined,
          size: 17,
          color: expired ? Colors.red.shade700 : AppColors.secondaryText,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            expired
                ? _t('ओटीपी समाप्त', 'OTP expired')
                : _t('ओटीपी की समय-सीमा: $time', 'OTP expires in $time'),
            style: GoogleFonts.notoSansDevanagari(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: expired ? Colors.red.shade700 : AppColors.secondaryText,
            ),
          ),
        ),
        TextButton(
          onPressed: canResend ? _resendOtp : null,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: _isResending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _resendSecondsRemaining > 0
                      ? _t(
                          '${_resendSecondsRemaining}s में पुनः भेजें',
                          'Resend in ${_resendSecondsRemaining}s',
                        )
                      : _t('ओटीपी पुनः भेजें', 'Resend OTP'),
                  style: GoogleFonts.notoSansDevanagari(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: canResend
                        ? AppColors.secondary
                        : AppColors.mutedText,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildStaffField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    bool obscure = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.notoSansDevanagari(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF212121),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure && !_passwordVisible,
          style: GoogleFonts.poppins(fontSize: 14),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: AppColors.mutedText),
            suffixIcon: obscure
                ? IconButton(
                    tooltip: _passwordVisible
                        ? _t('पासवर्ड छिपाएं', 'Hide password')
                        : _t('पासवर्ड दिखाएं', 'Show password'),
                    onPressed: () =>
                        setState(() => _passwordVisible = !_passwordVisible),
                    icon: Icon(
                      _passwordVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.mutedText,
                      size: 20,
                    ),
                  )
                : null,
            filled: true,
            fillColor: AppColors.background,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.brandBlue,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RoleTabs extends StatelessWidget {
  const _RoleTabs({
    required this.isCitizen,
    required this.onChanged,
    required this.citizenLabel,
    required this.departmentLabel,
  });

  final bool isCitizen;
  final ValueChanged<bool> onChanged;
  final String citizenLabel;
  final String departmentLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.greyBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              label: citizenLabel,
              selected: isCitizen,
              onTap: () => onChanged(true),
            ),
          ),
          Expanded(
            child: _TabButton(
              label: departmentLabel,
              selected: !isCitizen,
              onTap: () => onChanged(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle({required this.isEnglish, required this.onChanged});

  final bool isEnglish;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.greyBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LanguagePill(
            label: 'हिं',
            selected: !isEnglish,
            onTap: () => onChanged(false),
          ),
          _LanguagePill(
            label: 'EN',
            selected: isEnglish,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _LanguagePill extends StatelessWidget {
  const _LanguagePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.secondaryText,
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.notoSansDevanagari(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.secondaryText,
          ),
        ),
      ),
    );
  }
}

class _DepartmentRolePicker extends StatelessWidget {
  const _DepartmentRolePicker({
    required this.selected,
    required this.onChanged,
  });

  final UserRole selected;
  final ValueChanged<UserRole> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RoleChip(
            label: 'Officer',
            selected: selected == UserRole.officer,
            onTap: () => onChanged(UserRole.officer),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _RoleChip(
            label: 'Survey',
            selected: selected == UserRole.survey,
            onTap: () => onChanged(UserRole.survey),
          ),
        ),
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandBlueTint : AppColors.greyBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.brandBlue : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.brandBlue : AppColors.secondaryText,
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.onPressed,
    required this.label,
    required this.icon,
    required this.loading,
    required this.loadingLabel,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData icon;
  final bool loading;
  final String loadingLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            gradient: AppGradients.cta,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading) ...[
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    loadingLabel,
                    style: GoogleFonts.notoSansDevanagari(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ] else ...[
                  Text(
                    label,
                    style: GoogleFonts.notoSansDevanagari(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(icon, color: Colors.white, size: 20),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TermsFooter extends StatelessWidget {
  const _TermsFooter({required this.onLinkTap, required this.isEnglish});

  final ValueChanged<String> onLinkTap;
  final bool isEnglish;

  @override
  Widget build(BuildContext context) {
    final baseStyle = GoogleFonts.notoSansDevanagari(
      fontSize: 11,
      color: AppColors.secondaryText,
      height: 1.6,
    );
    final linkStyle = GoogleFonts.notoSansDevanagari(
      fontSize: 11,
      color: AppColors.brandBlue,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.brandBlue,
      height: 1.6,
    );

    final termsText = isEnglish ? 'Terms of Service' : 'सेवा की शर्तें';
    final privacyText = isEnglish ? 'Privacy Policy' : 'गोपनीयता नीति';
    final termsMessage = isEnglish
        ? 'Terms of Service will be available soon'
        : 'सेवा की शर्तें जल्द ही उपलब्ध होंगी';
    final privacyMessage = isEnglish
        ? 'Privacy Policy will be available soon'
        : 'गोपनीयता नीति जल्द ही उपलब्ध होगी';

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: baseStyle,
        children: [
          TextSpan(
            text: isEnglish
                ? 'By continuing, you agree to our '
                : 'जारी रखते हुए, आप हमारी ',
          ),
          TextSpan(
            text: termsText,
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () => onLinkTap(termsMessage),
          ),
          TextSpan(text: isEnglish ? ' and\n' : ' और\n'),
          TextSpan(
            text: privacyText,
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () => onLinkTap(privacyMessage),
          ),
          TextSpan(text: isEnglish ? '.' : ' से सहमत हैं।'),
        ],
      ),
    );
  }
}
