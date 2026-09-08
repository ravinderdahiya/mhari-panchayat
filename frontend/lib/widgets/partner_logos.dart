import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// HARSAC and Government of Haryana credential marks - each spins slowly and
/// continuously, the classic "seal" treatment for a partner/authority logo.
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

/// Rotates [child] in place, on an endless loop.
class SpinningLogo extends StatefulWidget {
  const SpinningLogo({super.key, required this.child});

  final Widget child;
  static const double size = 46;

  @override
  State<SpinningLogo> createState() => _SpinningLogoState();
}

class _SpinningLogoState extends State<SpinningLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: SizedBox(
        width: SpinningLogo.size,
        height: SpinningLogo.size,
        child: widget.child,
      ),
    );
  }
}
