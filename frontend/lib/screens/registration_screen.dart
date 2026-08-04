import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/registration_api.dart';

enum RegRole { surveyor, officer }

class _RegColors {
  _RegColors._();

  static const header = Color(0xFF0D3D2F);
  static const bg = Color(0xFFF7F5EE);
  static const ink = Color(0xFF3A4A43);
  static const muted = Color(0xFF6B7D74);
  static const placeholder = Color(0xFF9AA39C);
  static const border = Color(0xFFE6E2D5);
  static const paper = Color(0xFFFAF8F0);
  static const rejected = Color(0xFFC05A3A);
  static const rejectedBg = Color(0x14C05A3A);
  static const verified = header;
  static const disabled = Color(0xFFD9D6CC);
  static const disabledText = Color(0xFF8A877D);
}

/// Basmati-survey-app style self-registration:
/// phone OTP → email + district → Sign up → check email → set password (deep link).
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({
    super.key,
    this.initialRole = RegRole.surveyor,
    this.deepLinkEmail,
    this.deepLinkToken,
  });

  final RegRole initialRole;

  /// Unused — email deep links now open [SetPasswordScreen] via DeepLinkService.
  final String? deepLinkEmail;
  final String? deepLinkToken;

  static bool isAnyInstanceMounted = false;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  late final RegRole _role = widget.initialRole;
  String? _busy;
  String? _error;
  String? _info;

  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  final _employeeIdController = TextEditingController();
  final _otpController = TextEditingController();

  final _nameFocus = FocusNode();
  final _mobileFocus = FocusNode();
  final _otpFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _employeeIdFocus = FocusNode();

  bool _otpRequested = false;
  bool _phoneVerified = false;
  String? _phoneToken;

  List<RegistrationDistrict> _districts = [];
  int? _selectedDistrictId;

  @override
  void initState() {
    super.initState();
    RegistrationScreen.isAnyInstanceMounted = true;
    _loadDistricts();
    for (final c in [
      _nameController,
      _emailController,
      _employeeIdController,
    ]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    RegistrationScreen.isAnyInstanceMounted = false;
    _nameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _employeeIdController.dispose();
    _otpController.dispose();
    _nameFocus.dispose();
    _mobileFocus.dispose();
    _otpFocus.dispose();
    _emailFocus.dispose();
    _employeeIdFocus.dispose();
    super.dispose();
  }

  void _moveFocusAfter(FocusNode current) {
    final chain = <FocusNode>[
      _nameFocus,
      if (!_phoneVerified) _mobileFocus,
      if (_otpRequested && !_phoneVerified) _otpFocus,
      if (_phoneVerified) _emailFocus,
      if (_phoneVerified && _role == RegRole.officer) _employeeIdFocus,
    ];
    final i = chain.indexOf(current);
    if (i >= 0 && i < chain.length - 1) {
      chain[i + 1].requestFocus();
      return;
    }
    current.unfocus();
  }

  Future<void> _loadDistricts() async {
    try {
      final districts = await RegistrationApi.getDistricts();
      if (!mounted) return;
      setState(() => _districts = districts);
    } catch (_) {}
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _info = null;
    });
  }

  bool get _canSignUp {
    final email = _emailController.text.trim();
    final emailOk = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    return _nameController.text.trim().isNotEmpty &&
        _phoneVerified &&
        emailOk &&
        _selectedDistrictId != null &&
        (_role == RegRole.surveyor ||
            _employeeIdController.text.trim().isNotEmpty);
  }

  Future<void> _sendPhoneOtp() async {
    final mobile = _mobileController.text.trim();
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(mobile)) {
      _showError('कृपया 10 अंकों का सही मोबाइल नंबर दर्ज करें');
      return;
    }
    setState(() {
      _busy = 'phone';
      _error = null;
    });
    try {
      final result = await RegistrationApi.sendPhoneOtp(mobile);
      if (!mounted) return;
      if (result.devOtp.isNotEmpty) {
        _otpController.text = result.devOtp;
      }
      setState(() {
        _otpRequested = true;
        _info = result.smsSent
            ? 'OTP भेज दिया गया है'
            : result.devOtp.isNotEmpty
            ? 'SMS delivery उपलब्ध नहीं है। Development OTP अपने आप भर दिया गया है।'
            : result.message;
      });
      _otpFocus.requestFocus();
    } on RegistrationApiException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _verifyPhoneOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 4) {
      _showError('कृपया पूरा OTP दर्ज करें');
      return;
    }
    setState(() {
      _busy = 'phone';
      _error = null;
    });
    try {
      final token = await RegistrationApi.verifyPhoneOtp(
        mobile: _mobileController.text.trim(),
        otp: otp,
      );
      if (!mounted) return;
      setState(() {
        _phoneVerified = true;
        _phoneToken = token;
        _info = 'फ़ोन सत्यापित हो गया — अब ईमेल और जिला अनलॉक हो गए हैं';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _emailFocus.requestFocus();
      });
    } on RegistrationApiException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _signUp() async {
    if (!_canSignUp || _busy != null) return;
    setState(() {
      _busy = 'signup';
      _error = null;
    });
    try {
      final result = _role == RegRole.surveyor
          ? await RegistrationApi.registerSurveyor(
              name: _nameController.text.trim(),
              mobile: _mobileController.text.trim(),
              phoneToken: _phoneToken!,
              email: _emailController.text.trim(),
              districtId: _selectedDistrictId!,
            )
          : await RegistrationApi.registerOfficer(
              name: _nameController.text.trim(),
              mobile: _mobileController.text.trim(),
              phoneToken: _phoneToken!,
              email: _emailController.text.trim(),
              districtId: _selectedDistrictId!,
              employeeId: _employeeIdController.text.trim(),
            );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Check your email',
            style: GoogleFonts.fraunces(
              fontWeight: FontWeight.w700,
              color: _RegColors.header,
            ),
          ),
          content: Text(
            '${result.message}\n\n'
            '1. Open the verification email and tap Verify.\n'
            '2. Set your password in the app that opens.\n'
            '3. Wait for admin approval, then Sign in.',
            style: GoogleFonts.ibmPlexSans(
              height: 1.4,
              fontSize: 14,
              color: _RegColors.ink,
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _RegColors.header,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } on RegistrationApiException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _RegColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(onBack: () => Navigator.of(context).pop()),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      _MessageBanner(text: _error!, isError: true),
                    if (_info != null && _error == null)
                      _MessageBanner(text: _info!, isError: false),
                    if (_error != null || _info != null)
                      const SizedBox(height: 16),
                    ..._buildFormBody(),
                  ],
                ),
              ),
            ),
            _Footer(
              child: _PrimaryButton(
                label: 'Sign up',
                loading: _busy == 'signup',
                onPressed: _canSignUp && _busy == null ? _signUp : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFormBody() {
    final roleLabel = _role == RegRole.surveyor ? 'Field Surveyor' : 'Officer';
    return [
      Text(
        'Create a $roleLabel account. Verify phone with OTP, then verify '
        'your email — after that you set your own password. An admin must '
        'still approve you before Sign in works.',
        style: GoogleFonts.ibmPlexSans(
          fontSize: 13,
          color: _RegColors.muted,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 20),
      _label('Full name', required: true),
      const SizedBox(height: 6),
      _plainField(
        _nameController,
        'जैसा आधार पर है',
        Icons.person_outline,
        key: const ValueKey('reg-name'),
        focusNode: _nameFocus,
        onNext: () => _moveFocusAfter(_nameFocus),
      ),
      const SizedBox(height: 16),
      _label('Phone', required: true),
      const SizedBox(height: 6),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _plainField(
              _mobileController,
              '10 अंक',
              Icons.call_outlined,
              key: const ValueKey('reg-phone'),
              focusNode: _mobileFocus,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              enabled: !_phoneVerified,
              onNext: () {
                if (_otpRequested && !_phoneVerified) {
                  _otpFocus.requestFocus();
                } else {
                  _moveFocusAfter(_mobileFocus);
                }
              },
            ),
          ),
          const SizedBox(width: 10),
          if (!_phoneVerified)
            _InlineActionButton(
              label: _otpRequested ? 'Resend' : 'Send OTP',
              loading: _busy == 'phone' && !_otpRequested,
              onPressed: _busy != null ? null : _sendPhoneOtp,
            )
          else
            const _VerifiedChip(),
        ],
      ),
      if (_otpRequested && !_phoneVerified) ...[
        const SizedBox(height: 14),
        _label('OTP', required: true),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _plainField(
                _otpController,
                '4-digit OTP',
                Icons.pin_outlined,
                key: const ValueKey('reg-otp'),
                focusNode: _otpFocus,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textInputAction: TextInputAction.done,
                onNext: () {
                  _otpFocus.unfocus();
                  if (_busy == null) _verifyPhoneOtp();
                },
              ),
            ),
            const SizedBox(width: 10),
            _InlineActionButton(
              label: 'Verify',
              loading: _busy == 'phone',
              onPressed: _busy != null ? null : _verifyPhoneOtp,
            ),
          ],
        ),
      ],
      if (!_phoneVerified) ...[
        const SizedBox(height: 10),
        Text(
          'Verify OTP to unlock email and location fields.',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 12.5,
            color: _RegColors.muted,
          ),
        ),
      ],
      if (_phoneVerified) ...[
        const SizedBox(height: 20),
        _label('Email', required: true),
        const SizedBox(height: 6),
        _plainField(
          _emailController,
          'email id',
          Icons.mail_outline_rounded,
          key: const ValueKey('reg-email'),
          focusNode: _emailFocus,
          keyboardType: TextInputType.emailAddress,
          onNext: () {
            if (_role == RegRole.officer) {
              _employeeIdFocus.requestFocus();
            } else {
              _emailFocus.unfocus();
            }
          },
        ),
        const SizedBox(height: 16),
        _districtDropdown(),
        if (_role == RegRole.officer) ...[
          const SizedBox(height: 16),
          _label('Employee ID', required: true),
          const SizedBox(height: 6),
          _plainField(
            _employeeIdController,
            'employee ID',
            Icons.badge_outlined,
            key: const ValueKey('reg-employee-id'),
            focusNode: _employeeIdFocus,
            textInputAction: TextInputAction.done,
            onNext: () => _employeeIdFocus.unfocus(),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'After Sign up, open the verification email on this phone and tap '
          '“Verify email & open app” to set your password.',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 12.5,
            color: _RegColors.muted,
            height: 1.4,
          ),
        ),
      ],
    ];
  }

  Widget _label(String text, {required bool required}) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.ibmPlexSans(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: _RegColors.ink,
        ),
        children: [
          TextSpan(text: text),
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: _RegColors.rejected),
            ),
        ],
      ),
    );
  }

  Widget _plainField(
    TextEditingController controller,
    String hint,
    IconData icon, {
    Key? key,
    FocusNode? focusNode,
    TextInputType? keyboardType,
    TextInputAction textInputAction = TextInputAction.next,
    VoidCallback? onNext,
    bool obscure = false,
    int? maxLength,
    bool enabled = true,
  }) {
    final effectiveType = keyboardType ?? TextInputType.text;
    return TextField(
      key: key,
      focusNode: focusNode,
      controller: controller,
      keyboardType: effectiveType,
      textInputAction: textInputAction,
      onEditingComplete: onNext,
      textCapitalization: effectiveType == TextInputType.emailAddress
          ? TextCapitalization.none
          : TextCapitalization.sentences,
      autocorrect: effectiveType != TextInputType.emailAddress,
      enableSuggestions:
          effectiveType == TextInputType.emailAddress ||
          effectiveType == TextInputType.text,
      autofillHints: switch (effectiveType) {
        TextInputType.emailAddress => const [AutofillHints.email],
        TextInputType.phone => const [AutofillHints.telephoneNumber],
        _ when obscure => const [AutofillHints.newPassword],
        _ => null,
      },
      obscureText: obscure,
      maxLength: maxLength,
      enabled: enabled,
      style: GoogleFonts.ibmPlexSans(fontSize: 14, color: _RegColors.ink),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: _RegColors.muted, size: 20),
        hintText: hint,
        hintStyle: GoogleFonts.notoSansDevanagari(
          fontSize: 13,
          color: _RegColors.placeholder,
        ),
        counterText: maxLength != null ? '' : null,
        filled: true,
        fillColor: enabled
            ? _RegColors.paper
            : _RegColors.border.withValues(alpha: 0.4),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _RegColors.border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _RegColors.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _RegColors.header, width: 2),
        ),
      ),
    );
  }

  Widget _districtDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('District', required: true),
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          initialValue: _selectedDistrictId,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: _RegColors.muted,
          ),
          style: GoogleFonts.ibmPlexSans(fontSize: 14, color: _RegColors.ink),
          decoration: InputDecoration(
            prefixIcon: const Icon(
              Icons.place_outlined,
              color: _RegColors.muted,
              size: 20,
            ),
            filled: true,
            fillColor: _RegColors.paper,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: _RegColors.border,
                width: 1.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: _RegColors.border,
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _RegColors.header, width: 2),
            ),
          ),
          items: _districts
              .map((d) => DropdownMenuItem(value: d.id, child: Text(d.name)))
              .toList(),
          onChanged: (value) => setState(() => _selectedDistrictId = value),
          hint: Text(
            _districts.isEmpty ? 'Loading districts…' : 'Select district',
            style: GoogleFonts.notoSansDevanagari(
              fontSize: 13,
              color: _RegColors.placeholder,
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _RegColors.header,
      padding: const EdgeInsets.fromLTRB(4, 8, 20, 16),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          const SizedBox(width: 4),
          Text(
            'Sign up',
            style: GoogleFonts.fraunces(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      decoration: const BoxDecoration(
        color: _RegColors.bg,
        border: Border(top: BorderSide(color: _RegColors.border)),
      ),
      child: SafeArea(top: false, child: child),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final bg = isError ? _RegColors.rejectedBg : const Color(0x140D3D2F);
    final fg = isError ? _RegColors.rejected : _RegColors.header;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: GoogleFonts.notoSansDevanagari(fontSize: 13, color: fg),
      ),
    );
  }
}

class _VerifiedChip extends StatelessWidget {
  const _VerifiedChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _RegColors.verified.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: _RegColors.verified,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            'Verified',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _RegColors.verified,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineActionButton extends StatelessWidget {
  const _InlineActionButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final foreground = enabled ? Colors.white : _RegColors.disabledText;
    return Material(
      color: enabled ? _RegColors.header : _RegColors.disabled,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          child: loading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: foreground,
                  ),
                )
              : Text(
                  label,
                  style: GoogleFonts.ibmPlexSans(
                    color: foreground,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? _RegColors.header : _RegColors.disabled,
            borderRadius: BorderRadius.circular(14),
          ),
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label,
                  style: GoogleFonts.ibmPlexSans(
                    color: enabled ? Colors.white : _RegColors.disabledText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}
