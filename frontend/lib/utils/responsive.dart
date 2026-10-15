import 'package:flutter/widgets.dart';

/// Tablet layouts key off the device's *shortest* side (Material's 600dp
/// compact/medium breakpoint), so a phone held in landscape stays a phone.
/// Every tablet-only branch in the app checks [ResponsiveContext.isTablet];
/// phones always take the original code path untouched.
abstract final class Breakpoints {
  static const double tablet = 600;

  /// Readable width for forms, detail pages and single-column content.
  static const double form = 720;

  /// Wider cap for lists / grids / dashboards laid out in multiple columns.
  static const double wide = 1100;
}

extension ResponsiveContext on BuildContext {
  bool get isTablet =>
      MediaQuery.sizeOf(this).shortestSide >= Breakpoints.tablet;
}

/// Centres [child] at [maxWidth] on tablets by padding it in from the
/// incoming constraints (so tight/loose height behaviour is unchanged).
/// On phones it returns [child] as-is.
class TabletConstrained extends StatelessWidget {
  const TabletConstrained({
    super.key,
    required this.child,
    this.maxWidth = Breakpoints.form,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!context.isTablet) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final extra = constraints.maxWidth - maxWidth;
        if (!constraints.hasBoundedWidth || extra <= 0) return child;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: extra / 2),
          child: child,
        );
      },
    );
  }
}

/// Horizontal inset that centres content at [maxWidth] inside
/// [availableWidth] (use with a LayoutBuilder's `constraints.maxWidth`, which
/// already excludes the tablet nav rail). Put it in a scroll view's `padding`
/// so the side margins still scroll. Returns [min] when there is no room.
double centeredGutter(
  double availableWidth,
  double maxWidth, {
  double min = 0,
}) {
  final extra = (availableWidth - maxWidth) / 2;
  return extra > min ? extra : min;
}

/// Number of columns for a card list: 1 on phones, 2 on tablets wide enough.
/// Pass the available width (e.g. from a LayoutBuilder).
int tabletColumns(
  BuildContext context,
  double availableWidth, {
  double minColumnWidth = 360,
}) {
  if (!context.isTablet) return 1;
  final width = availableWidth.clamp(0, Breakpoints.wide);
  return (width / minColumnWidth).floor().clamp(1, 3);
}
