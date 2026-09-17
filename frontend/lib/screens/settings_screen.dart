import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../navigation/app_navigation.dart';
import '../navigation/navigator_key.dart';
import '../navigation/role_navigation.dart';
import '../services/app_preferences.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/common_widgets.dart';
import 'change_password_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _pushNotifications = true;
  bool _isEnglish = false;
  bool _loadingPrefs = true;

  /// Returns [english] when the English toggle is active, else [hindi] -
  /// same idiom login_screen.dart already uses for its own bilingual UI.
  String _t(String hindi, String english) => _isEnglish ? english : hindi;

  @override
  void initState() {
    super.initState();
    AppPreferences.getIsEnglish().then((value) {
      if (!mounted) return;
      setState(() {
        _isEnglish = value;
        _loadingPrefs = false;
      });
    });
  }

  Future<void> _setEnglish(bool value) async {
    setState(() => _isEnglish = value);
    await AppPreferences.setIsEnglish(value);
  }

  /// Most screens read colors from a plain `AppColors.*` static getter
  /// rather than `Theme.of(context)` (a ~22-screen retrofit, out of scope
  /// here - see app_theme.dart), so a screen already built before this
  /// toggle won't repaint on its own. Rebuilding the dashboard from scratch
  /// - skipping the splash screen's 3s minimum display - guarantees every
  /// visible screen re-reads the current color immediately, at the cost of
  /// resetting back to the shell's Home tab instead of wherever the user
  /// was mid-flow.
  Future<void> _setDark(bool value) async {
    await ThemeController.instance.setDark(value);
    final session = await AuthService.getSession();
    if (session == null || !mounted) return;
    rootNavigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => dashboardForSession(session)),
      (route) => false,
    );
  }

  Future<void> _pickLanguage() async {
    final choice = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  _t('भाषा चुनें', 'Choose language'),
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.mutedText,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              _LanguageOption(
                label: 'हिंदी',
                selected: !_isEnglish,
                onTap: () => Navigator.of(sheetContext).pop(false),
              ),
              _LanguageOption(
                label: 'English',
                selected: _isEnglish,
                onTap: () => Navigator.of(sheetContext).pop(true),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
    if (choice != null) await _setEnglish(choice);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPrefs) {
      return Scaffold(
        backgroundColor: AppColors.greyBg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.greyBg,
      body: Column(
        children: [
          GradientHeader(
            title: _t('सेटिंग्स', 'Settings'),
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
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.screen,
                  ),
                  children: [
                    _SectionLabel(_t('सामान्य', 'GENERAL')),
                    _SettingsGroup(
                      children: [
                        _ValueRow(
                          icon: Icons.translate_rounded,
                          title: _t('भाषा', 'Language'),
                          value: _isEnglish ? 'English' : 'हिंदी',
                          onTap: _pickLanguage,
                        ),
                        const _RowDivider(),
                        _ToggleRow(
                          icon: Icons.notifications_active_rounded,
                          title: _t('पुश सूचनाएं', 'Push notifications'),
                          value: _pushNotifications,
                          onChanged: (v) =>
                              setState(() => _pushNotifications = v),
                        ),
                        const _RowDivider(),
                        ValueListenableBuilder<bool>(
                          valueListenable: ThemeController.instance,
                          builder: (context, isDark, _) {
                            return _ToggleRow(
                              icon: Icons.dark_mode_rounded,
                              title: _t('डार्क मोड', 'Dark mode'),
                              value: isDark,
                              onChanged: _setDark,
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _SectionLabel(_t('खाता', 'ACCOUNT')),
                    _SettingsGroup(
                      children: [
                        _NavRow(
                          icon: Icons.lock_outline_rounded,
                          title: _t('पासवर्ड बदलें', 'Change password'),
                          onTap: () =>
                              push(context, const ChangePasswordScreen()),
                        ),
                        const _RowDivider(),
                        _NavRow(
                          icon: Icons.phone_iphone_rounded,
                          title: _t(
                            'मोबाइल नंबर बदलें',
                            'Change mobile number',
                          ),
                          onTap: () {},
                        ),
                        const _RowDivider(),
                        _NavRow(
                          icon: Icons.policy_rounded,
                          title: _t('गोपनीयता नीति', 'Privacy policy'),
                          onTap: () {},
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Center(
                      child: Text(
                        'Mhari Panchayat · v1.0.0',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppColors.mutedText,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        label,
        style: GoogleFonts.notoSansDevanagari(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: AppColors.primary)
          : null,
      onTap: onTap,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen + 4, 0, 0, 8),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.mutedText,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
      child: Card(child: Column(children: children)),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, indent: 56, color: AppColors.border);
  }
}

class _RowLeading extends StatelessWidget {
  const _RowLeading(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: AppColors.orangeTint,
      foregroundColor: AppColors.primary,
      child: Icon(icon, size: 19),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _RowLeading(icon),
      title: Text(
        title,
        style: GoogleFonts.notoSansDevanagari(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: GoogleFonts.notoSansDevanagari(
              fontSize: 14,
              color: AppColors.mutedText,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: AppColors.mutedText),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: _RowLeading(icon),
      title: Text(
        title,
        style: GoogleFonts.notoSansDevanagari(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      value: value,
      activeThumbColor: Colors.white,
      activeTrackColor: AppColors.secondary,
      onChanged: onChanged,
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _RowLeading(icon),
      title: Text(
        title,
        style: GoogleFonts.notoSansDevanagari(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: AppColors.mutedText,
      ),
      onTap: onTap,
    );
  }
}
