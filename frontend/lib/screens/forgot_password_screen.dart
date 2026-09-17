import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_api.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// Staff (Department login) "forgot password" - two steps: identifier ->
/// OTP sent to the mobile on file for that account, then OTP + new
/// password in one submit. Mirrors the OTP UX already used for citizen
/// login (same 4-box entry, countdown, resend) for a familiar feel.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _identifierController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _otpControllers = List.generate(4, (_) => TextEditingController());
  final _otpFocusNodes = List.generate(4, (_) => FocusNode());

  bool _otpSent = false;
  bool _submitting = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _error;
  String? _mobileHint;
  int _otpSecondsRemaining = 0;
  int _resendSecondsRemaining = 0;
  DateTime? _otpExpiresAt;
  DateTime? _resendAvailableAt;
  Timer? _countdownTimer;

  bool get _lenOk => _newPasswordController.text.length >= 8;
  bool get _matchOk =>
      _newPasswordController.text.isNotEmpty &&
      _newPasswordController.text == _confirmController.text;

  @override
  void initState() {
    super.initState();
    for (final c in [_newPasswordController, _confirmController]) {
      c.addListener(() => setState(() {}));
    }
    for (final node in _otpFocusNodes) {
      node.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _identifierController.dispose();
    _newPasswordController.dispose();
    _confirmController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final node in _otpFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  int _secondsUntil(DateTime? deadline) {
    if (deadline == null) return 0;
    final milliseconds = deadline.difference(DateTime.now()).inMilliseconds;
    if (milliseconds <= 0) return 0;
    return (milliseconds + 999) ~/ 1000;
  }

  void _startCountdown({
    required int expiresInSeconds,
    required int resendAfterSeconds,
  }) {
    _countdownTimer?.cancel();
    final now = DateTime.now();
    _otpExpiresAt = now.add(Duration(seconds: expiresInSeconds));
    _resendAvailableAt = now.add(Duration(seconds: resendAfterSeconds));
    setState(() {
      _otpSecondsRemaining = expiresInSeconds;
      _resendSecondsRemaining = resendAfterSeconds;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
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

  Future<void> _sendOtp({bool resend = false}) async {
    if (_submitting) return;
    final identifier = _identifierController.text.trim();
    if (identifier.isEmpty) {
      setState(() => _error = 'मोबाइल / Emp ID / ईमेल / यूज़र ID दर्ज करें');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await AuthApi.sendStaffPasswordResetOtp(identifier);
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        _mobileHint = result.mobileHint;
      });
      _startCountdown(
        expiresInSeconds: result.expiresInSeconds,
        resendAfterSeconds: result.resendAfterSeconds,
      );
      if (resend) {
        for (final c in _otpControllers) {
          c.clear();
        }
      }
      _otpFocusNodes.first.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message,
            style: GoogleFonts.notoSansDevanagari(),
          ),
        ),
      );
    } on AuthApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_submitting) return;
    final otp = _otpControllers.map((c) => c.text.trim()).join();
    if (otp.length != 4) {
      setState(() => _error = 'कृपया पूरा OTP दर्ज करें');
      return;
    }
    if (!_lenOk) {
      setState(() => _error = 'पासवर्ड कम से कम 8 अक्षर का होना चाहिए');
      return;
    }
    if (!_matchOk) {
      setState(() => _error = 'दोनों पासवर्ड मेल नहीं खाते');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await AuthApi.verifyStaffPasswordReset(
        identifier: _identifierController.text.trim(),
        otp: otp,
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'पासवर्ड बदल गया',
            style: GoogleFonts.notoSansDevanagari(fontWeight: FontWeight.w700),
          ),
          content: Text(
            'अब आप नए पासवर्ड से लॉगिन कर सकते हैं।',
            style: GoogleFonts.notoSansDevanagari(height: 1.4),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } on AuthApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _onOtpChanged(int index, String value) {
    if (value.length == 1 && index < 3) {
      _otpFocusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _otpFocusNodes[index - 1].requestFocus();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.greyBg,
      body: Column(
        children: [
          GradientHeader(
            title: 'पासवर्ड भूल गए?',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Transform.translate(
              offset: const Offset(0, -20),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.greyBg,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.screen),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _otpSent ? _buildResetStep() : _buildIdentifierStep(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildIdentifierStep() {
    return [
      Text(
        'अपना मोबाइल, Emp ID, ईमेल या यूज़र ID दर्ज करें - OTP आपके रजिस्टर्ड मोबाइल पर भेजा जाएगा।',
        style: GoogleFonts.notoSansDevanagari(
          fontSize: 13,
          color: AppColors.secondaryText,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _identifierController,
        style: GoogleFonts.poppins(fontSize: 14),
        decoration: const InputDecoration(
          labelText: 'मोबाइल / Emp ID / ईमेल / यूज़र ID',
          prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(
          _error!,
          style: GoogleFonts.notoSansDevanagari(
            color: const Color(0xFFC62828),
            fontSize: 13,
          ),
        ),
      ],
      const SizedBox(height: 18),
      GradientButton(
        onPressed: _submitting ? null : () => _sendOtp(),
        label: _submitting ? 'भेजा जा रहा है...' : 'OTP भेजें',
      ),
    ];
  }

  List<Widget> _buildResetStep() {
    final minutes = _otpSecondsRemaining ~/ 60;
    final seconds = _otpSecondsRemaining % 60;
    final time = '$minutes:${seconds.toString().padLeft(2, '0')}';
    final expired = _otpSecondsRemaining == 0;
    final canResend = !_submitting && _resendSecondsRemaining == 0;

    return [
      if (_mobileHint != null) ...[
        Text(
          '$_mobileHint पर OTP भेजा गया है',
          style: GoogleFonts.notoSansDevanagari(
            fontSize: 13,
            color: AppColors.secondaryText,
          ),
        ),
        const SizedBox(height: 14),
      ],
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(4, (index) {
          final focused = _otpFocusNodes[index].hasFocus;
          final filled = _otpControllers[index].text.isNotEmpty;
          return SizedBox(
            width: 52,
            height: 52,
            child: TextField(
              controller: _otpControllers[index],
              focusNode: _otpFocusNodes[index],
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 1,
              style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (value) => _onOtpChanged(index, value),
              decoration: InputDecoration(
                counterText: '',
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.border, width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: focused || filled ? AppColors.primary : AppColors.border,
                    width: focused ? 2 : 1.5,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
              ),
            ),
          );
        }),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Icon(
            expired ? Icons.timer_off_outlined : Icons.timer_outlined,
            size: 16,
            color: expired ? const Color(0xFFC62828) : AppColors.secondaryText,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              expired ? 'OTP समाप्त हो गया' : 'OTP की समय-सीमा: $time',
              style: GoogleFonts.notoSansDevanagari(
                fontSize: 12,
                color: expired ? const Color(0xFFC62828) : AppColors.secondaryText,
              ),
            ),
          ),
          TextButton(
            onPressed: canResend ? () => _sendOtp(resend: true) : null,
            child: Text(
              _resendSecondsRemaining > 0
                  ? '${_resendSecondsRemaining}s में पुनः भेजें'
                  : 'OTP पुनः भेजें',
              style: GoogleFonts.notoSansDevanagari(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      _passwordField(
        controller: _newPasswordController,
        label: 'नया पासवर्ड',
        obscure: _obscureNew,
        onToggle: () => setState(() => _obscureNew = !_obscureNew),
      ),
      const SizedBox(height: 14),
      _passwordField(
        controller: _confirmController,
        label: 'पासवर्ड की पुष्टि करें',
        obscure: _obscureConfirm,
        onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
      ),
      const SizedBox(height: 10),
      Text(
        '• कम से कम 8 अक्षर',
        style: GoogleFonts.notoSansDevanagari(
          fontSize: 12.5,
          color: _lenOk ? AppColors.primary : AppColors.secondaryText,
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(
          _error!,
          style: GoogleFonts.notoSansDevanagari(
            color: const Color(0xFFC62828),
            fontSize: 13,
          ),
        ),
      ],
      const SizedBox(height: 18),
      GradientButton(
        onPressed: _submitting ? null : _resetPassword,
        label: _submitting ? 'सेव हो रहा है...' : 'पासवर्ड बदलें',
      ),
    ];
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        ),
      ),
    );
  }
}
