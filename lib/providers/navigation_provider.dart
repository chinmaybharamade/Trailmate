import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import '../services/websocket_service.dart';
import '../services/location_service.dart';
import '../services/ola_maps_service.dart';
import '../services/connectivity_service.dart';
import '../services/offline_cache_service.dart';
import '../services/fall_detection_service.dart';
import '../services/shake_detection_service.dart';
import '../providers/group_provider.dart';
import '../utils/polyline_decoder.dart';
import '../widgets/suggestion_card.dart';

enum TtsPriority { urgent, high, normal, low }

class TtsMessage {
  final String text;
  final TtsPriority priority;
  TtsMessage(this.text, this.priority);
}

/// Navigation Provider — manages live navigation state.
///
/// Holds member positions, route data, alerts, and nearby POIs.
class NavigationProvider extends ChangeNotifier {
  final WebSocketService _wsService = WebSocketService();
  final LocationService _locationService = LocationService();
  final OlaMapsService _olaMapsService = OlaMapsService();
  final ConnectivityService _connectivityService = ConnectivityService();
  final OfflineCacheService _offlineCacheService = OfflineCacheService();
  final FallDetectionService _fallDetectionService = FallDetectionService();
  final ShakeDetectionService _shakeDetectionService = ShakeDetectionService();
  final FlutterTts _tts = FlutterTts();
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  // Subscriptions
  final List<StreamSubscription> _subscriptions = [];

  // State
  String? _currentGroupId;
  GroupModel? _navigatingGroup;
  String? _currentUserId;
  String? _currentUserName;
  bool _isNavigating = false;
  Map<String, MemberPosition> _memberPositions = {};
  List<LatLng> _routePolyline = [];
  List<LatLng> _traveledPolyline = [];
  List<LatLng> _remainingPolyline = [];
  Position? _lastPolylineSplitPosition;
  List<RouteStep> _routeSteps = [];
  double _routeDistance = 0; // meters (initial total)
  double _routeDuration = 0; // seconds (initial total)
  double _remainingDistance = 0; // meters (dynamic, updates as you drive)
  double _remainingDuration = 0; // seconds (dynamic)
  List<AlertData> _activeAlerts = [];
  List<NearbyPlace> _nearbyPlaces = [];
  bool _isSosActive = false;
  String? _sosUserId;
  double? _initialRouteBearing;

  // Step tracking
  int _currentStepIndex = 0;
  double _distanceToNextStep = 0;

  // Rerouting
  bool _isRerouting = false;
  DateTime? _lastRerouteTime;
  int _consecutiveOffRoute = 0; // Tracks consecutive off-route GPS readings
  int _consecutiveWrongWay = 0; // Tracks consecutive wrong-way driving readings
  static const _rerouteCooldown = Duration(seconds: 10);
  static const _deviationThreshold = 15.0; // meters — perpendicular to segment

  // Arrival
  bool _hasArrived = false;
  bool _reachedLeader = false;
  DateTime? _tripStartTime;
  double _totalDistanceTraveled = 0; // meters

  // TTS
  bool _ttsEnabled = true;
  bool _hasSpokenApproachWarning = false;
  final List<TtsMessage> _ttsQueue = [];
  bool _isSpeaking = false;

  // Smart Suggestions
  WaypointSuggestion? _activeSuggestion;
  Timer? _suggestionTimer;
  DateTime? _lastMoveTime;

  // Quick Stops / Detour
  List<LatLng> _detourPolyline = [];
  List<RouteStep> _detourSteps = [];
  NearbyPlace? _selectedStop;
  String? _activeStopCategory;
  String _runtimeTransportMode = 'driving';

  // Offline Navigation
  bool _isOffline = false;
  bool _hasSpokenOfflineWarning = false; // "Rerouting unavailable offline" — speak once per offline stretch
  bool _wasOffRouteWhenOffline = false; // Track if user deviated while offline, for reroute on reconnect

  // Getters
  WebSocketService get wsService => _wsService;
  LocationService get locationService => _locationService;
  OlaMapsService get olaMapsService => _olaMapsService;
  String get runtimeTransportMode => _runtimeTransportMode;
  bool get isNavigating => _isNavigating;
  Map<String, MemberPosition> get memberPositions => _memberPositions;
  List<LatLng> get routePolyline => _routePolyline;
  List<LatLng> get traveledPolyline => _traveledPolyline;
  List<LatLng> get remainingPolyline => _remainingPolyline;
  List<RouteStep> get routeSteps => _routeSteps;
  RouteStep? get currentStep => _routeSteps.isNotEmpty && _currentStepIndex < _routeSteps.length ? _routeSteps[_currentStepIndex] : null;
  RouteStep? get upcomingStep => _routeSteps.isNotEmpty && _currentStepIndex + 1 < _routeSteps.length ? _routeSteps[_currentStepIndex + 1] : null;
  RouteStep? get nextUpcomingStep => _routeSteps.isNotEmpty && _currentStepIndex + 2 < _routeSteps.length ? _routeSteps[_currentStepIndex + 2] : null;
  double get distanceToNextStep => _distanceToNextStep;
  double get routeDistance => _routeDistance;
  double get routeDuration => _routeDuration;
  double get remainingDistance => _remainingDistance;
  double get remainingDuration => _remainingDuration;
  List<AlertData> get activeAlerts => _activeAlerts;
  List<NearbyPlace> get nearbyPlaces => _nearbyPlaces;
  bool get isSosActive => _isSosActive;
  String? get sosUserId => _sosUserId;
  double? get initialRouteBearing => _initialRouteBearing;
  bool get isRerouting => _isRerouting;
  bool get hasArrived => _hasArrived;
  DateTime? get tripStartTime => _tripStartTime;
  double get totalDistanceTraveled => _totalDistanceTraveled;
  bool get ttsEnabled => _ttsEnabled;
  WaypointSuggestion? get activeSuggestion => _activeSuggestion;
  List<LatLng> get detourPolyline => _detourPolyline;

  List<LatLng> _sosPolyline = [];
  List<LatLng> get sosPolyline => _sosPolyline;
  List<RouteStep> get detourSteps => _detourSteps;
  NearbyPlace? get selectedStop => _selectedStop;
  String? get activeStopCategory => _activeStopCategory;
  bool get isOffline => _isOffline;

  // Live Alternative Routes
  List<Map<String, dynamic>> _liveAlternativeRoutes = [];
  List<Map<String, dynamic>> get liveAlternativeRoutes => _liveAlternativeRoutes;
  Timer? _liveAlternativesTimer;

  final StreamController<bool> _fallSignalController = StreamController<bool>.broadcast();
  Stream<bool> get onFallSignal => _fallSignalController.stream;

  /// Initialize with auth token
  void initialize(String token, String currentUserId, String currentUserName) {
    _currentUserId = currentUserId;
    _currentUserName = currentUserName;
    _olaMapsService.setToken(token);
    _wsService.connect(token);
    _setupListeners();
    _initTts();
    _setupConnectivityListener();
    _initNotifications();
    _setupFallDetection();
    _setupShakeDetection();
  }

  void _initNotifications() async {
    const AndroidInitializationSettings initSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(android: initSettingsAndroid);
    await _localNotifications.initialize(settings: initSettings);
  }

