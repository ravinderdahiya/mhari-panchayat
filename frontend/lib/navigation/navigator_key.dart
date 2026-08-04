import 'package:flutter/material.dart';

/// The app's root navigator, exposed so code outside the widget tree (e.g.
/// API services reacting to a 401) can navigate without a [BuildContext].
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
