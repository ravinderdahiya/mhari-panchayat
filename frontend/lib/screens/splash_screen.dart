import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';

import '../navigation/app_navigation.dart';
import '../navigation/role_navigation.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

typedef SplashCompleteCallback = void Function(AuthSession? session);

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onComplete});

  final SplashCompleteCallback? onComplete;

  static const Duration minDisplayDuration = Duration(seconds: 3);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _isBootstrapping = false;
  bool _hasFinished = false;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (_isBootstrapping || _hasFinished) return;
    _isBootstrapping = true;

    final startedAt = DateTime.now();
    final session = await AuthService.getSession();

    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < SplashScreen.minDisplayDuration) {
      await Future<void>.delayed(SplashScreen.minDisplayDuration - elapsed);
    }

    if (!mounted || _hasFinished) return;
    _hasFinished = true;
    _finish(session);
  }

  void _finish(AuthSession? session) {
    if (widget.onComplete != null) {
      widget.onComplete!(session);
      return;
    }

    final nextScreen = session != null && session.isValid
        ? dashboardForRole(session.role)
        : const LoginScreen();
    pushReplacement(context, nextScreen);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Stack(
            children: [
              const Positioned.fill(child: _SplashBackdrop()),
              Column(
                children: [
                  const Spacer(flex: 5),
                  const MhariPanchayatLogo(size: 132),
                  const SizedBox(height: 18),
                  Text(
                    'म्हारी पंचायत',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansDevanagari(
                      color: AppColors.secondary,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'सशक्त नागरिक, सक्षम पंचायत',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansDevanagari(
                      color: AppColors.secondaryText,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(flex: 6),
                  const SizedBox(
                    height: 220,
                    width: double.infinity,
                    child: _SplashVillageIllustration(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplashBackdrop extends StatelessWidget {
  const _SplashBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            AppColors.brandBlueTint.withValues(alpha: 0.5),
            AppColors.greenTint.withValues(alpha: 0.6),
          ],
        ),
      ),
    );
  }
}

/// Circular family + home mark used on the splash screen and login header.
class MhariPanchayatLogo extends StatelessWidget {
  const MhariPanchayatLogo({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Soft outer ring.
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = AppColors.greenTint.withValues(alpha: 0.6),
    );

    // Orange ground arc.
    final arcRect = Rect.fromCircle(center: center, radius: radius * 0.72);
    canvas.drawArc(
      arcRect,
      3.4,
      2.6,
      false,
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.16
        ..strokeCap = StrokeCap.round,
    );

    // House.
    final houseCenter = Offset(center.dx, center.dy + radius * 0.38);
    final houseW = radius * 0.5;
    final houseH = radius * 0.36;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: houseCenter, width: houseW, height: houseH),
        Radius.circular(radius * 0.04),
      ),
      Paint()..color = Colors.white,
    );
    final roof = Path()
      ..moveTo(houseCenter.dx - houseW * 0.65, houseCenter.dy - houseH * 0.4)
      ..lineTo(houseCenter.dx, houseCenter.dy - houseH * 1.1)
      ..lineTo(houseCenter.dx + houseW * 0.65, houseCenter.dy - houseH * 0.4)
      ..close();
    canvas.drawPath(roof, Paint()..color = AppColors.secondary);

    // Family figures.
    _drawFigure(
      canvas,
      Offset(center.dx, center.dy - radius * 0.22),
      radius * 0.24,
      AppColors.brandBlue,
    );
    _drawFigure(
      canvas,
      Offset(center.dx - radius * 0.36, center.dy - radius * 0.02),
      radius * 0.19,
      AppColors.secondary,
    );
    _drawFigure(
      canvas,
      Offset(center.dx + radius * 0.36, center.dy - radius * 0.02),
      radius * 0.19,
      const Color(0xFF66BB6A),
    );
  }

  void _drawFigure(Canvas canvas, Offset base, double scale, Color color) {
    final paint = Paint()..color = color;
    canvas.drawCircle(
      Offset(base.dx, base.dy - scale * 0.95),
      scale * 0.42,
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(base.dx - scale * 0.55, base.dy + scale * 0.55)
        ..quadraticBezierTo(
          base.dx - scale * 0.6,
          base.dy - scale * 0.25,
          base.dx,
          base.dy - scale * 0.45,
        )
        ..quadraticBezierTo(
          base.dx + scale * 0.6,
          base.dy - scale * 0.25,
          base.dx + scale * 0.55,
          base.dy + scale * 0.55,
        )
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SplashVillageIllustration extends StatelessWidget {
  const _SplashVillageIllustration();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _SplashVillagePainter(), size: Size.infinite);
  }
}

class _SplashVillagePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Distant hill (blue).
    final backHill = Path()
      ..moveTo(0, h * 0.62)
      ..quadraticBezierTo(w * 0.28, h * 0.42, w * 0.55, h * 0.58)
      ..quadraticBezierTo(w * 0.8, h * 0.72, w, h * 0.5)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(backHill, Paint()..color = const Color(0xFFBBDEFB));

    // Front hill (green).
    final frontHill = Path()
      ..moveTo(0, h * 0.8)
      ..quadraticBezierTo(w * 0.3, h * 0.62, w * 0.62, h * 0.76)
      ..quadraticBezierTo(w * 0.84, h * 0.86, w, h * 0.7)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(frontHill, Paint()..color = const Color(0xFFA5D6A7));

    // Sun.
    canvas.drawCircle(
      Offset(w * 0.16, h * 0.22),
      16,
      Paint()..color = const Color(0xFFFFCA28),
    );

    // Water tower.
    final towerX = w * 0.78;
    final towerBaseY = h * 0.62;
    canvas.drawRect(
      Rect.fromLTWH(towerX - 2, towerBaseY - 34, 4, 34),
      Paint()..color = const Color(0xFF90A4AE),
    );
    canvas.drawRect(
      Rect.fromLTWH(towerX - 22, towerBaseY - 34, 4, 34),
      Paint()..color = const Color(0xFF90A4AE),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(towerX - 10, towerBaseY - 44),
        width: 44,
        height: 24,
      ),
      Paint()..color = const Color(0xFF64B5F6),
    );

    // Tree.
    final treeCenter = Offset(w * 0.42, h * 0.58);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(treeCenter.dx, treeCenter.dy + 26),
          width: 10,
          height: 32,
        ),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFF8D6E63),
    );
    canvas.drawCircle(treeCenter, 28, Paint()..color = const Color(0xFF66BB6A));
    canvas.drawCircle(
      Offset(treeCenter.dx - 20, treeCenter.dy + 8),
      16,
      Paint()..color = const Color(0xFF81C784),
    );
    canvas.drawCircle(
      Offset(treeCenter.dx + 20, treeCenter.dy + 6),
      15,
      Paint()..color = const Color(0xFF81C784),
    );

    // Houses.
    _drawHouse(canvas, Offset(w * 0.2, h * 0.68), 1.0);
    _drawHouse(canvas, Offset(w * 0.6, h * 0.7), 0.85);
  }

  void _drawHouse(Canvas canvas, Offset base, double scale) {
    final bodyW = 40.0 * scale;
    final bodyH = 30.0 * scale;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: base, width: bodyW, height: bodyH),
        const Radius.circular(2),
      ),
      Paint()..color = Colors.white,
    );

    final roof = Path()
      ..moveTo(base.dx - bodyW * 0.62, base.dy - bodyH * 0.42)
      ..lineTo(base.dx, base.dy - bodyH)
      ..lineTo(base.dx + bodyW * 0.62, base.dy - bodyH * 0.42)
      ..close();
    canvas.drawPath(roof, Paint()..color = const Color(0xFFFFB74D));

    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(base.dx, base.dy + bodyH * 0.15),
        width: 10 * scale,
        height: 14 * scale,
      ),
      Paint()..color = const Color(0xFF8D6E63),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
