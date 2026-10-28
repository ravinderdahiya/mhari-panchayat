import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/user_role.dart';
import 'auth_service.dart';

/// Tells the server where a signed-in citizen is, once per app launch, so the
/// admin panel can show their district / tehsil / village. Silent and best-effort:
/// a denied permission, no GPS fix or no network just means nothing is saved.
class CitizenLocationSync {
  CitizenLocationSync._();

  static bool _done = false;

  static Future<void> run() async {
    if (_done) return;
    try {
      final session = await AuthService.getSession();
      if (session == null || !session.isValid || session.role != UserRole.citizen) return;
      _done = true;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      if (!await Geolocator.isLocationServiceEnabled()) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      );
      await http
          .put(
            Uri.parse('${ApiConfig.baseUrl}/api/auth/citizen/location'),
            headers: {
              'Authorization': 'Bearer ${session.token}',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'latitude': position.latitude, 'longitude': position.longitude}),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      // Location is a nice-to-have; never surface an error for it.
    }
  }
}