  void _setupFallDetection() {
    _subscriptions.add(
      _fallDetectionService.onFallDetected.listen((_) async {
        debugPrint('[NavigationProvider] Fall detected! Triggering UI and Screen Wake');
        
        // Notify UI to push countdown screen
        _fallSignalController.add(true);

        // Wake screen using full-screen intent
        const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
          'sos_channel', 
          'SOS Alerts',
          channelDescription: 'Automatic SOS fall detection',
          importance: Importance.max,
          priority: Priority.high,
          fullScreenIntent: true,
          visibility: NotificationVisibility.public,
        );
        const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);
        await _localNotifications.show(
          id: 888, 
          title: 'Fall Detected', 
          body: 'Automatic SOS will be triggered.', 
          notificationDetails: platformDetails,
        );
      })
    );
  }

  void _setupShakeDetection() {
    _subscriptions.add(
      _shakeDetectionService.onShakeDetected.listen((_) async {
        debugPrint('[NavigationProvider] Shake detected! Triggering UI and Screen Wake');
        
        // Notify UI to push countdown screen
        _fallSignalController.add(true);

        // Wake screen using full-screen intent
        const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
          'sos_channel', 
          'SOS Alerts',
          channelDescription: 'Automatic SOS shake detection',
          importance: Importance.max,
          priority: Priority.high,
          fullScreenIntent: true,
          visibility: NotificationVisibility.public,
        );
        const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);
        await _localNotifications.show(
          id: 889, 
          title: 'Shake Detected', 
          body: 'Automatic SOS will be triggered.', 
          notificationDetails: platformDetails,
        );
      })
    );
  }

  /// Listen to connectivity changes and handle offline/online transitions.
  void _setupConnectivityListener() {
    _connectivityService.initialize();

    _subscriptions.add(
      _connectivityService.onConnectivityChanged.listen((online) {
        final wasOffline = _isOffline;
        _isOffline = !online;
        notifyListeners();

        if (online && wasOffline && _isNavigating) {
          // ── Connectivity restored while navigating ──
          debugPrint('[Navigation] Connectivity restored — recovering...');
          _queueSpeak('Connection restored.', priority: TtsPriority.normal);
          
          _activeAlerts.add(AlertData(
            type: 'network',
            userId: 'system',
            name: 'System',
            message: 'Connection restored!',
            timestamp: DateTime.now(),
          ));
          notifyListeners();

          // Re-subscribe to WebSocket group room
          _wsService.reconnectToGroup();

          // Flush offline location queue as a batch
          _flushOfflineLocationQueue();

          // Reroute if user was off-route while offline
          if (_wasOffRouteWhenOffline && !_isRerouting) {
            debugPrint('[Navigation] User was off-route while offline. Triggering reroute.');
            _wasOffRouteWhenOffline = false;
            _calculatePersonalRoute();
          }

          // Reset offline warning flag for next offline stretch
          _hasSpokenOfflineWarning = false;
        } else if (!online && _isNavigating) {
          // ── Going offline while navigating ──
          debugPrint('[Navigation] Went offline — switching to GPS-only navigation.');
          _queueSpeak('You are offline. GPS navigation is still active.', priority: TtsPriority.high);

          // Cache the current route to disk so it survives app kill
          _cacheCurrentRoute();
        }
      }),
    );
  }

  /// Flush the persisted offline location queue to the server as a batch.
  Future<void> _flushOfflineLocationQueue() async {
    try {
      final queue = await _offlineCacheService.loadLocationQueue();
      if (queue.isEmpty || _currentGroupId == null) return;

      debugPrint('[Navigation] Flushing ${queue.length} queued locations...');
      _wsService.sendLocationBatch(
        groupId: _currentGroupId!,
        locations: queue,
      );

      await _offlineCacheService.clearLocationQueue();
    } catch (e) {
      debugPrint('[Navigation] Failed to flush location queue: $e');
    }
  }

  /// Cache the current route data to disk for offline survival.
  Future<void> _cacheCurrentRoute() async {
    if (_navigatingGroup == null || _routeSteps.isEmpty) return;

    try {
      final stepsJson = _routeSteps.map((s) => {
        'distance': s.distance,
        'duration': s.duration,
        'instruction': s.instruction,
        'maneuver': s.maneuverType,
        'start_location': {'lat': s.location.latitude, 'lng': s.location.longitude},
        'end_location': {'lat': s.endLocation.latitude, 'lng': s.endLocation.longitude},
      }).toList();

      await _offlineCacheService.cacheActiveRoute(
        groupId: _currentGroupId ?? '',
        polyline: _navigatingGroup!.route.polyline ?? '',
        steps: stepsJson,
        destinationName: _navigatingGroup!.route.destination.name,
        destinationLat: _navigatingGroup!.route.destination.lat ?? 0,
        destinationLng: _navigatingGroup!.route.destination.lng ?? 0,
        originName: _navigatingGroup!.route.origin.name,
        originLat: _navigatingGroup!.route.origin.lat ?? 0,
        originLng: _navigatingGroup!.route.origin.lng ?? 0,
        distance: _routeDistance,
        duration: _routeDuration,
        transportMode: _runtimeTransportMode,
      );
    } catch (e) {
      debugPrint('[Navigation] Failed to cache route: $e');
    }
  }

  /// Initialize TTS engine
  void _initTts() {
    _tts.setLanguage('en-IN');
    _tts.setSpeechRate(0.5);
    _tts.setVolume(1.0);
    _tts.setPitch(1.0);
    
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      _processTtsQueue();
    });

    _tts.setCancelHandler(() {
      _isSpeaking = false;
      _processTtsQueue();
    });
  }

  /// Toggle TTS on/off
  void toggleTts() {
    _ttsEnabled = !_ttsEnabled;
    if (!_ttsEnabled) {
      _tts.stop();
      _ttsQueue.clear();
      _isSpeaking = false;
    }
    notifyListeners();
  }

  /// Queue a navigation instruction with priority
  void _queueSpeak(String text, {TtsPriority priority = TtsPriority.normal}) {
    if (!_ttsEnabled) return;

    if (priority == TtsPriority.urgent) {
      _tts.stop();
      _ttsQueue.clear();
      _isSpeaking = false;
      _ttsQueue.add(TtsMessage(text, priority));
      _processTtsQueue();
    } else if (priority == TtsPriority.high) {
      _tts.stop();
      _isSpeaking = false;
      _ttsQueue.insert(0, TtsMessage(text, priority));
      _processTtsQueue();
    } else {
      // Avoid spamming low priority messages
      if (priority == TtsPriority.low && _ttsQueue.length > 2) return;
      
      _ttsQueue.add(TtsMessage(text, priority));
      if (!_isSpeaking) _processTtsQueue();
    }
  }

  /// Process the next message in the queue
  Future<void> _processTtsQueue() async {
    if (_isSpeaking || _ttsQueue.isEmpty || !_ttsEnabled) return;

    _isSpeaking = true;
    final msg = _ttsQueue.removeAt(0);

    // Call await on speak, but use completion handler to proceed
    await _tts.speak(msg.text);
  }

  /// Set up WebSocket and location listeners
  void _setupListeners() {
    // Location updates from other members
    _subscriptions.add(
      _wsService.locationUpdates.listen((data) {
        final userId = data['userId'] as String?;
        // Don't overwrite local user's position from WS since we update it locally instantly
        if (userId != null && userId != _currentUserId) {
          _memberPositions[userId] = MemberPosition(
            userId: userId,
            name: data['name'] ?? '',
            lat: (data['lat'] as num).toDouble(),
            lng: (data['lng'] as num).toDouble(),
            speed: (data['speed'] as num?)?.toDouble() ?? 0,
            heading: (data['heading'] as num?)?.toDouble() ?? 0,
            status: data['status'] ?? 'on-route',
            timestamp: DateTime.now(),
          );
          notifyListeners();

          if (_routePolyline.isEmpty && _navigatingGroup != null && userId == _navigatingGroup!.leaderId && !_navigatingGroup!.isLeader(_currentUserId!)) {
            _calculatePersonalRoute();
          }
        }
      }),
    );

    // Initial member locations
    _subscriptions.add(
      _wsService.memberLocations.listen((members) {
        for (final m in members) {
          final userId = m['userId'] as String?;
          final loc = m['location'] as Map<String, dynamic>?;
          if (userId != null && loc != null && loc['lat'] != null) {
            _memberPositions[userId] = MemberPosition(
              userId: userId,
              name: m['name'] ?? '',
              lat: (loc['lat'] as num).toDouble(),
              lng: (loc['lng'] as num).toDouble(),
              speed: (loc['speed'] as num?)?.toDouble() ?? 0,
              heading: (loc['heading'] as num?)?.toDouble() ?? 0,
              status: m['status'] ?? 'waiting',
              timestamp: loc['updatedAt'] != null
                  ? DateTime.tryParse(loc['updatedAt']) ?? DateTime.now()
                  : DateTime.now(),
            );
          }
        }
        notifyListeners();

        if (_routePolyline.isEmpty && _navigatingGroup != null && _memberPositions.containsKey(_navigatingGroup!.leaderId) && !_navigatingGroup!.isLeader(_currentUserId!)) {
          _calculatePersonalRoute();
        }
      }),
    );

    // Alerts
    _subscriptions.add(
      _wsService.alerts.listen((data) {
        final type = data['type'] ?? 'unknown';
        final userId = data['userId'] ?? '';

        // Prevent flooding: ignore if an alert of this type for this user is already showing
        if (_activeAlerts.any((a) => a.type == type && a.userId == userId)) {
          return;
        }

        final alert = AlertData(
          type: type,
          userId: userId,
          name: data['name'] ?? '',
          message: data['message'] ?? '',
          timestamp: DateTime.now(),
        );

        _activeAlerts.add(alert);
        
        // Prevent screen overflow by capping at 3 alerts
        if (_activeAlerts.length > 3) {
          _activeAlerts.removeAt(0);
        }
        
        notifyListeners();

        // Speak high priority group alerts
        if (type == 'deviation') {
          _queueSpeak('Warning, ${data['name']} has deviated from the route.', priority: TtsPriority.high);
        } else if (type == 'separation') {
          _queueSpeak('${data['name']} has fallen behind the group.', priority: TtsPriority.high);
        } else if (type == 'regroup') {
          _queueSpeak('${data['name']} has requested a regroup at their location.', priority: TtsPriority.high);
          alert.onNavigate = () {
            if (data['lat'] != null && data['lng'] != null) {
              final regroupPlace = NearbyPlace(
                name: 'Regroup Location',
                type: 'Regroup',
                lat: data['lat'],
                lng: data['lng'],
              );
              selectStop(regroupPlace);
            }
          };
        } else if (type == 'stopRequest') {
          _queueSpeak('${data['name']} is requesting a stop for ${data['reason'] ?? 'a break'}.', priority: TtsPriority.high);
          alert.onNavigate = () {
            if (data['lat'] != null && data['lng'] != null) {
              final stopPlace = NearbyPlace(
                name: '${data['name']} Stop Request',
                type: 'Stop',
                lat: data['lat'],
                lng: data['lng'],
              );
              selectStop(stopPlace);
            }
          };
        } else if (type == 'backOnRoute') {
          _queueSpeak('${data['name']} is back on the route.', priority: TtsPriority.normal);
        }

        // Auto-remove THIS specific alert after 5 seconds (faster cleanup)
        Future.delayed(const Duration(seconds: 5), () {
          if (_activeAlerts.contains(alert)) {
            _activeAlerts.remove(alert);
            notifyListeners();
          }
        });

        // Auto-reroute if current user deviates
        if (type == 'deviation' && userId == _currentUserId) {
          _calculatePersonalRoute();
        }
      }),
    );

    // SOS events
    _subscriptions.add(
      _wsService.sosEvents.listen((data) {
        final type = data['type'] as String;
        if (type == 'triggered') {
          final userId = data['userId'];
          // Deduplicate SOS alerts for the same user
          if (_activeAlerts.any((a) => a.type == 'sos' && a.userId == userId)) {
            return;
          }

          _isSosActive = true;
          _sosUserId = userId;
          
          final lat = (data['lat'] as num?)?.toDouble();
          final lng = (data['lng'] as num?)?.toDouble();

          _activeAlerts.add(AlertData(
            type: 'sos',
            userId: userId ?? '',
            name: data['name'] ?? '',
            message: data['message'] ?? 'Emergency!',
            timestamp: DateTime.now(),
            lat: lat,
            lng: lng,
            onNavigate: (lat != null && lng != null) ? () => fetchSosRoute(lat, lng) : null,
          ));
          _queueSpeak('SOS Emergency! ${data['name']} needs help. SOS triggered.', priority: TtsPriority.urgent);
        } else if (type == 'cancelled') {
          _isSosActive = false;
          final userId = data['userId'];
          if (userId == _sosUserId) {
            _sosUserId = null;
            _sosPolyline = [];
          }
          _activeAlerts.removeWhere((a) => a.type == 'sos' && a.userId == userId);
          _queueSpeak('SOS has been cancelled.', priority: TtsPriority.high);
        }
        notifyListeners();
      }),
    );

    // Smart Suggestions
    _subscriptions.add(
      _wsService.suggestions.listen((data) {
        final suggestionData = data['suggestion'];
        if (suggestionData != null) {
          _activeSuggestion = WaypointSuggestion.fromJson(suggestionData);
          
          if (_activeSuggestion!.type == 'fatigue_break') {
            _queueSpeak('Fatigue warning. ${_activeSuggestion!.reason}', priority: TtsPriority.high);
          } else if (_activeSuggestion!.type == 'ai_waypoint') {
            _queueSpeak('Adventure stop ahead: ${_activeSuggestion!.name}.', priority: TtsPriority.normal);
          } else {
            _queueSpeak('Smart Suggestion: ${_activeSuggestion!.name}. ${_activeSuggestion!.reason}', priority: TtsPriority.low);
          }
          
          notifyListeners();
        }
      }),
    );

    // GPS location stream
    _subscriptions.add(
      _locationService.positionStream.listen((position) {
        if (_currentGroupId != null && _isNavigating && _currentUserId != null) {
          bool _dirty = false;
          
          // Reject low-confidence fixes outright
          if (position.accuracy > 30) return;
          
          final prevPos = _memberPositions[_currentUserId!];
          
          // Reject physically impossible jumps
          if (prevPos != null) {
            final dt = position.timestamp.difference(prevPos.timestamp).inMilliseconds / 1000.0;
            if (dt > 0) {
              final d = LocationService.distanceBetween(
                prevPos.lat, prevPos.lng, position.latitude, position.longitude);
              if (d / dt > 55) return; // ~200 km/h on a bike is a glitch
            }
          }
          
          // Track distance traveled
          if (prevPos != null) {
            final delta = LocationService.distanceBetween(
              prevPos.lat, prevPos.lng, position.latitude, position.longitude,
            );
            if (delta < 500) { // Ignore teleportation glitches
              _totalDistanceTraveled += delta;
            }
          }

          // Map Matching (snap to route if within 20m)
          double displayLat = position.latitude;
          double displayLng = position.longitude;
          if (_routePolyline.isNotEmpty && !_isRerouting) {
            final projection = _projectToRoute(position.latitude, position.longitude);
            if (projection.distance < 20.0) {
              displayLat = projection.point.latitude;
              displayLng = projection.point.longitude;
            }
          }

          // 1. Update local user position immediately for instant UI feedback
          _memberPositions[_currentUserId!] = MemberPosition(
            userId: _currentUserId!,
            name: _currentUserName ?? 'Me',
            lat: displayLat,
            lng: displayLng,
            speed: position.speed * 3.6,
            heading: position.heading,
            status: _memberPositions[_currentUserId!]?.status ?? 'on-route',
            timestamp: DateTime.now(),
          );
          _dirty = true;

          // 2. Broadcast to others (or queue if offline)
          if (!_isOffline) {
            _wsService.sendLocation(
              groupId: _currentGroupId!,
              lat: position.latitude,
              lng: position.longitude,
              speed: position.speed * 3.6, // m/s → km/h
              heading: position.heading,
            );
          } else {
            // Persist to disk queue (survives app kill)
            _offlineCacheService.enqueueLocation({
              'groupId': _currentGroupId!,
              'lat': position.latitude,
              'lng': position.longitude,
              'speed': position.speed * 3.6,
              'heading': position.heading,
              'timestamp': DateTime.now().toIso8601String(),
            });
          }

          // 3. Check deviation and separation (server-side, skip when offline)
          if (!_isOffline) {
            _wsService.checkDeviation(
              groupId: _currentGroupId!,
              lat: position.latitude,
              lng: position.longitude,
            );
            _wsService.checkSeparation(
              groupId: _currentGroupId!,
              lat: position.latitude,
              lng: position.longitude,
            );
          }

          // 4. Check deviation from route (Off-route auto-rerouting)
          if (_routePolyline.isNotEmpty && !_isRerouting) {
            // Calculate perpendicular distance to nearest polyline SEGMENT (not just vertices)
            final projection = _projectToRoute(position.latitude, position.longitude);
            final minDistance = projection.distance;
            final isWrongWay = _isWrongWay(position, projection.segmentIndex, minDistance);
            
            // --- SPLIT POLYLINE LOGIC ---
            // Throttle splitting logic: only recalculate if moved > 3 meters since last split
            final lastSplitPos = _lastPolylineSplitPosition;
            if (lastSplitPos == null || LocationService.distanceBetween(position.latitude, position.longitude, lastSplitPos.latitude, lastSplitPos.longitude) > 3) {
              _lastPolylineSplitPosition = position;
              if (projection.segmentIndex < _routePolyline.length) {
                // Slices the route: Traveled gets 0 to segmentIndex + the projection point
                _traveledPolyline = [
                  ..._routePolyline.sublist(0, projection.segmentIndex + 1),
                  projection.point,
                ];
                // Remaining gets the projection point + the rest of the route
                _remainingPolyline = [
                  projection.point,
                  ..._routePolyline.sublist(projection.segmentIndex + 1),
                ];
              }
            }
            
            // If user is more than threshold off the nearest route segment, trigger reroute
            if (minDistance > _deviationThreshold) {
              _consecutiveOffRoute++;
              _consecutiveWrongWay = 0;
              
              // Only reroute after 3 consecutive off-route readings (prevents GPS noise)
              if (_consecutiveOffRoute >= 3) {
                if (_isOffline) {
                  // Offline: can't reroute, speak warning ONCE per offline stretch
                  if (!_hasSpokenOfflineWarning) {
                    _hasSpokenOfflineWarning = true;
                    _wasOffRouteWhenOffline = true;
                    _queueSpeak('You are off route. Rerouting is unavailable offline.', priority: TtsPriority.high);
                  }
                } else {
                  // Online: normal rerouting logic
                  final now = DateTime.now();
                  if (_lastRerouteTime == null || now.difference(_lastRerouteTime!) > _rerouteCooldown) {
                    _lastRerouteTime = now;
                    _isRerouting = true;
                    _consecutiveOffRoute = 0;
                    _dirty = true;
                    debugPrint('[Navigation] User is ${minDistance.toStringAsFixed(1)}m off route for 3+ readings. Rerouting...');
                    _queueSpeak('Rerouting', priority: TtsPriority.normal);
                    _calculatePersonalRoute().whenComplete(() {
                      _isRerouting = false;
                      if (_remainingDistance < 15.0) {
                        _hasArrived = true;
                      }
                      notifyListeners();
                    });
                  }
                }
              }
            } else {
              _consecutiveOffRoute = 0; // Reset counter when back on route
              
              if (isWrongWay) {
                _consecutiveWrongWay++;
                if (_consecutiveWrongWay == 3) {
                  _queueSpeak('You are going the wrong way. Please turn around.', priority: TtsPriority.high);
                } else if (_consecutiveWrongWay > 3 && _consecutiveWrongWay % 10 == 0) {
                  _queueSpeak('You are still going the wrong way.', priority: TtsPriority.normal);
                }
              } else {
                _consecutiveWrongWay = 0;
              }
              
              // Reset offline off-route warning so it can fire again for a new deviation
              if (_hasSpokenOfflineWarning) {
                _hasSpokenOfflineWarning = false;
                _wasOffRouteWhenOffline = false;
              }
              
              if (_routeSteps.isNotEmpty && _currentStepIndex < _routeSteps.length) {
                // 4b. Responsive Step Progression
                // Advance past any steps the user has already passed.
                // A step is "passed" if the user is closer to the next step's
                // start location than to the current step's end location, OR
                // if the user is within 25m of the current step's end.
                bool advanced = true;
                while (advanced && _currentStepIndex < _routeSteps.length - 1) {
                  advanced = false;
                  final currentStepData = _routeSteps[_currentStepIndex];
                  final nextStepData = _routeSteps[_currentStepIndex + 1];

                  final distToCurrentEnd = LocationService.distanceBetween(
                    position.latitude, position.longitude,
                    currentStepData.endLocation.latitude, currentStepData.endLocation.longitude,
                  );

                  // Advance if: within 25m of current step's end
                  if (distToCurrentEnd < 25.0) {
                    _currentStepIndex++;
                    _hasSpokenApproachWarning = false;
                    final newStep = _routeSteps[_currentStepIndex];
                    _queueSpeak(newStep.instruction, priority: TtsPriority.normal);
                    _updateRemainingStats();
                    advanced = true;
                  }
                }

                // Now calculate the live distance to the current step's end
                final currentStepData = _routeSteps[_currentStepIndex];
                final distToTurn = LocationService.distanceBetween(
                  position.latitude, position.longitude,
                  currentStepData.endLocation.latitude, currentStepData.endLocation.longitude,
                );

                _distanceToNextStep = distToTurn;

                // Approach warning TTS at 200m
                if (distToTurn < 200.0 && !_hasSpokenApproachWarning && _currentStepIndex < _routeSteps.length - 1) {
                  _hasSpokenApproachWarning = true;
                  final nextStep = _routeSteps[_currentStepIndex + 1];
                  _queueSpeak('In ${distToTurn.round()} meters, ${nextStep.instruction}', priority: TtsPriority.normal);
                }

                // 4c. Arrival Detection
                if (_currentStepIndex >= _routeSteps.length - 1 && distToTurn < 50.0) {
                  final isLeader = _navigatingGroup?.isLeader(_currentUserId!) ?? true;
                  
                  if (isLeader) {
                    if (!_hasArrived) {
                      _hasArrived = true;
                      final destName = _selectedStop?.name ?? _navigatingGroup?.route.destination.name;
                      final message = destName != null && destName.isNotEmpty
                          ? 'You have reached your set $destName destination.'
                          : 'You have arrived at your destination.';
                      _queueSpeak(message, priority: TtsPriority.high);
                      _dirty = true;
                    }
                  } else {
                    if (!_reachedLeader) {
                      _reachedLeader = true;
                      _queueSpeak('You have caught up to the trip leader.', priority: TtsPriority.normal);
                      // Clear the route so we re-fetch if/when the leader moves further away
                      _routePolyline = [];
                      _traveledPolyline = [];
                      _remainingPolyline = [];
                      _lastPolylineSplitPosition = null;
                      _routeSteps = [];
                      _currentStepIndex = 0;
                      _dirty = true;
                    }
                  }
                }

                _dirty = true;
              }
            }
          }

          if (_dirty) {
            notifyListeners();
          }

          // 5. Calculate route if not done yet (e.g. initial start) — skip if offline
          if (_routePolyline.isEmpty && _navigatingGroup != null && !_isRerouting && !_isOffline) {
            _calculatePersonalRoute();
          }
        }
      }),
    );
  }

  /// Projects a point onto the nearest polyline segment, returning the minimum distance,
  /// the index of that segment, and the exact projected coordinate.
  ({double distance, int segmentIndex, LatLng point}) _projectToRoute(double lat, double lng) {
    if (_routePolyline.length < 2) {
      if (_routePolyline.isNotEmpty) {
        return (
          distance: LocationService.distanceBetween(lat, lng, _routePolyline[0].latitude, _routePolyline[0].longitude),
          segmentIndex: 0,
          point: _routePolyline[0],
        );
      }
      return (distance: double.infinity, segmentIndex: 0, point: const LatLng(0, 0));
    }

    double minDist = double.infinity;
    int minIndex = 0;
    LatLng minPoint = _routePolyline[0];

    for (int i = 0; i < _routePolyline.length - 1; i++) {
      final a = _routePolyline[i];
      final b = _routePolyline[i + 1];
      
      final dx = b.longitude - a.longitude;
      final dy = b.latitude - a.latitude;
      final lenSq = dx * dx + dy * dy;

      double projLat, projLng;

      if (lenSq == 0) {
        projLat = a.latitude;
        projLng = a.longitude;
      } else {
        double t = ((lng - a.longitude) * dx + (lat - a.latitude) * dy) / lenSq;
        if (t < 0) t = 0;
        if (t > 1) t = 1;
        projLat = a.latitude + t * dy;
        projLng = a.longitude + t * dx;
      }

      final dist = LocationService.distanceBetween(lat, lng, projLat, projLng);
      if (dist < minDist) {
        minDist = dist;
        minIndex = i;
        minPoint = LatLng(projLat, projLng);
      }
    }

    return (distance: minDist, segmentIndex: minIndex, point: minPoint);
  }

  /// Check if the user is driving the wrong way along the route
  bool _isWrongWay(Position position, int segmentIndex, double minDistance) {
    if (_routePolyline.length < 2) return false;
    // Don't calculate wrong way if moving too slow or off route (1.5 m/s = 5.4 km/h)
    if (position.speed < 1.5 || minDistance > _deviationThreshold) return false;

    if (segmentIndex >= _routePolyline.length - 1) return false;

    final a = _routePolyline[segmentIndex];
    final b = _routePolyline[segmentIndex + 1];
    final nearestSegmentBearing = LocationService.bearingBetween(a.latitude, a.longitude, b.latitude, b.longitude);
    
    double diff = (position.heading - nearestSegmentBearing).abs();
    if (diff > 180) diff = 360 - diff;
    
    // If bearing difference is > 120 degrees, they are driving the wrong way
    return diff > 120;
  }

  /// Recalculate remaining distance/duration from current step onward
  void _updateRemainingStats() {
    double dist = 0;
    double dur = 0;
    for (int i = _currentStepIndex; i < _routeSteps.length; i++) {
      dist += _routeSteps[i].distance;
      dur += _routeSteps[i].duration;
    }
    _remainingDistance = dist;
    _remainingDuration = dur;
  }

  /// Start navigation for a group
  Future<void> startNavigation(GroupModel group) async {
    _currentGroupId = group.id;
    _navigatingGroup = group;
    _isNavigating = true;
    _runtimeTransportMode = group.route.transportMode;
    _hasArrived = false;
    _reachedLeader = false;
    _tripStartTime = DateTime.now();
    _totalDistanceTraveled = 0;
    _currentStepIndex = 0;
    _routeDistance = group.route.distanceMeters.toDouble();
    _routeDuration = group.route.durationSeconds.toDouble();
    _remainingDistance = _routeDistance;
    _remainingDuration = _routeDuration;
    _isRerouting = false;
    _lastRerouteTime = null;
    _consecutiveOffRoute = 0;

    // Subscribe to group WebSocket room
    _wsService.subscribeToGroup(group.id);

    // Start suggestion timer (checks every 5 minutes)
    _suggestionTimer = Timer.periodic(const Duration(minutes: 5), (_) => _checkSuggestions());
    _lastMoveTime = DateTime.now();

    // Start GPS tracking
    final hasPermission = await _locationService.requestPermissions();
    if (hasPermission) {
      _locationService.startTracking();
      _fallDetectionService.start();
      _shakeDetectionService.start();
    }

    // Context-Aware Night Driving Advisory
    final hour = DateTime.now().hour;
    if (hour >= 18 || hour < 6) {
      _queueSpeak('Night driving mode. Please drive safely, ensure your headlights are on, and maintain a safe following distance.', priority: TtsPriority.low);
    }

    // Use the group's predefined route polyline initially
    if (group.route.polyline?.isNotEmpty == true) {
      _routePolyline = decodePolyline(group.route.polyline!);
      _traveledPolyline = [];
      _remainingPolyline = List.from(_routePolyline);
      _lastPolylineSplitPosition = null;
      
      // Load steps from the group route so DirectionsBanner can display instructions
      if (group.route.steps.isNotEmpty) {
        _routeSteps = group.route.steps
            .map((s) => RouteStep.fromJson(s as Map<String, dynamic>))
            .toList();
      }
      
      // We do not call _calculatePersonalRoute() here if the user is the leader 
      // because we want to preserve their custom start point rather than immediately
      // because we want to preserve their custom start point rather than immediately
      // routing from their current GPS location.
    }

    // Start live alternatives fetching
    _liveAlternativesTimer?.cancel();
    _liveAlternativesTimer = Timer.periodic(const Duration(minutes: 2), (_) => fetchLiveAlternatives());
    fetchLiveAlternatives(); // Fetch initially too

    notifyListeners();

    if (_locationService.lastPosition != null) {
      if (_currentUserId != null && !group.isLeader(_currentUserId!)) {
        await _calculatePersonalRoute();
      }
    }
  }

  void setTransportMode(String mode) {
    if (_runtimeTransportMode != mode) {
      _runtimeTransportMode = mode;
      notifyListeners();
      _calculatePersonalRoute();
    }
  }

  /// Stop navigation
  void stopNavigation() {
    if (_currentGroupId != null) {
      _wsService.unsubscribeFromGroup(_currentGroupId!);
    }
    _locationService.stopTracking();
    _offlineCacheService.clearAll();
    _tts.stop();
    _isNavigating = false;
    _currentGroupId = null;
    _isNavigating = false;
    _routePolyline = [];
    _traveledPolyline = [];
    _remainingPolyline = [];
    _lastPolylineSplitPosition = null;
    _routeSteps = [];
    _memberPositions.clear();
    _activeAlerts.clear();
    _activeSuggestion = null;
    _suggestionTimer?.cancel();
    _locationService.stopTracking();
    _fallDetectionService.stop();
    _shakeDetectionService.stop();
    _wsService.disconnect();
    
    // Clear offline cache
    _offlineCacheService.clearRouteCache();
    _offlineCacheService.clearLocationQueue();
    _nearbyPlaces.clear();
    _isSosActive = false;
    _sosUserId = null;
    _initialRouteBearing = null;
    _hasArrived = false;
    _isRerouting = false;
    _currentStepIndex = 0;
    _distanceToNextStep = 0;
    _consecutiveOffRoute = 0;
    _suggestionTimer?.cancel();
    _activeSuggestion = null;
    notifyListeners();
  }

  /// Reset arrival state (for dismissing the arrival screen)
  void dismissArrival() {
    _hasArrived = false;
    // Clear route to prevent arrival from immediately triggering again 
    // on the next GPS update while staying in the active navigation session.
    _routePolyline.clear();
    _traveledPolyline.clear();
    _remainingPolyline.clear();
    _lastPolylineSplitPosition = null;
    _routeSteps.clear();
    _currentStepIndex = 0;
    _remainingDistance = 0;
    _remainingDuration = 0;
    if (_selectedStop != null) {
      clearStop();
    }
    notifyListeners();
  }

  /// Set route polyline (decoded from directions API)
  void setRoutePolyline(List<LatLng> points) {
    _routePolyline = points;
    _traveledPolyline = [];
    _remainingPolyline = List.from(_routePolyline);
    _lastPolylineSplitPosition = null;
    notifyListeners();
  }

  /// Calculates personal route from current position to destination
  Future<void> _calculatePersonalRoute() async {
    if (_navigatingGroup == null || _currentUserId == null) return;
    
    final me = _locationService.lastPosition;
    if (me == null) return;

    double destLat;
    double destLng;

    if (_navigatingGroup!.isLeader(_currentUserId!)) {
      final dest = _navigatingGroup!.route.destination;
      if (!dest.hasLocation) return;
      destLat = dest.lat!;
      destLng = dest.lng!;
    } else {
      final leaderId = _navigatingGroup!.leaderId;
      final leaderPos = _memberPositions[leaderId];
      if (leaderPos == null) {
        debugPrint('[Navigation] Waiting for leader position to route.');
        return;
      }
      destLat = leaderPos.lat;
      destLng = leaderPos.lng;
    }

    try {
      final List<Map<String, double>> routeWaypoints = [];
      if (_navigatingGroup!.isLeader(_currentUserId!)) {
        if (_navigatingGroup!.route.waypoints.isNotEmpty) {
          routeWaypoints.addAll(_navigatingGroup!.route.waypoints.map((w) => {'lat': w.lat, 'lng': w.lng}));
        }
        if (_navigatingGroup!.route.aiWaypoints.isNotEmpty) {
          routeWaypoints.addAll(_navigatingGroup!.route.aiWaypoints.map((w) => {'lat': w.lat, 'lng': w.lng}));
        }
      }

      final result = await _olaMapsService.getDirections(
        originLat: me.latitude,
        originLng: me.longitude,
        destLat: destLat,
        destLng: destLng,
        waypoints: routeWaypoints.isNotEmpty ? routeWaypoints : null,
        mode: _runtimeTransportMode,
      );

      final routes = result['routes'] as List?;
      if (routes != null && routes.isNotEmpty) {
        final route = routes[0];
        
        // Parse Polyline
        dynamic polylineData = route['overview_polyline'] ?? route['geometry'];
        if (polylineData is Map) {
          polylineData = polylineData['points'];
        }
        final polylineStr = polylineData as String?;
        if (polylineStr != null && polylineStr.isNotEmpty) {
          final points = decodePolyline(polylineStr);
          if (points.isNotEmpty) {
            points.insert(0, LatLng(me.latitude, me.longitude));
          }
          setRoutePolyline(points);
          
          if (points.length >= 2) {
            _initialRouteBearing = LocationService.bearingBetween(
              points[0].latitude, points[0].longitude,
              points[1].latitude, points[1].longitude,
            );
          }
        }

        // Parse distance and duration (from all legs)
        final legs = route['legs'] as List?;
        if (legs != null && legs.isNotEmpty) {
          double totalDistance = 0;
          double totalDuration = 0;
          List<RouteStep> allSteps = [];

          for (final leg in legs) {
            totalDistance += (leg['distance'] as num?)?.toDouble() ?? 0;
            totalDuration += (leg['duration'] as num?)?.toDouble() ?? 0;
            
            final stepsJson = leg['steps'] as List?;
            if (stepsJson != null) {
              allSteps.addAll(stepsJson.map((s) => RouteStep.fromJson(s)));
            }
          }

          _routeDistance = totalDistance;
          _routeDuration = totalDuration;
          _remainingDistance = _routeDistance;
          _remainingDuration = _routeDuration;

          _routeSteps = allSteps;
          _currentStepIndex = 0;
          _hasSpokenApproachWarning = false;
          _distanceToNextStep = _routeSteps.isNotEmpty ? _routeSteps[0].distance : 0;
          
          // Speak first instruction
          if (_routeSteps.isNotEmpty) {
            _queueSpeak(_routeSteps[0].instruction, priority: TtsPriority.normal);
          }
        } else {
          _routeDistance = 0;
          _routeDuration = 0;
          _remainingDistance = 0;
          _remainingDuration = 0;
          _routeSteps = [];
          _currentStepIndex = 0;
          _distanceToNextStep = 0;
        }
        
        _reachedLeader = false;
        notifyListeners();
        debugPrint('[Navigation] Personal route calculated: ${_routeDistance}m, ${_routeSteps.length} steps');
        
        // Cache this new route so it's ready in case of sudden network drop
        _cacheCurrentRoute();
      }
    } catch (e) {
      debugPrint('[Navigation] Failed to calculate personal route: $e');
    }
  }

  /// Fetch nearby places of a given type
  Future<void> fetchNearbyPlaces(double lat, double lng, String type, {int radius = 1500}) async {
    try {
      final result = await _olaMapsService.nearbySearch(
        lat: lat,
        lng: lng,
        type: type,
        radius: radius,
      );

      final predictions = result['predictions'] as List? ?? [];
      if (predictions.isNotEmpty) {
        debugPrint('Raw first prediction: ${predictions.first}');
      }
      _nearbyPlaces = predictions.map((p) {
        final place = NearbyPlace.fromJson(p);
        debugPrint('Parsed place: ${place.name} -> lat: ${place.lat}, lng: ${place.lng}');
        if (place.lat != null && place.lng != null) {
          final distanceMeters = const Distance().as(
            LengthUnit.Meter,
            LatLng(lat, lng),
            LatLng(place.lat!, place.lng!),
          );
          return place.copyWith(distance: distanceMeters.toDouble());
        }
        return place;
      }).where((place) {
        final name = place.name.toLowerCase();
        if (type == 'gas_station') {
          if (name.contains('water') || name.contains('pumping station') || name.contains('pump house')) {
            if (!name.contains('petrol') && !name.contains('fuel')) {
              return false;
            }
          }
        } else if (type == 'restaurant') {
          if (name.contains('bus stop') || name.contains('bus stand') || name.contains('metro station')) {
            if (!name.contains('restaurant') && !name.contains('cafe') && !name.contains('food')) {
              return false;
            }
          }
        }
        return true;
      }).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Nearby search error: $e');
    }
  }

  /// Clear alerts
  void clearAlerts() {
    _activeAlerts.clear();
    notifyListeners();
  }

  /// Dismiss a specific alert
  void dismissAlert(int index) {
    if (index < _activeAlerts.length) {
      _activeAlerts.removeAt(index);
      notifyListeners();
    }
  }

  /// Dismiss the active suggestion
  void dismissSuggestion() {
    _activeSuggestion = null;
    notifyListeners();
  }

  /// Select a nearby stop and fetch detour route to it
  Future<void> selectStop(NearbyPlace stop) async {
    _selectedStop = stop;
    notifyListeners();

    // Fetch route from current position to the stop
    final pos = _locationService.lastPosition;
    if (pos != null && stop.lat != null && stop.lng != null) {
      debugPrint('==== FETCHING DETOUR ====');
      debugPrint('Origin: ${pos.latitude}, ${pos.longitude}');
      debugPrint('Dest: ${stop.lat}, ${stop.lng}');
      try {
        final result = await _olaMapsService.getDirections(
          originLat: pos.latitude,
          originLng: pos.longitude,
          destLat: stop.lat!,
          destLng: stop.lng!,
          mode: _runtimeTransportMode,
        );

        debugPrint('Detour API Response status: ${result['status'] ?? 'No Status'}');
        
        // Parse polyline from response
        final routes = result['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final overviewPolyline = routes[0]['overview_polyline'];
          debugPrint('Overview Polyline Object: $overviewPolyline');
          if (overviewPolyline != null) {
            final encoded = overviewPolyline is String ? overviewPolyline : overviewPolyline['points'];
            if (encoded is String) {
              _detourPolyline = decodePolyline(encoded);
              debugPrint('Decoded detour points count: ${_detourPolyline.length}');
            } else {
              debugPrint('Encoded polyline is not a string: $encoded');
            }
          } else {
            debugPrint('No overview_polyline in route');
          }
          
          // Parse detour steps
          _detourSteps.clear();
          final legs = routes[0]['legs'] as List?;
          if (legs != null && legs.isNotEmpty) {
            final steps = legs[0]['steps'] as List?;
            if (steps != null) {
              for (final step in steps) {
                try {
                  _detourSteps.add(RouteStep.fromJson(step));
                } catch (e) {
                  debugPrint('Error parsing detour step: $e');
                }
              }
            }
          }
        } else {
          debugPrint('No routes found in API response for detour');
        }
        notifyListeners();
      } catch (e, stackTrace) {
        debugPrint('Detour error: $e\n$stackTrace');
      }
    } else {
      debugPrint('Cannot fetch detour: pos=$pos, lat=${stop.lat}, lng=${stop.lng}');
    }
  }

  /// Fetches an SOS route to a distressed user and renders it as a red polyline
  Future<void> fetchSosRoute(double destLat, double destLng) async {
    if (_locationService.lastPosition == null) {
      debugPrint('Cannot fetch SOS route: pos is null');
      return;
    }
    debugPrint('==== FETCHING SOS ROUTE ====');
    try {
      final pos = _locationService.lastPosition!;
      final result = await _olaMapsService.getDirections(
        originLat: pos.latitude,
        originLng: pos.longitude,
        destLat: destLat,
        destLng: destLng,
        mode: _runtimeTransportMode,
      );

      debugPrint('SOS API Response status: ${result['status'] ?? 'No Status'}');
      
      final routes = result['routes'] as List?;
      if (routes != null && routes.isNotEmpty) {
        final route = routes.first;
        final overviewPolyline = route['overview_polyline'];
        debugPrint('Overview Polyline Object for SOS: $overviewPolyline');
        if (overviewPolyline != null) {
          final encoded = overviewPolyline['points'] ?? overviewPolyline;
          if (encoded is String) {
            _sosPolyline = decodePolyline(encoded);
            debugPrint('Decoded SOS points count: ${_sosPolyline.length}');
            notifyListeners();
          } else {
            debugPrint('Encoded SOS polyline is not a string: $encoded');
          }
        } else {
          debugPrint('No overview_polyline in SOS route');
        }
      } else {
        debugPrint('No routes found in API response for SOS');
      }
    } catch (e, stackTrace) {
      debugPrint('SOS routing error: $e\n$stackTrace');
    }
  }


  /// Clear the selected stop and detour route
  void clearStop() {
    _selectedStop = null;
    _detourPolyline = [];
    _detourSteps = [];
    _activeStopCategory = null;
    notifyListeners();
  }

  /// Set the active stop category (for highlighting in the UI)
  void setActiveStopCategory(String? category) {
    _activeStopCategory = category;
    notifyListeners();
  }

  /// Periodic check for smart suggestions
  void _checkSuggestions() {
    if (_navigatingGroup == null || _currentUserId == null || !_navigatingGroup!.isLeader(_currentUserId!)) {
      return; // Only leader checks for suggestions
    }

    final pos = _locationService.lastPosition;
    if (pos == null) return;

    final elapsedMinutes = _tripStartTime != null ? DateTime.now().difference(_tripStartTime!).inMinutes.toDouble() : 0.0;
    
    // Check if stopped for > 3 minutes
    bool isStopped = false;
    if (pos.speed < 1.0) {
      if (_lastMoveTime != null && DateTime.now().difference(_lastMoveTime!).inMinutes >= 3) {
        isStopped = true;
      }
    } else {
      _lastMoveTime = DateTime.now();
    }

    _wsService.checkSuggestions(
      groupId: _navigatingGroup!.id,
      lat: pos.latitude,
      lng: pos.longitude,
      elapsedMinutes: elapsedMinutes,
      distanceTraveled: _totalDistanceTraveled,
      isStopped: isStopped,
    );
  }

  Future<void> fetchLiveAlternatives() async {
    if (!_isNavigating || _navigatingGroup == null || _locationService.lastPosition == null || _isOffline) return;
    
    try {
      final pos = _locationService.lastPosition!;
      final destLat = _navigatingGroup!.route.destination.lat ?? 0;
      final destLng = _navigatingGroup!.route.destination.lng ?? 0;
      
      final res = await _olaMapsService.getDirections(
        originLat: pos.latitude,
        originLng: pos.longitude,
        destLat: destLat,
        destLng: destLng,
        mode: _runtimeTransportMode,
        alternatives: true,
      );
      
      if (res['routes'] != null && (res['routes'] as List).length > 1) {
         _liveAlternativeRoutes = (res['routes'] as List).map((route) {
            int duration = 0;
            if (route['legs'] != null && route['legs'].isNotEmpty) {
              duration = (route['legs'][0]['duration'] as num).toInt();
            }
            return {
              'polyline': route['overview_polyline'] ?? route['geometry'],
              'duration': duration,
              'route': route, 
            };
         }).toList();
         notifyListeners();
      }
    } catch (e) {
      debugPrint('[Navigation] Failed to fetch live alternatives: $e');
    }
  }

  Future<void> switchToAlternativeRoute(Map<String, dynamic> routeData) async {
    final route = routeData['route'];
    final polyline = route['overview_polyline'] ?? route['geometry'];
    if (polyline != null) {
      _routePolyline = decodePolyline(polyline);
      _traveledPolyline = [];
      _remainingPolyline = List.from(_routePolyline);
      _lastPolylineSplitPosition = null;
      
      if (route['legs'] != null && (route['legs'] as List).isNotEmpty) {
        _routeDistance = (route['legs'][0]['distance'] as num).toDouble();
        _routeDuration = (route['legs'][0]['duration'] as num).toDouble();
        
        final rawSteps = route['legs'][0]['steps'] as List;
        _routeSteps = rawSteps.map((s) => RouteStep.fromJson(s as Map<String, dynamic>)).toList();
      }
      
      _currentStepIndex = 0;
      _remainingDistance = _routeDistance;
      _remainingDuration = _routeDuration;
      
      // Clear the live alternatives since we switched
      _liveAlternativeRoutes.clear();
      
      _queueSpeak('Route updated', priority: TtsPriority.high);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _wsService.dispose();
    _locationService.dispose();
    _tts.stop();
    super.dispose();
  }
}

