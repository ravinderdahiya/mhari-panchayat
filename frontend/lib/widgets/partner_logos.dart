import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// HARSAC and Government of Haryana credential marks, shown static as the
/// classic "seal" treatment for a partner/authority logo.
/// Shown on the splash screen and the login screen.
class PartnerLogosRow extends StatelessWidget {
  const PartnerLogosRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'के सहयोग से',
          style: GoogleFonts.notoSansDevanagari(
            color: AppColors.secondaryText,
            fontSize: 11.5,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SpinningLogo(
              child: Image(
                image: AssetImage('assets/images/harsac_logo.png'),
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 28),
            SpinningLogo(
              child: SvgPicture.asset(
                'assets/images/haryana_emblem.svg',
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Renders [child] at the logo's fixed size, without any rotation.
class SpinningLogo extends StatelessWidget {
  const SpinningLogo({super.key, required this.child});

  final Widget child;
  static const double size = 46;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: size, height: size, child: child);
  }
}
