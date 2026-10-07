import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../services/ola_maps_service.dart';
import '../../utils/polyline_decoder.dart';
import '../../widgets/skeleton_loader.dart';
import '../../core/tutorial_controller.dart';
import '../../core/tutorial_keys.dart';

class RouteStyleScreen extends StatefulWidget {
  final String tripName;
  final String transportMode;
  final String travelType;
  final PlaceModel origin;
  final PlaceModel destination;
  final List<PlaceModel> waypoints;

  const RouteStyleScreen({
    super.key,
    required this.tripName,
    required this.transportMode,
    required this.travelType,
    required this.origin,
    required this.destination,
    this.waypoints = const [],
  });

  @override
  State<RouteStyleScreen> createState() => _RouteStyleScreenState();
}

class _RouteStyleScreenState extends State<RouteStyleScreen> {
  final OlaMapsService _mapsService = OlaMapsService();
  final MapController _mapController = MapController();
  
  String _selectedRouteMode = 'highway';
  bool _isLoading = true;
  bool _isCreating = false;
  Set<int> _selectedPoiIndices = {};
  int _selectedRouteIndex = 0;
  
  bool _isSheetExpanded = true;
  bool _isPoisExpanded = true;
  bool _isStylesExpanded = true;
  
  static const List<Color> _routeColors = [
    Color(0xFF4CAF50), // Green (Main)
    Color(0xFF2196F3), // Blue
    Color(0xFF00BCD4), // Cyan (Replaced Orange for better day/night visibility)
    Color(0xFF9C27B0), // Purple
    Color(0xFFE91E63), // Pink
  ];

  Color _getRouteColor(int index) {
    return _routeColors[index % _routeColors.length];
  }

  // Base route fetched on load
  List<dynamic>? _baseRoutes;
  int _baseDistance = 0;
  int _baseDuration = 0;
  final String _mainRoad = 'NH 48'; // Mock default or extracted from route

  // Dynamic route based on selected style
  List<dynamic>? _styleRoutes;
  List<dynamic>? _styleWaypoints;

  // Mock scenic spots to show on the map for the aesthetic
  final List<LatLng> _mockScenicSpots = [];