// ==================== Data Models ====================

class MemberPosition {
  final String userId;
  final String name;
  final double lat;
  final double lng;
  final double speed;
  final double heading;
  final String status;
  final DateTime timestamp;

  MemberPosition({
    required this.userId,
    required this.name,
    required this.lat,
    required this.lng,
    this.speed = 0,
    this.heading = 0,
    this.status = 'on-route',
    required this.timestamp,
  });

  LatLng get latLng => LatLng(lat, lng);
}

class AlertData {
  final String type;
  final String userId;
  final String name;
  final String message;
  final DateTime timestamp;
  final double? lat;
  final double? lng;
  VoidCallback? onNavigate;

  AlertData({
    required this.type,
    required this.userId,
    required this.name,
    required this.message,
    required this.timestamp,
    this.lat,
    this.lng,
    this.onNavigate,
  });
}

class NearbyPlace {
  final String name;
  final String? address;
  final double? lat;
  final double? lng;
  final double? rating;
  final String? type;
  final double? distance;

  NearbyPlace({
    required this.name,
    this.address,
    this.lat,
    this.lng,
    this.rating,
    this.type,
    this.distance,
  });

  NearbyPlace copyWith({
    String? name,
    String? address,
    double? lat,
    double? lng,
    double? rating,
    String? type,
    double? distance,
  }) {
    return NearbyPlace(
      name: name ?? this.name,
      address: address ?? this.address,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      rating: rating ?? this.rating,
      type: type ?? this.type,
      distance: distance ?? this.distance,
    );
  }

