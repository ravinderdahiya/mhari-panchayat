import 'package:geolocator/geolocator.dart';

/// Optional device coordinates for this login attempt, never a previous login.
class LoginLocation {
  LoginLocation._();

  static Future<Map<String, double>> capture() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return {};
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return {};
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return {'latitude': position.latitude, 'longitude': position.longitude};
    } catch (_) {
      // Permission denial or GPS failure must not prevent authentication.
      return {};
    }
  }
}
