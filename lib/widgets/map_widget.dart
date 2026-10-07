import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';

import '../core/theme.dart';
import '../providers/navigation_provider.dart';
import '../providers/group_provider.dart';
import '../services/ola_tile_proxy.dart';
import 'member_marker.dart';
import 'navigation_marker.dart';
import '../core/app_colors.dart';
import 'suggestion_card.dart';
import '../utils/polyline_decoder.dart';

/// Reusable Map Widget wrapping flutter_map.
///
/// Can display the route polyline, member markers, and nearby POIs.
/// Uses AnimatedMarkerLayer for smooth marker transitions.
class TrailMapWidget extends StatefulWidget {
  final MapController mapController;
  final LatLng initialCenter;
  final double initialZoom;
  final List<LatLng> routePolyline;
  final List<LatLng> traveledPolyline;
  final List<LatLng> remainingPolyline;
  final Map<String, MemberPosition> memberPositions;
  final String? currentUserId;
  final String? leaderId;
  final bool isDrivingMode;
  final double? initialRouteBearing;
  final List<AIWaypoint> aiWaypoints;
  final double deviceHeading;
  final List<WaypointModel> waypoints;
  final Function(AIWaypoint)? onWaypointTap;
  final List<LatLng> detourPolyline;
  final bool isDarkMode;
  final WaypointSuggestion? activeSuggestion;
  final VoidCallback? onSuggestionDismiss;
  final VoidCallback? onSuggestionNavigate;
  final List<LatLng> sosPolyline;
  final List<NearbyPlace> nearbyPlaces;
  final Duration? animationDuration;
  final List<Map<String, dynamic>>? liveAlternativeRoutes;
  final Function(Map<String, dynamic>)? onAlternativeRouteSelected;

  TrailMapWidget({
    super.key,
    required this.mapController,
    this.initialCenter = const LatLng(0, 0),
    this.initialZoom = 14.0,
    this.routePolyline = const [],
    this.traveledPolyline = const [],
    this.remainingPolyline = const [],
    this.memberPositions = const {},
    this.currentUserId,
    this.leaderId,
    this.isDrivingMode = false,
    this.initialRouteBearing,
    this.deviceHeading = 0.0,
    this.aiWaypoints = const [],
    this.waypoints = const [],
    this.onWaypointTap,
    this.detourPolyline = const [],
    this.isDarkMode = false,
    this.activeSuggestion,
    this.onSuggestionDismiss,
    this.onSuggestionNavigate,
    this.sosPolyline = const [],
    this.nearbyPlaces = const [],
    this.animationDuration,
    this.liveAlternativeRoutes,
    this.onAlternativeRouteSelected,
  });

  @override
  State<TrailMapWidget> createState() => _TrailMapWidgetState();
}

class _TrailMapWidgetState extends State<TrailMapWidget> with TickerProviderStateMixin {