  factory NearbyPlace.fromJson(Map<String, dynamic> json) {
    final geometry = json['geometry'] as Map<String, dynamic>?;
    final location = geometry?['location'] as Map<String, dynamic>?;

    return NearbyPlace(
      name: json['structured_formatting']?['main_text'] ??
          json['description'] ??
          json['name'] ??
          '',
      address: json['structured_formatting']?['secondary_text'] ??
          json['formatted_address'],
      lat: (location?['lat'] as num?)?.toDouble(),
      lng: (location?['lng'] as num?)?.toDouble(),
      rating: (json['rating'] as num?)?.toDouble(),
      type: json['type'],
    );
  }
}

class RouteStep {
  final double distance;
  final double duration;
  final String instruction;
  final String maneuverType;
  final LatLng location;
  final LatLng endLocation;

  RouteStep({
    required this.distance,
    required this.duration,
    required this.instruction,
    required this.maneuverType,
    required this.location,
    required this.endLocation,
  });

  factory RouteStep.fromJson(Map<String, dynamic> json) {
    // Debug: log the raw step JSON to understand the API response
    debugPrint('[RouteStep] Raw step keys: ${json.keys.toList()}');
    debugPrint('[RouteStep] maneuver raw: ${json['maneuver']} (${json['maneuver'].runtimeType})');
    debugPrint('[RouteStep] instruction raw: ${json['instruction'] ?? json['instructions'] ?? json['html_instructions']}');

    // ── Parse locations ──
    final startLoc = json['start_location'] as Map<String, dynamic>?;
    LatLng latLng = const LatLng(0, 0);
    if (startLoc != null) {
      latLng = LatLng(
        (startLoc['lat'] as num?)?.toDouble() ?? 0,
        (startLoc['lng'] as num?)?.toDouble() ?? 0,
      );
    }
    
    final endLoc = json['end_location'] as Map<String, dynamic>?;
    LatLng endLatLng = latLng; // fallback
    if (endLoc != null) {
      endLatLng = LatLng(
        (endLoc['lat'] as num?)?.toDouble() ?? 0,
        (endLoc['lng'] as num?)?.toDouble() ?? 0,
      );
    }

    // ── Parse distance (can be a number OR an object {text, value}) ──
    double distance = 0;
    final rawDist = json['distance'];
    if (rawDist is num) {
      distance = rawDist.toDouble();
    } else if (rawDist is Map) {
      distance = (rawDist['value'] as num?)?.toDouble() ?? 0;
    }

    // ── Parse duration (can be a number OR an object {text, value}) ──
    double duration = 0;
    final rawDur = json['duration'];
    if (rawDur is num) {
      duration = rawDur.toDouble();
    } else if (rawDur is Map) {
      duration = (rawDur['value'] as num?)?.toDouble() ?? 0;
    }

    // ── Parse instruction (API may use 'instruction', 'instructions', or 'html_instructions') ──
    String rawInstruction = (json['instruction'] 
        ?? json['instructions'] 
        ?? json['html_instructions'] 
        ?? '').toString();
    // Strip HTML tags
    rawInstruction = rawInstruction.replaceAll(RegExp(r'<[^>]*>'), '');

    // Only replace "Head north/south/east/west" with "Go straight" — keep the rest
    String cleanedInstruction = rawInstruction.replaceAllMapped(
      RegExp(r'^Head\s+(north|south|east|west)(?:-(east|west))?\s*', caseSensitive: false),
      (match) => 'Go straight ',
    ).trim();

    // ── Parse maneuver (can be a string OR an object {type, modifier, ...}) ──
    String maneuver = '';
    final rawManeuver = json['maneuver'];
    if (rawManeuver is String) {
      maneuver = rawManeuver;
    } else if (rawManeuver is Map) {
      // OLA Maps format: {type: "turn", modifier: "right"} or {type: "turn-right"}
      final type = (rawManeuver['type'] ?? '').toString();
      final modifier = (rawManeuver['modifier'] ?? '').toString();
      if (type.isNotEmpty && modifier.isNotEmpty && !type.contains(modifier)) {
        maneuver = '$type-$modifier'; // e.g. "turn" + "right" → "turn-right"
      } else if (type.isNotEmpty) {
        maneuver = type;
      }
    }

    // If maneuver is still empty, infer from the instruction text
    if (maneuver.isEmpty) {
      maneuver = _inferManeuverFromInstruction(cleanedInstruction);
    }

    debugPrint('[RouteStep] Parsed: maneuver=$maneuver, instruction=$cleanedInstruction, dist=$distance');

    return RouteStep(
      distance: distance,
      duration: duration,
      instruction: cleanedInstruction,
      maneuverType: maneuver,
      location: latLng,
      endLocation: endLatLng,
    );
  }

