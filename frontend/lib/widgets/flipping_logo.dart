import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Haryana emblem and HARSAC logo back-to-back, flipping every 5 seconds.
class FlippingLogo extends StatefulWidget {
  const FlippingLogo({super.key, this.size = 40});

  final double size;

  @override
  State<FlippingLogo> createState() => _FlippingLogoState();
}

class _FlippingLogoState extends State<FlippingLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      _controller.isCompleted ? _controller.reverse() : _controller.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final angle = Curves.easeInOut.transform(_controller.value) * math.pi;
        final showBack = angle > math.pi / 2;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.002)
            ..rotateY(angle),
          child: showBack
              // Counter-rotate so the back face isn't mirrored.
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.rotationY(math.pi),
                  child: Image.asset(
                    'assets/images/harsac_logo.png',
                    width: size,
                    height: size,
                  ),
                )
              : SvgPicture.asset(
                  'assets/images/haryana_emblem.svg',
                  width: size,
                  height: size,
                ),
        );
      },
    );
  }
}