  // Track previous positions for smooth animation
  final Map<String, LatLng> _previousPositions = {};
  final Map<String, LatLng> _animatedPositions = {};
  final Map<String, AnimationController> _positionAnimControllers = {};

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant TrailMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Animate markers when their positions change
    for (final entry in widget.memberPositions.entries) {
      final userId = entry.key;
      final newPos = entry.value.latLng;
      final prevPos = _previousPositions[userId];

      if (prevPos != null && (prevPos.latitude != newPos.latitude || prevPos.longitude != newPos.longitude)) {
        // In driving mode the camera follows me, so animating my own marker
        // fights the camera tween. Pin it to the raw position.
        if (userId == widget.currentUserId && widget.isDrivingMode) {
          _animatedPositions[userId] = newPos;
        } else {
          _animateMarker(userId, newPos);
        }
      } else {
        _animatedPositions[userId] = newPos;
      }
      _previousPositions[userId] = newPos;
    }
  }

  void _animateMarker(String userId, LatLng to) {
    final currentPos = _animatedPositions[userId] ?? to;

    _positionAnimControllers[userId]?.dispose();

    final controller = AnimationController(
      duration: widget.animationDuration ?? const Duration(milliseconds: 1000),
      vsync: this,
    );

    final latTween = Tween<double>(begin: currentPos.latitude, end: to.latitude);
    final lngTween = Tween<double>(begin: currentPos.longitude, end: to.longitude);
    final curved = CurvedAnimation(parent: controller, curve: Curves.linear);

    controller.addListener(() {
      setState(() {
        _animatedPositions[userId] = LatLng(
          latTween.evaluate(curved),
          lngTween.evaluate(curved),
        );
      });
    });

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _animatedPositions[userId] = to;
      }
    });

    _positionAnimControllers[userId] = controller;
    controller.forward();
  }

  @override
  void dispose() {
    for (final c in _positionAnimControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Dark mode color matrix — inverts and hue-rotates OSM tiles
  static const ColorFilter _darkModeFilter = ColorFilter.matrix(<double>[
    -0.8, 0, 0, 0, 230,  // Red
    0, -0.8, 0, 0, 230,  // Green
    0, 0, -0.6, 0, 230,  // Blue (slightly less inversion for better contrast)
    0, 0, 0, 1, 0,       // Alpha
  ]);

  /// Finds the nearest point on the polyline for a given waypoint
  LatLng _nearestPointOnPolyline(LatLng point, List<LatLng> polyline) {
    if (polyline.isEmpty) return point;
    
    double minDist = double.infinity;
    LatLng nearest = polyline.first;
    
    for (final p in polyline) {
      final dlat = point.latitude - p.latitude;
      final dlng = point.longitude - p.longitude;
      final dist = dlat * dlat + dlng * dlng;
      if (dist < minDist) {
        minDist = dist;
        nearest = p;
      }
    }
    return nearest;
  }

  DateTime? _lastTileUpdate;
  Timer? _tileUpdateTimer;

  late final StreamTransformer<TileUpdateEvent, TileUpdateEvent> _throttleTileUpdates =
      StreamTransformer<TileUpdateEvent, TileUpdateEvent>.fromBind((Stream<TileUpdateEvent> inStream) {
    StreamController<TileUpdateEvent> controller = StreamController<TileUpdateEvent>();
    inStream.listen((event) {
      final now = DateTime.now();
      if (_lastTileUpdate == null || now.difference(_lastTileUpdate!) > const Duration(milliseconds: 150)) {
        _lastTileUpdate = now;
        controller.add(event);
      } else {
        _tileUpdateTimer?.cancel();
        _tileUpdateTimer = Timer(const Duration(milliseconds: 150), () {
          _lastTileUpdate = DateTime.now();
          if (!controller.isClosed) {
             controller.add(event);
          }
        });
      }
    }, onDone: () => controller.close(), onError: (e) => controller.addError(e));
    return controller.stream;
  });

  Widget? _cachedTileLayer;

  Widget _buildTileLayer() {
    _cachedTileLayer ??= TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.vorniity.rouniity',
      tileProvider: const FMTCStore('mapStore').getTileProvider(),
      keepBuffer: 2, 
      tileUpdateTransformer: _throttleTileUpdates,
    );

    return widget.isDarkMode
        ? ColorFiltered(colorFilter: _darkModeFilter, child: _cachedTileLayer!)
        : _cachedTileLayer!;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    // Build the tile layer (cached to avoid 60fps rebuilds during marker animation)
    final tileLayer = _buildTileLayer();

    // (Waypoint connector dotted lines removed since AI waypoints are now part of the route)
    final List<Polyline<Object>> waypointConnectors = [];

    return FlutterMap(
      mapController: widget.mapController,
      options: MapOptions(
        initialCenter: widget.initialCenter,
        initialZoom: widget.initialZoom,
        maxZoom: 18.0,
        minZoom: 3.0,
        interactionOptions: InteractionOptions(
          flags: InteractiveFlag.all,
        ),
      ),
      children: [
        // Raster Map Tiles Layer (with optional dark mode filter)
        tileLayer,

        // Route Polyline
        if (widget.traveledPolyline.isNotEmpty || widget.remainingPolyline.isNotEmpty)
          PolylineLayer(
            polylines: <Polyline<Object>>[
              if (widget.traveledPolyline.isNotEmpty)
                Polyline(
                  points: widget.traveledPolyline,
                  color: colors.textTertiary.withValues(alpha: 0.6),
                  strokeWidth: 6.0,
                  borderStrokeWidth: 2.0,
                  borderColor: colors.primaryBackground.withValues(alpha: 0.6),
                ),
              if (widget.remainingPolyline.isNotEmpty)
                Polyline(
                  points: widget.remainingPolyline,
                  color: colors.accentPrimary.withValues(alpha: 0.8),
                  strokeWidth: 6.0,
                  borderStrokeWidth: 2.0,
                  borderColor: colors.primaryBackground,
                ),
            ],
          )
        else if (widget.routePolyline.isNotEmpty)
          PolylineLayer(
            polylines: <Polyline<Object>>[
              Polyline(
                points: widget.routePolyline,
                color: colors.accentPrimary.withValues(alpha: 0.8),
                strokeWidth: 6.0,
                borderStrokeWidth: 2.0,
                borderColor: colors.primaryBackground,
              ),
            ],
          ),

            // Waypoint connector lines (drawn after route so they appear on top)
            if (waypointConnectors.isNotEmpty)
              PolylineLayer(polylines: waypointConnectors),

            if (widget.liveAlternativeRoutes != null && widget.liveAlternativeRoutes!.isNotEmpty)
              PolylineLayer(
                polylines: widget.liveAlternativeRoutes!.map((r) => Polyline(
                  points: decodePolyline(r['polyline']),
                  color: Colors.grey.withValues(alpha: 0.7),
                  strokeWidth: 5.0,
                  borderStrokeWidth: 1.5,
                  borderColor: Colors.grey.shade800,
                )).toList(),
              ),

            // Detour Polyline (yellow)
            if (widget.detourPolyline.isNotEmpty)
              PolylineLayer(
                polylines: <Polyline<Object>>[
                  Polyline(
                    points: widget.detourPolyline,
                    color: const Color(0xFFFFD600),
                    strokeWidth: 5.0,
                    borderStrokeWidth: 1.5,
                    borderColor: const Color(0xFFFFA000),
                  ),
                ],
              ),
              
            // SOS Polyline (red)
            if (widget.sosPolyline.isNotEmpty)
              PolylineLayer(
                polylines: <Polyline<Object>>[
                  Polyline(
                    points: widget.sosPolyline,
                    color: const Color(0xFFFF1744),
                    strokeWidth: 6.0,
                    borderStrokeWidth: 2.0,
                    borderColor: const Color(0xFFD50000),
                  ),
                ],
              ),

            // Member Markers (with smooth animation)
            MarkerLayer(
              markers: [
                if (widget.routePolyline.isNotEmpty) ...[
                  Marker(
                    point: widget.routePolyline.first,
                    width: 40,
                    height: 40,
                    child: Icon(Icons.location_on, color: colors.accentSecondary, size: 40),
                  ),
                  Marker(
                    point: widget.routePolyline.last,
                    width: 40,
                    height: 40,
                    child: Icon(Icons.flag_rounded, color: colors.accentDanger, size: 40),
                  ),
                ],
                ...widget.waypoints.asMap().entries.map((e) => Marker(
                  point: LatLng(e.value.lat, e.value.lng),
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.orange, width: 2),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                    ),
                    child: Center(
                      child: Text('${e.key + 1}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                )),
                ...widget.aiWaypoints.map((wp) => Marker(
                  point: LatLng(wp.lat, wp.lng),
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  child: GestureDetector(
                    onTap: () => widget.onWaypointTap?.call(wp),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        border: Border.all(color: const Color(0xFF4CAF50), width: 2.5),
                      ),
                      child: Center(
                        child: Icon(wp.iconData, color: const Color(0xFF4CAF50), size: 20),
                      ),
                    ),
                  ),
                )),
                ...widget.nearbyPlaces.where((p) => p.lat != null && p.lng != null).map((p) => Marker(
                  point: LatLng(p.lat!, p.lng!),
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                      border: Border.all(color: const Color(0xFF4CAF50), width: 2.5),
                    ),
                    child: Center(
                      child: Icon(Icons.place_rounded, color: const Color(0xFF4CAF50), size: 20),
                    ),
                  ),
                )),

                if (widget.liveAlternativeRoutes != null)
                  ...widget.liveAlternativeRoutes!.map((alt) {
                    final pts = decodePolyline(alt['polyline']);
                    if (pts.isEmpty) return Marker(point: LatLng(0,0), child: SizedBox.shrink());
                    final midPt = pts[(pts.length * 0.5).toInt()];
                    final mainDur = widget.routePolyline.length * 2; // rough approx
                    final altDur = alt['duration'];
                    final diffMin = ((altDur - mainDur) / 60.0).round();
                    final sign = diffMin > 0 ? '+' : '';
                    final diffText = diffMin == 0 ? 'Similar ETA' : '$sign$diffMin min';
                    final diffColor = diffMin > 0 ? Colors.red : Colors.green;
                    
                    return Marker(
                      point: midPt,
                      width: 90,
                      height: 45,
                      child: GestureDetector(
                        onTap: () => widget.onAlternativeRouteSelected?.call(alt),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: diffColor, width: 2),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                          ),
                          child: Center(
                            child: Text(
                              diffText,
                              style: TextStyle(color: diffColor, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),

                ...widget.memberPositions.values.map((pos) {
                  final isMe = pos.userId == widget.currentUserId;
                  final isLeader = pos.userId == widget.leaderId;
                  
                  // Use the animated position if available, otherwise raw
                  final displayPos = _animatedPositions[pos.userId] ?? pos.latLng;

                  if (isMe && widget.isDrivingMode) {
                    return Marker(
                      point: displayPos,
                      width: 60,
                      height: 60,
                      alignment: Alignment.center,
                      rotate: true,
                      child: GoogleNavigationMarker(
                        heading: pos.speed < 1.0 ? widget.deviceHeading : pos.heading,
                        animationDuration: widget.animationDuration,
                      ),
                    );
                  }

                  return Marker(
                    point: displayPos,
                    width: 80,
                    height: 80,
                    alignment: Alignment.topCenter,
                    child: MemberMarker(
                      name: pos.name,
                      isLeader: isLeader,
                      status: pos.status,
                    ),
                  );
                }),
                // Smart Suggestion Map Bubble
                if (widget.activeSuggestion != null)
                  Marker(
                    point: LatLng(widget.activeSuggestion!.lat, widget.activeSuggestion!.lng),
                    width: 200,
                    height: 120,
                    alignment: Alignment.topCenter,
                    child: _SuggestionBubble(
                      suggestion: widget.activeSuggestion!,
                      onDismiss: widget.onSuggestionDismiss,
                      onNavigate: widget.onSuggestionNavigate,
                    ),
                  ),
              ],
            ),
      ],
    );
  }
}

class _SuggestionBubble extends StatelessWidget {
  final WaypointSuggestion suggestion;
  final VoidCallback? onDismiss;
  final VoidCallback? onNavigate;

  const _SuggestionBubble({
    required this.suggestion,
    this.onDismiss,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colors.cardColor.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: suggestion.accentColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: suggestion.accentColor.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: suggestion.accentColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(suggestion.iconData, color: suggestion.accentColor, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.name,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        suggestion.reason,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: colors.borderColor),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onDismiss,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Center(
                      child: Text(
                        'Dismiss',
                        style: TextStyle(color: colors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 24, color: colors.borderColor),
              Expanded(
                child: InkWell(
                  onTap: onNavigate,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Center(
                      child: Text(
                        'Navigate',
                        style: TextStyle(color: suggestion.accentColor, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
