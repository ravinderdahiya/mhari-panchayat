import 'package:flutter/material.dart';

/// Presentation-only mapping for backend-provided icon keys.
IconData assetTypeIcon(String iconKey) {
  return switch (iconKey) {
    'school' => Icons.school,
    'child_care' => Icons.child_care,
    'local_hospital' => Icons.local_hospital,
    'medical_services' => Icons.local_hospital_outlined,
    'pets' => Icons.pets,
    'account_balance' => Icons.account_balance,
    'groups' => Icons.groups,
    'woman' => Icons.people,
    'diversity_3' => Icons.groups_outlined,
    'forum' => Icons.forum,
    'stadium' => Icons.sports_soccer,
    'fitness_center' => Icons.fitness_center,
    'park' => Icons.park,
    'temple_hindu' => Icons.temple_hindu,
    'local_fire_department' => Icons.local_fire_department,
    'church' => Icons.church,
    'domain' => Icons.domain,
    'business' => Icons.business,
    'home_work' => Icons.home_work,
    'water_drop' => Icons.water_drop,
    'local_post_office' => Icons.local_post_office,
    'alt_route' => Icons.alt_route,
    'landscape' => Icons.landscape,
    'directions_bus' => Icons.directions_bus,
    'wb_sunny' => Icons.wb_sunny,
    'local_library' => Icons.local_library,
    'handshake' => Icons.volunteer_activism,
    'gavel' => Icons.gavel,
    'spa' => Icons.spa,
    'elderly' => Icons.elderly,
    _ => Icons.apartment,
  };
}