  @override
  void initState() {
    super.initState();
    _generateMockSpots();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchBaseRoute();
      TutorialController.startRouteStyleTutorial(context);
    });
  }

  void _generateMockSpots() {
    // Generate some points between origin and destination roughly for visuals
    final lat1 = widget.origin.lat!;
    final lng1 = widget.origin.lng!;
    final lat2 = widget.destination.lat!;
    final lng2 = widget.destination.lng!;
    
    _mockScenicSpots.add(LatLng(lat1 + (lat2 - lat1) * 0.3, lng1 + (lng2 - lng1) * 0.3));
    _mockScenicSpots.add(LatLng(lat1 + (lat2 - lat1) * 0.6, lng1 + (lng2 - lng1) * 0.6));
    _mockScenicSpots.add(LatLng(lat1 + (lat2 - lat1) * 0.8, lng1 + (lng2 - lng1) * 0.8));
  }

  Future<void> _fetchBaseRoute() async {
    if (mounted) _mapsService.setToken(context.read<AuthProvider>().token ?? '');
    try {
      final dir = await _mapsService.getDirections(
        originLat: widget.origin.lat!,
        originLng: widget.origin.lng!,
        destLat: widget.destination.lat!,
        destLng: widget.destination.lng!,
        waypoints: widget.waypoints.isNotEmpty ? widget.waypoints.map((w) => {'lat': w.lat!, 'lng': w.lng!}).toList() : null,
        mode: widget.transportMode,
        alternatives: widget.waypoints.isEmpty,
      );
      
      if (dir['routes'] != null && (dir['routes'] as List).isNotEmpty) {
        final route = dir['routes'][0];
        final legs = route['legs'] as List;
        
        int totalDist = 0;
        int totalDur = 0;
        for (var leg in legs) {
          totalDist += (leg['distance'] as num).toInt();
          totalDur += (leg['duration'] as num).toInt();
        }
        
        if (mounted) {
          setState(() {
            _baseRoutes = dir['routes'];
            _baseDistance = totalDist;
            _baseDuration = totalDur;
            _isLoading = false;
          });
          _fitMapBounds();
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error fetching base route: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _fitMapBounds({List<dynamic>? routes}) {
    final activeRoutes = routes ?? _styleRoutes ?? _baseRoutes;
    if (activeRoutes == null || activeRoutes.isEmpty) return;
    try {
      final index = (routes != null) ? 0 : _selectedRouteIndex;
      if (index >= activeRoutes.length) return;
      
      final polylineStr = activeRoutes[index]['overview_polyline'] ?? activeRoutes[index]['geometry'];
      if (polylineStr != null) {
        final points = decodePolyline(polylineStr);
        if (points.isNotEmpty) {
          // POIs will remain unticked by default, managed by _fetchStyleRoute state
          final bounds = LatLngBounds.fromPoints([
            ...points,
            LatLng(widget.origin.lat!, widget.origin.lng!),
            LatLng(widget.destination.lat!, widget.destination.lng!),
          ]);
          _animatedMapFitBounds(bounds);
        }
      }
    } catch (e) {
      debugPrint('Error fitting map bounds: $e');
    }
  }

  void _animatedMapFitBounds(LatLngBounds bounds) {
    // Determine a safe padding that won't crash flutter_map on small screens.
    // The previous bottom padding of 420 was larger than the available vertical space on some devices,
    // causing the map to lock up or ignore the camera fit command.
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPadding = screenHeight > 800 ? 300.0 : 150.0; // Safe dynamic padding

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds, 
        padding: EdgeInsets.only(top: 100.0, left: 40.0, right: 40.0, bottom: bottomPadding),
      ),
    );
  }

  Future<void> _fetchStyleRoute(String mode) async {
    setState(() {
      _selectedRouteMode = mode;
      _selectedRouteIndex = 0;
      _isLoading = true;
      _selectedPoiIndices = {}; // Clear POI selection when switching styles
    });

    try {
      if (mode == 'highway') {
        setState(() {
          _styleRoutes = _baseRoutes;
          _styleWaypoints = [];
          _isLoading = false;
        });
        _fitMapBounds();
        return;
      }

      final res = await _mapsService.getSmartRoute(
        originLat: widget.origin.lat!,
        originLng: widget.origin.lng!,
        destLat: widget.destination.lat!,
        destLng: widget.destination.lng!,
        mode: mode,
        transportMode: widget.transportMode,
      );

      if (mounted) {
        setState(() {
          _styleRoutes = res['routes'];
          _styleWaypoints = res['aiWaypoints'];
          _isLoading = false;
        });
        _fitMapBounds();
      }
    } catch (e) {
      debugPrint('Error fetching style route: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createTrip() async {
    if (_baseRoutes == null || _baseRoutes!.isEmpty) return;

    setState(() => _isCreating = true);

    try {
      Map<String, dynamic> currentRoute;
      
      if (_selectedPoiIndices.isEmpty || _styleWaypoints == null) {
        currentRoute = _baseRoutes![_selectedRouteIndex];
      } else {
        // Fetch a new route that passes exactly through the selected POIs
        final selectedWps = _styleWaypoints!.asMap().entries
            .where((e) => _selectedPoiIndices.contains(e.key))
            .map((e) => e.value)
            .toList();
            
        final waypointsList = selectedWps.map((wp) => {
          'lat': (wp['lat'] as num).toDouble(),
          'lng': (wp['lng'] as num).toDouble(),
        }).toList();

        try {
          final res = await _mapsService.getDirections(
            originLat: widget.origin.lat!,
            originLng: widget.origin.lng!,
            destLat: widget.destination.lat!,
            destLng: widget.destination.lng!,
            waypoints: [
              ...widget.waypoints.map((w) => {'lat': w.lat!, 'lng': w.lng!}),
              ...waypointsList,
            ],
            mode: widget.transportMode,
          );
          if (res['routes'] != null && res['routes'].isNotEmpty) {
            currentRoute = res['routes'][0];
          } else {
            currentRoute = _baseRoutes![_selectedRouteIndex];
          }
        } catch (e) {
          debugPrint('Error fetching waypoint route: $e');
          currentRoute = _baseRoutes![_selectedRouteIndex];
        }
      }

      final polyline = currentRoute['overview_polyline'] ?? currentRoute['geometry'];

      List<dynamic> steps = [];
      if (currentRoute['legs'] != null && currentRoute['legs'].isNotEmpty) {
        for (final leg in currentRoute['legs']) {
          if (leg['steps'] != null) {
            steps.addAll(leg['steps']);
          }
        }
      }

      final groupProvider = context.read<GroupProvider>();
      
      final group = await groupProvider.createGroup(
        name: widget.tripName,
        origin: widget.origin,
        destination: widget.destination,
        waypoints: widget.waypoints,
        transportMode: widget.transportMode,
        routeMode: _selectedRouteMode,
        polyline: polyline,
        steps: steps,
        distanceMeters: _getCalculatedDistance(_selectedRouteMode),
        durationSeconds: _getCalculatedDuration(_selectedRouteMode),
        aiWaypoints: _styleWaypoints != null 
            ? _styleWaypoints!.asMap().entries.where((e) => _selectedPoiIndices.contains(e.key)).map((e) => AIWaypoint.fromJson(e.value as Map<String, dynamic>)).toList() 
            : [],
        routeCharacter: 'Scenic',
      );

      if (mounted) {
        if (group != null) {
          if (widget.travelType == 'solo') {
            final navProvider = context.read<NavigationProvider>();
            final authProvider = context.read<AuthProvider>();

            if (group.isLeader(authProvider.currentUser!.id)) {
              await groupProvider.updateStatus(group.id, 'active');
              navProvider.wsService.startTrip(group.id);
            }
            
            if (mounted) {
              await navProvider.startNavigation(group);
              Navigator.pushReplacementNamed(context, '/live-navigation', arguments: group.id);
            }
          } else {
            Navigator.pushNamed(context, '/group-lobby', arguments: group.id);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(groupProvider.errorMessage ?? 'Failed to create trip')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  int _getCalculatedDistance(String mode) {
    if (_baseDistance == 0) return 0;
    if (['adventure', 'cultural', 'foodie', 'coastal', 'spiritual'].contains(mode)) return (_baseDistance * 1.05).round();
    if (['full_adventure', 'wildlife'].contains(mode)) return (_baseDistance * 1.15).round();
    return _baseDistance;
  }

  int _getCalculatedDuration(String mode) {
    if (_baseDuration == 0) return 0;
    if (['adventure', 'cultural', 'foodie', 'coastal', 'spiritual'].contains(mode)) return (_baseDuration * 1.15).round();
    if (['full_adventure', 'wildlife'].contains(mode)) return (_baseDuration * 1.35).round();
    return _baseDuration;
  }

  String _formatDistance(int meters) {
    return '${(meters / 1000).toStringAsFixed(0)} km';
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final h = mins ~/ 60;
    final m = mins % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 1. Map Layer
          _buildMapLayer(),

          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildFloatingStatsPill(),
                _buildBottomSheet(),
              ],
            ),
          ),
          
          // Back Button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: _buildCircleButton(Icons.arrow_back_ios_new_rounded, () => Navigator.pop(context)),
          ),
          
          if (_isLoading)
            const SkeletonRouteOptions(),
        ],
      ),
    );
  }

  Widget _buildMapLayer() {
    final trueOrigin = LatLng(widget.origin.lat!, widget.origin.lng!);
    final trueDest = LatLng(widget.destination.lat!, widget.destination.lng!);
    List<LatLng>? selectedPolyline;

    if (_styleRoutes != null && _styleRoutes!.isNotEmpty && _selectedRouteIndex < _styleRoutes!.length) {
      selectedPolyline = decodePolyline(_styleRoutes![_selectedRouteIndex]['overview_polyline'] ?? _styleRoutes![_selectedRouteIndex]['geometry'] ?? '');
    } else if (_baseRoutes != null && _baseRoutes!.isNotEmpty && _selectedRouteIndex < _baseRoutes!.length) {
      selectedPolyline = decodePolyline(_baseRoutes![_selectedRouteIndex]['overview_polyline'] ?? _baseRoutes![_selectedRouteIndex]['geometry'] ?? '');
    }

    // Google Maps style origin/destination connectors
    final List<Polyline> connectorLines = [];
    if (selectedPolyline != null && selectedPolyline.isNotEmpty) {
      // Connect true origin to route start
      connectorLines.add(Polyline(
        points: [trueOrigin, selectedPolyline.first],
        color: Colors.grey.shade600,
        strokeWidth: 3.0,
        pattern: const StrokePattern.dotted(spacingFactor: 2),
      ));
      // Connect route end to true destination
      connectorLines.add(Polyline(
        points: [selectedPolyline.last, trueDest],
        color: Colors.grey.shade600,
        strokeWidth: 3.0,
        pattern: const StrokePattern.dotted(spacingFactor: 2),
      ));
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: trueOrigin,
        initialZoom: 8.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.vorniity.rouniity',
        ),
        // Render multiple routes
        if (_styleRoutes != null && _styleRoutes!.isNotEmpty)
          PolylineLayer(
            polylines: [
              for (int i = 0; i < _styleRoutes!.length; i++)
                if (i != _selectedRouteIndex)
                  Polyline(
                    points: decodePolyline(_styleRoutes![i]['overview_polyline'] ?? _styleRoutes![i]['geometry'] ?? ''),
                    color: _getRouteColor(i).withValues(alpha: 0.6),
                    strokeWidth: 4,
                  ),
              if (selectedPolyline != null)
                Polyline(
                  points: selectedPolyline,
                  color: _getRouteColor(_selectedRouteIndex),
                  strokeWidth: 6,
                ),
            ],
          )
        else if (_baseRoutes != null && _baseRoutes!.isNotEmpty)
          PolylineLayer(
            polylines: [
              for (int i = 0; i < _baseRoutes!.length; i++)
                if (i != _selectedRouteIndex)
                  Polyline(
                    points: decodePolyline(_baseRoutes![i]['overview_polyline'] ?? _baseRoutes![i]['geometry'] ?? ''),
                    color: _getRouteColor(i).withValues(alpha: 0.6),
                    strokeWidth: 4,
                  ),
              if (selectedPolyline != null)
                Polyline(
                  points: selectedPolyline,
                  color: _getRouteColor(_selectedRouteIndex),
                  strokeWidth: 6,
                ),
            ],
          ),
          
        // Render connector lines
        if (connectorLines.isNotEmpty)
          PolylineLayer(polylines: connectorLines),
        
        // ETA Bubbles
        MarkerLayer(
          markers: [
            ...(_styleRoutes ?? _baseRoutes ?? []).asMap().entries.map((e) {
              final index = e.key;
              final route = e.value;
              final points = decodePolyline(route['overview_polyline'] ?? route['geometry'] ?? '');
              if (points.isEmpty) return null;
              
              final isSelected = index == _selectedRouteIndex;
              // Place bubble around 40% of the route to avoid overlap at the origin/destination
              final midpointIndex = (points.length * 0.4).toInt();
              final point = points[midpointIndex];
              
              int duration = 0;
              if (route['legs'] != null && (route['legs'] as List).isNotEmpty) {
                duration = (route['legs'][0]['duration'] as num).toInt();
              }
              final durationText = _formatDuration(duration);
              final color = _getRouteColor(index);
              
              return Marker(
                point: point,
                width: 80,
                height: 40,
                alignment: Alignment.center,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedRouteIndex = index;
                      if (_styleRoutes == null && _baseRoutes != null) {
                        _baseDuration = duration;
                        _baseDistance = (_baseRoutes![index]['legs'][0]['distance'] as num).toInt();
                      }
                    });
                    _fitMapBounds();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected ? color : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color, width: 2),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                    ),
                    child: Center(
                      child: Text(
                        durationText,
                        style: TextStyle(
                          color: isSelected ? Colors.white : color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).where((m) => m != null).cast<Marker>(),
          ],
        ),
        
        // POI Markers
        MarkerLayer(
          markers: [
            if (_styleWaypoints != null)
              ..._styleWaypoints!.asMap().entries.map((e) {
                final index = e.key;
                final wp = e.value;
                final isSelected = _selectedPoiIndices.contains(index);
                return Marker(
                  point: LatLng((wp['lat'] as num).toDouble(), (wp['lng'] as num).toDouble()),
                  width: 32,
                  height: 32,
                  child: GestureDetector(
                    onTap: () => _showPoiDetails(wp),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: isSelected ? 1.0 : 0.4,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E5B33), // Deep green matching the mockup
                          shape: BoxShape.circle,
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Center(
                          child: Icon(Icons.location_on, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),

        // Origin / Destination Markers
        MarkerLayer(
          markers: [
            Marker(
              point: trueOrigin,
              width: 160,
              height: 100,
              alignment: Alignment.topCenter,
              child: _buildLocationMarker(widget.origin.name, isOrigin: true),
            ),
            Marker(
              point: trueDest,
              width: 160,
              height: 100,
              alignment: Alignment.topCenter,
              child: _buildLocationMarker(widget.destination.name, isOrigin: false),
            ),
            ...widget.waypoints.asMap().entries.map((e) => Marker(
              point: LatLng(e.value.lat!, e.value.lng!),
              width: 160,
              height: 100,
              alignment: Alignment.topCenter,
              child: _buildLocationMarker(e.value.name, isOrigin: false, index: e.key + 1),
            )),
          ],
        ),
      ],
    );
  }

  Marker _buildScenicMarker(LatLng point, IconData icon) {
    return Marker(
      point: point,
      width: 32,
      height: 32,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
          border: Border.all(color: const Color(0xFF4CAF50), width: 2),
        ),
        child: Icon(icon, color: const Color(0xFF4CAF50), size: 16),
      ),
    );
  }

  Widget _buildLocationMarker(String name, {required bool isOrigin, int? index}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF333333),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            name.split(',')[0],
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 4),
        if (index != null)
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.orange, width: 3),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
            ),
            child: Center(child: Text('$index', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 10))),
          )
        else if (isOrigin)
          Container(
            width: 16, height: 16,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF4CAF50), width: 4),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
            ),
          )
        else
          const Icon(Icons.location_on, color: Color(0xFF4CAF50), size: 28, shadows: [Shadow(color: Colors.black26, blurRadius: 4)]),
      ],
    );
  }

  Widget _buildCircleButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
        ),
        child: Icon(icon, color: Colors.black87, size: 20),
      ),
    );
  }

  Widget _buildFloatingStatsPill() {
    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStatItem(Icons.route_outlined, _formatDistance(_getCalculatedDistance(_selectedRouteMode)), 'Distance'),
              const SizedBox(width: 12),
              _buildVerticalDivider(),
              const SizedBox(width: 12),
              _buildStatItem(Icons.schedule, _formatDuration(_getCalculatedDuration(_selectedRouteMode)), 'Est. time'),
              const SizedBox(width: 12),
              _buildVerticalDivider(),
              const SizedBox(width: 12),
              _buildStatItem(Icons.edit_road, _mainRoad, 'Main route'),
              const SizedBox(width: 12),
              _buildVerticalDivider(),
              const SizedBox(width: 12),
              _buildStatItem(Icons.speed, 'Fastest', 'Less detours'),
            ],
          ),
        ),
    );
  }

  Widget _buildVerticalDivider() => Container(width: 1, height: 24, color: Colors.grey.shade300);

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFF4CAF50), size: 20),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomSheet() {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -5))],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => setState(() => _isSheetExpanded = !_isSheetExpanded),
              behavior: HitTestBehavior.opaque,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 8),
                  Icon(_isSheetExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up, color: Colors.grey.shade400, size: 20),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            
            if (_isSheetExpanded) ...[
              // Multiple Routes Selector
              Builder(builder: (context) {
                final activeRoutes = (_styleRoutes != null && _styleRoutes!.isNotEmpty) ? _styleRoutes! : (_baseRoutes ?? []);
                if (activeRoutes.length <= 1) return const SizedBox.shrink();
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                child: SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: activeRoutes.length,
                    itemBuilder: (context, index) {
                      final isSelected = index == _selectedRouteIndex;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedRouteIndex = index);
                          _fitMapBounds();
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF4CAF50) : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: isSelected ? const Color(0xFF4CAF50) : Colors.grey.shade300),
                          ),
                          child: Center(
                            child: Text(
                              'Route ${index + 1}',
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            }),
            
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Text('Choose your adventure', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
                      const SizedBox(width: 8),
                      Icon(Icons.landscape, color: Colors.green.shade800),
                    ],
                  ),
                  IconButton(
                    icon: Icon(_isStylesExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up),
                    onPressed: () {
                      setState(() {
                        _isStylesExpanded = !_isStylesExpanded;
                      });
                    },
                  ),
                ],
              ),
            ),
            if (_isStylesExpanded) const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 4.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('How do you want to experience this journey?', style: TextStyle(color: Colors.black54, fontSize: 13)),
              ),
            ),
            if (_isStylesExpanded) const SizedBox(height: 16),

            // Horizontal Style Cards
            if (_isStylesExpanded) TutorialController.buildShowcase(
              key: TutorialKeys.routeStyles,
              title: 'Choose your route style',
              description: 'Select Highway for speed, or Adventure for scenic views',
              child: SizedBox(
                height: 210,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  physics: const BouncingScrollPhysics(),
                  children: [
                  _buildStyleOptionCard(
                    id: 'highway',
                    title: 'Highway',
                    subtitle: 'Fast & efficient',
                    desc: 'Fastest route via major highways.',
                    icon: Icons.bolt,
                    distance: _getCalculatedDistance('highway'),
                    duration: _getCalculatedDuration('highway'),
                    pillText: 'Few stops',
                  ),
                  _buildStyleOptionCard(
                    id: 'adventure',
                    title: 'Adventure',
                    subtitle: 'Scenic & balanced',
                    desc: 'Scenic roads with viewpoints & attractions.',
                    icon: Icons.terrain,
                    distance: _getCalculatedDistance('adventure'),
                    duration: _getCalculatedDuration('adventure'),
                    pillText: '+3 scenic stops',
                  ),
                  _buildStyleOptionCard(
                    id: 'full_adventure',
                    title: 'Full Adventure',
                    subtitle: 'Explore the journey',
                    desc: 'Maximum exploration with hidden gems & nature.',
                    icon: Icons.park,
                    distance: _getCalculatedDistance('full_adventure'),
                    duration: _getCalculatedDuration('full_adventure'),
                    pillText: '+7 recommended stops',
                  ),
                  _buildStyleOptionCard(
                    id: 'cultural',
                    title: 'Cultural',
                    subtitle: 'Heritage sites',
                    desc: 'Museums, ancient temples, monuments.',
                    icon: Icons.account_balance,
                    distance: _getCalculatedDistance('cultural'),
                    duration: _getCalculatedDuration('cultural'),
                    pillText: '+5 heritage stops',
                  ),
                  _buildStyleOptionCard(
                    id: 'foodie',
                    title: 'Foodie',
                    subtitle: 'Culinary journey',
                    desc: 'Famous eateries, cafes, bakeries.',
                    icon: Icons.restaurant,
                    distance: _getCalculatedDistance('foodie'),
                    duration: _getCalculatedDuration('foodie'),
                    pillText: '+4 food stops',
                  ),
                  _buildStyleOptionCard(
                    id: 'coastal',
                    title: 'Coastal',
                    subtitle: 'Ocean views',
                    desc: 'Beaches, marinas, scenic coastlines.',
                    icon: Icons.beach_access,
                    distance: _getCalculatedDistance('coastal'),
                    duration: _getCalculatedDuration('coastal'),
                    pillText: '+4 beach stops',
                  ),
                  _buildStyleOptionCard(
                    id: 'spiritual',
                    title: 'Spiritual',
                    subtitle: 'Peaceful retreats',
                    desc: 'Ashrams, monasteries, retreats.',
                    icon: Icons.self_improvement,
                    distance: _getCalculatedDistance('spiritual'),
                    duration: _getCalculatedDuration('spiritual'),
                    pillText: '+3 spiritual stops',
                  ),
                  _buildStyleOptionCard(
                    id: 'wildlife',
                    title: 'Wildlife',
                    subtitle: 'Nature & safari',
                    desc: 'National parks, reserves, deep forests.',
                    icon: Icons.pets,
                    distance: _getCalculatedDistance('wildlife'),
                    duration: _getCalculatedDuration('wildlife'),
                    pillText: '+2 wildlife stops',
                  ),
                ],
              ),
            ),
            ),
            

            if (_styleWaypoints != null && _styleWaypoints!.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildTopPoisSection(),
            ],

            ],

            const SizedBox(height: 16),

            // Apply Button
            Padding(
              padding: EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 24.0 + MediaQuery.of(context).padding.bottom),
              child: TutorialController.buildShowcase(
                key: TutorialKeys.createTripBtn,
                title: 'Create your trip',
                description: 'You\'re the trip captain. Tap to create!',
                disposeOnTap: true,
                onTargetClick: _isCreating ? null : _createTrip,
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                  onPressed: _isCreating ? null : _createTrip,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E5B33), // Deep green from mockup
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                    elevation: 0,
                  ),
                  child: _isCreating
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            SizedBox(width: 24), // Balance spacing
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Apply Route Style', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            Icon(Icons.arrow_forward),
                          ],
                        ),
                ),
              ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStyleOptionCard({
    required String id,
    required String title,
    required String subtitle,
    required String desc,
    required IconData icon,
    required int distance,
    required int duration,
    required String pillText,
  }) {
    final isSelected = _selectedRouteMode == id;
    final baseColor = isSelected ? const Color(0xFFE8F3E8) : Colors.white;
    final borderColor = isSelected ? const Color(0xFF4CAF50) : Colors.transparent;
    
    return GestureDetector(
      onTap: () {
        if (!isSelected) {
          _fetchStyleRoute(id);
        }
      },
      child: Container(
        width: 155,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor, width: 1.5),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: Colors.green.shade800, size: 20),
                        ),
                        const SizedBox(height: 8),
                        Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isSelected ? Colors.green.shade800 : Colors.black87)),
                        Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.black87)),
                        const SizedBox(height: 6),
                        Text(desc, style: const TextStyle(fontSize: 9, color: Colors.black54), maxLines: 2, overflow: TextOverflow.ellipsis),
                        const Spacer(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_formatDistance(distance), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                const Text('Distance', style: TextStyle(fontSize: 9, color: Colors.black54)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(_formatDuration(duration), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                const Text('Est. time', style: TextStyle(fontSize: 9, color: Colors.black54)),
                              ],
                            ),
                          ],
                        )
                      ],
                    ),
                    if (isSelected)
                      Positioned(
                        top: 0, right: 0,
                        child: Container(
                          decoration: const BoxDecoration(color: Color(0xFF1E5B33), shape: BoxShape.circle),
                          child: const Icon(Icons.check, color: Colors.white, size: 16),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4EC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.eco_outlined, size: 10, color: Color(0xFF4CAF50)),
                  const SizedBox(width: 4),
                  Text(pillText, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopPoisSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Flexible(child: Text('Top POIs on this route', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87), overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('${_selectedPoiIndices.length}/${_styleWaypoints!.length}', style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text('Handpicked places worth stopping for', style: TextStyle(fontSize: 12, color: Colors.black54), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Row(
                children: [
                  const Text('View all', style: TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w600)),
                  const Icon(Icons.chevron_right, size: 18, color: Colors.black87),
                  IconButton(
                    icon: Icon(_isPoisExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up),
                    onPressed: () {
                      setState(() {
                        _isPoisExpanded = !_isPoisExpanded;
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_isPoisExpanded) const SizedBox(height: 12),
        if (_isPoisExpanded) SizedBox(
          height: 240,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _styleWaypoints!.length,
            itemBuilder: (context, index) {
              final wp = _styleWaypoints![index];
              final isSelected = _selectedPoiIndices.contains(index);
              final String? photoUrl = wp['photoUrl'];
              final String title = wp['name'] ?? 'POI';
              final String desc = wp['reason'] ?? 'A notable spot to visit.';
              final String time = wp['timeFromOrigin'] != null ? '${wp['timeFromOrigin']} min' : '—';
              final String dist = wp['distanceFromOrigin'] != null ? '${wp['distanceFromOrigin']} km' : '—';
              
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedPoiIndices.remove(index);
                    } else {
                      _selectedPoiIndices.add(index);
                    }
                  });
                },
                onLongPress: () => _showPoiDetails(wp),
                child: Container(
                  width: 180,
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 4)),
                    ],
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Image Area
                      SizedBox(
                        height: 100,
                        width: double.infinity,
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                              child: photoUrl != null
                                  ? Image.network(
                                      photoUrl,
                                      width: double.infinity,
                                      height: 100,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => _buildPlaceholderImage(),
                                    )
                                  : _buildPlaceholderImage(),
                            ),
                            // Selection Checkbox
                            Positioned(
                              top: 8,
                              right: 8,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFF1E5B33) : Colors.white,
                                  borderRadius: BorderRadius.circular(isSelected ? 12 : 6),
                                  border: Border.all(
                                    color: isSelected ? const Color(0xFF1E5B33) : Colors.black87,
                                    width: isSelected ? 0 : 1.5,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Details Area
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('📍', style: TextStyle(fontSize: 14)), // red pin replacement
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Expanded(
                                child: Text(
                                  desc,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.schedule, size: 12, color: Colors.black54),
                                  const SizedBox(width: 4),
                                  Text(time, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                                  const Spacer(),
                                  const Icon(Icons.route_outlined, size: 12, color: Colors.black54),
                                  const SizedBox(width: 4),
                                  Text(dist, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      color: Colors.green.shade100,
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Icon(Icons.landscape, size: 40, color: Colors.green.shade300),
      ),
    );
  }

  Future<Map<String, String>> _fetchWikiData(String query, double lat, double lng) async {
    try {
      final uri = Uri.parse('https://en.wikipedia.org/w/api.php?action=query&generator=geosearch&ggscoord=$lat|$lng&ggsradius=5000&ggslimit=10&prop=pageimages|extracts&exintro&explaintext&pithumbsize=600&format=json');
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final pages = data['query']?['pages'] as Map<String, dynamic>?;
        if (pages != null && pages.isNotEmpty) {
          Map<String, dynamic>? bestPage;
          for (final page in pages.values) {
            if (page['thumbnail'] != null && page['thumbnail']['source'] != null) {
              bestPage = page as Map<String, dynamic>;
              break;
            }
          }
          bestPage ??= pages.values.first as Map<String, dynamic>;
          if (bestPage['pageid'] != null) {
            return {
              'image': bestPage['thumbnail']?['source'] ?? '',
              'extract': bestPage['extract'] ?? '',
            };
          }
        }
      }
    } catch (e) {
      debugPrint('Wiki fetch error: $e');
    }
    return {'image': '', 'extract': ''};
  }

  void _showPoiDetails(dynamic wp) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final String title = wp['name'] ?? 'POI';
        final String desc = wp['reason'] ?? 'A notable spot to visit.';
        final double lat = wp['lat'];
        final double lng = wp['lng'];
        final String type = wp['type'] ?? 'poi';
        
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, controller) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: FutureBuilder<Map<String, String>>(
              future: _fetchWikiData(title, lat, lng),
              builder: (context, snapshot) {
                final isLoading = snapshot.connectionState == ConnectionState.waiting;
                final wikiData = snapshot.data ?? {'image': '', 'extract': ''};
                final hasImage = wikiData['image']!.isNotEmpty;
                final hasExtract = wikiData['extract']!.isNotEmpty;

                return Column(
                  children: [
                    // Pull tab
                    Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        controller: controller,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        children: [
                          // Cover Photo
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              height: 200,
                              color: Colors.grey.shade100,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (isLoading)
                                    const Center(child: CircularProgressIndicator())
                                  else if (hasImage)
                                    Image.network(
                                      wikiData['image']!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Center(
                                        child: Icon(Icons.landscape_rounded, size: 64, color: Colors.grey),
                                      ),
                                    )
                                  else
                                    const Center(
                                      child: Icon(Icons.landscape_rounded, size: 64, color: Colors.grey),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4CAF50).withOpacity(0.15),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF4CAF50), width: 2),
                                ),
                                child: const Icon(Icons.place, color: Color(0xFF4CAF50), size: 28),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      type.toUpperCase().replaceAll('_', ' '),
                                      style: const TextStyle(color: Color(0xFF1E5B33), fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Why we recommended this:',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            desc,
                            style: const TextStyle(fontSize: 15, color: Colors.black54, height: 1.5),
                          ),
                          const SizedBox(height: 24),
                          
                          // Factual Info Section
                          const Text(
                            'Factual Information',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          const SizedBox(height: 16),
                          if (isLoading)
                            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                          else if (hasExtract)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Text(
                                wikiData['extract']!,
                                style: const TextStyle(color: Colors.black54, height: 1.5, fontSize: 14),
                              ),
                            )
                          else
                            const Text(
                              'No extended factual information available from Open Data sources.',
                              style: TextStyle(color: Colors.black38, fontStyle: FontStyle.italic),
                            ),
                        ],
                      ),
                    ),
                    // Action Bar
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(top: BorderSide(color: Colors.grey.shade200)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                height: 56,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: const Center(
                                  child: Text('Close', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                                // Optional: they can also toggle selection here
                                final idx = _styleWaypoints!.indexOf(wp);
                                if (idx != -1) {
                                  setState(() {
                                    if (!_selectedPoiIndices.contains(idx)) {
                                      _selectedPoiIndices.add(idx);
                                    }
                                  });
                                }
                              },
                              child: Container(
                                height: 56,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E5B33),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Center(
                                  child: Text('Add to Route', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
