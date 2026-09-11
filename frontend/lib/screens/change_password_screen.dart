import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_api.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// Self-service password change for any logged-in staff account (CPLO and
/// every other role) — reachable from Settings without admin intervention.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  String? _error;

  bool get _lenOk => _newController.text.length >= 8;
  bool get _matchOk =>
      _newController.text.isNotEmpty &&
      _newController.text == _confirmController.text;

  @override
  void initState() {
    super.initState();
    for (final c in [_currentController, _newController, _confirmController]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_currentController.text.isEmpty) {
      setState(() => _error = 'Enter your current password');
      return;
    }
    if (!_lenOk) {
      setState(() => _error = 'New password must be at least 8 characters');
      return;
    }
    if (!_matchOk) {
      setState(() => _error = 'New password and confirmation do not match');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final message = await AuthApi.changePassword(
        currentPassword: _currentController.text,
        newPassword: _newController.text,
        newPasswordConfirmation: _confirmController.text,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Password changed',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
          ),
          content: Text(message, style: GoogleFonts.poppins(height: 1.4)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.greyBg,
      body: Column(
        children: [
          GradientHeader(
            title: 'Change Password',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Transform.translate(
              offset: const Offset(0, -20),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(
                  color: AppColors.greyBg,
                  borderRadius: BorderRadius.only(
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
                          children: [
                            _passwordField(
                              controller: _currentController,
                              label: 'Current password',
                              obscure: _obscureCurrent,
                              onToggle: () => setState(
                                () => _obscureCurrent = !_obscureCurrent,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _passwordField(
                              controller: _newController,
                              label: 'New password',
                              obscure: _obscureNew,
                              onToggle: () =>
                                  setState(() => _obscureNew = !_obscureNew),
                            ),
                            const SizedBox(height: 14),
                            _passwordField(
                              controller: _confirmController,
                              label: 'Confirm new password',
                              obscure: _obscureConfirm,
                              onToggle: () => setState(
                                () => _obscureConfirm = !_obscureConfirm,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '• At least 8 characters',
                              style: GoogleFonts.poppins(
                                fontSize: 12.5,
                                color: _lenOk
                                    ? AppColors.primary
                                    : AppColors.secondaryText,
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                style: GoogleFonts.poppins(
                                  color: const Color(0xFFC62828),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            GradientButton(
                              onPressed: _submitting ? null : _submit,
                              label: _submitting
                                  ? 'Saving…'
                                  : 'Change password',
                            ),
                          ],
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
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }
}