  /// Infer a maneuver type string from the instruction text when the API
  /// doesn't provide one. Returns a Google-compatible maneuver string.
  static String _inferManeuverFromInstruction(String instruction) {
    final inst = instruction.toLowerCase();
    
    // U-turn (check before left/right)
    if (inst.contains('u-turn') || inst.contains('u turn') || inst.contains('uturn')) {
      return inst.contains('right') ? 'uturn-right' : 'uturn-left';
    }
    // Arrival
    if (inst.contains('arrive') || inst.contains('destination')) return 'arrive';
    // Roundabout
    if (inst.contains('roundabout') || inst.contains('rotary')) {
      return inst.contains('left') ? 'roundabout-left' : 'roundabout-right';
    }
    // Fork
    if (inst.contains('fork')) {
      return inst.contains('left') ? 'fork-left' : 'fork-right';
    }
    // Merge
    if (inst.contains('merge')) return 'merge';
    // Ramp / exit
    if (inst.contains('ramp') || inst.contains('exit')) {
      return inst.contains('left') ? 'ramp-left' : 'ramp-right';
    }
    // Sharp turns
    if (inst.contains('sharp left')) return 'sharp-left';
    if (inst.contains('sharp right')) return 'sharp-right';
    // Slight / keep / bear
    if (inst.contains('slight left') || inst.contains('keep left') || inst.contains('bear left')) {
      return 'slight-left';
    }
    if (inst.contains('slight right') || inst.contains('keep right') || inst.contains('bear right')) {
      return 'slight-right';
    }
    // Normal turns — use explicit phrases to avoid matching road names
    if (inst.contains('turn left') || inst.contains('take left') || inst.contains('take a left')) {
      return 'turn-left';
    }
    if (inst.contains('turn right') || inst.contains('take right') || inst.contains('take a right')) {
      return 'turn-right';
    }
    // Default
    return 'straight';
  }
}
