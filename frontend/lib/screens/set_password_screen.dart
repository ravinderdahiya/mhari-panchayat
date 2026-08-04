import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/registration_api.dart';

/// Basmati-style set-password screen after email verification deep link.
class SetPasswordScreen extends StatefulWidget {
  const SetPasswordScreen({super.key, this.initialToken, this.accountEmail});

  final String? initialToken;
  final String? accountEmail;

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  static const _header = Color(0xFF0D3D2F);
  static const _bg = Color(0xFFF7F5EE);
  static const _muted = Color(0xFF6B7D74);
  static const _paper = Color(0xFFFAF8F0);
  static const _border = Color(0xFFE6E2D5);

  late final TextEditingController _tokenController;
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _submitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;

  bool get _fromDeepLink => (widget.initialToken ?? '').trim().isNotEmpty;

  bool get _lenOk => _passwordController.text.length >= 8;
  bool get _matchOk =>
      _passwordController.text.isNotEmpty &&
      _passwordController.text == _confirmController.text;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(text: widget.initialToken ?? '');
    _passwordController.addListener(() => setState(() {}));
    _confirmController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String _extractToken(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.queryParameters['token'] != null) {
      return uri.queryParameters['token']!;
    }
    return trimmed;
  }

  Future<void> _submit() async {
    final token = _extractToken(_tokenController.text);
    if (token.isEmpty) {
      setState(
        () => _error = 'Paste the set-password link or token from your email',
      );
      return;
    }
    if (!_lenOk) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    if (!_matchOk) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final message = await RegistrationApi.setPassword(
        token: token,
        password: _passwordController.text,
        confirmPassword: _confirmController.text,
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
            'Password saved',
            style: GoogleFonts.fraunces(fontWeight: FontWeight.w700),
          ),
          content: Text(message, style: GoogleFonts.ibmPlexSans(height: 1.4)),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _header,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text('Go to Sign in'),
            ),
          ],
        ),
      );
    } on RegistrationApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(
          'Set password',
          style: GoogleFonts.fraunces(fontWeight: FontWeight.w600),
        ),
        backgroundColor: _header,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _paper,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Set your password',
                  style: GoogleFonts.fraunces(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _header,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose a password for your account. Use it with your email '
                  'to Sign in after admin approval.',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    color: _muted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                if (_fromDeepLink) ...[
                  if ((widget.accountEmail ?? '').isNotEmpty) ...[
                    InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.email_outlined, size: 20),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        widget.accountEmail!,
                        style: GoogleFonts.ibmPlexSans(fontSize: 15),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5EF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _border),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.verified_rounded,
                          color: _header,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Verification link applied',
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _header,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: _tokenController,
                    decoration: InputDecoration(
                      labelText: 'Set-password link or token',
                      prefixIcon: const Icon(Icons.link_rounded, size: 20),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(
                      Icons.lock_outline_rounded,
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmController,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirm password',
                    prefixIcon: const Icon(
                      Icons.lock_outline_rounded,
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '• At least 8 characters',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 12.5,
                    color: _lenOk ? _header : _muted,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: GoogleFonts.ibmPlexSans(
                      color: const Color(0xFFC05A3A),
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _header,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Save password',
                          style: GoogleFonts.ibmPlexSans(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
