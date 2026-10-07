/// RoUniity App Constants
///
/// Centralized configuration for the entire app — API endpoints,
/// alert thresholds, POI categories, and map settings.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppConstants {
  // ==================== Server ====================
  // Debug mode: Uses local network IP for physical device testing.
  // Make sure your PC is on 192.168.0.9 or update this IP.
  // Release mode: Uses Production VPS IP.
  static const String _localServer = 'http://10.8.3.129:3000';
  static const String _prodServer = 'https://rouniity.onrender.com';

  static String get serverBaseUrl => kReleaseMode ? _prodServer : _localServer;
  static String get serverWsUrl => kReleaseMode ? _prodServer : _localServer;

  // ==================== API Endpoints ====================
  static const String apiPrefix = '/api';

  // Auth
  static const String loginEndpoint = '$apiPrefix/auth/login';
  static const String registerEndpoint = '$apiPrefix/auth/register';
  static const String profileEndpoint = '$apiPrefix/auth/me';

  // Groups
  static const String groupsEndpoint = '$apiPrefix/groups';
  static const String joinGroupEndpoint = '$apiPrefix/groups/join';
  static const String myGroupsEndpoint = '$apiPrefix/groups/my';

  // Ola Maps Proxy
  static const String directionsEndpoint = '$apiPrefix/maps/directions';
  static const String nearbyEndpoint = '$apiPrefix/maps/nearby';
  static const String autocompleteEndpoint = '$apiPrefix/maps/autocomplete';
  static const String geocodeEndpoint = '$apiPrefix/maps/geocode';
  static const String reverseGeocodeEndpoint = '$apiPrefix/maps/reverse-geocode';
  static const String distanceMatrixEndpoint = '$apiPrefix/maps/distance-matrix';
  static const String snapToRoadEndpoint = '$apiPrefix/maps/snap-to-road';
  static const String apiUsageEndpoint = '$apiPrefix/maps/usage';
  static const String suggestWaypointsEndpoint = '$apiPrefix/maps/suggest-waypoints';
  static const String smartRouteEndpoint = '$apiPrefix/maps/smart-route';

  // ==================== Map Tiles ====================
  static const String olaVectorStyleUrl =
      'https://api.olamaps.io/tiles/vector/v1/styles/default-light-standard/style.json?api_key={key}';
  
  static const String olaApiKey = 'Txtd52X2o49O1UlPk7euny0DUhjd65VGQaMWzBoR';

  // ==================== Alert Thresholds ====================
  /// Distance from route polyline (meters) before deviation alert fires
  static const double deviationThresholdMeters = 500;

  /// Distance behind leader (meters) before separation alert fires
  static const double separationThresholdMeters = 2000;

  /// Minutes without movement before stall alert fires
  static const int stallTimeoutMinutes = 10;

  /// Location update interval in seconds (how often GPS is sent to server)
  static const int locationUpdateIntervalSeconds = 5;

  // ==================== Group Settings ====================
  /// Maximum members in a group
  static const int maxGroupMembers = 20;

  /// Invite code length
  static const int inviteCodeLength = 6;

  // ==================== POI Categories ====================
  /// Mapping of POI categories to their Ola Maps API type string
  static const Map<String, String> poiCategories = {
    'Fuel': 'gas_station',
    'Food': 'restaurant',
    'Hospital': 'hospital',
    'Hotel': 'lodging',
    'Parking': 'parking',
  };

  /// Route mode definitions for the intelligence layer
  static const Map<String, Map<String, String>> routeModes = {
    'highway': {
      'title': 'Highway',
      'subtitle': 'Fastest route. Highways, expressways, no detours.',
      'emoji': '🛣️',
    },
    'adventure': {
      'title': 'Adventure',
      'subtitle': 'Scenic detours, curvy roads, ghats & hill routes.',
      'emoji': '🏔️',
    },
    'full_adventure': {
      'title': 'Full Adventure',
      'subtitle': 'Jungle trails, water crossings, mountain passes.',
      'emoji': '🌊',
    },
  };

  /// Icons for each POI category (Material Design icons)
  static const Map<String, IconData> poiIcons = {
    'Fuel': Icons.local_gas_station_rounded,
    'Food': Icons.restaurant_rounded,
    'Hospital': Icons.local_hospital_rounded,
    'Hotel': Icons.hotel_rounded,
    'Parking': Icons.local_parking_rounded,
  };

  // ==================== Secure Storage Keys ====================
  static const String tokenKey = 'auth_token';
  static const String userIdKey = 'user_id';
  static const String userNameKey = 'user_name';
  static const String userEmailKey = 'user_email';
}
