import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../widgets/alert_banner.dart';
import '../../widgets/sos_button.dart';
import '../../widgets/directions_banner.dart';
import '../../widgets/poi_card.dart';
import '../../widgets/rerouting_banner.dart';
import '../../widgets/suggestion_card.dart';
import '../../widgets/trip_bottom_sheet.dart';
import '../../widgets/map_widget.dart';
import '../../widgets/compass_speedometer.dart';
import '../../widgets/quick_stops_bar.dart';
import 'arrival_screen.dart';
import 'auto_sos_countdown_screen.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/app_colors.dart';
import '../../core/theme.dart';
import '../../core/tutorial_controller.dart';
import '../../core/tutorial_keys.dart';

/// Main Live Navigation Screen
///
/// Combines the TrailMap, alerts overlay, SOS button, member list drawer, and POI cards.
class LiveNavigationScreen extends StatefulWidget {
  final String groupId;

  LiveNavigationScreen({super.key, required this.groupId});

  @override
  State<LiveNavigationScreen> createState() => _LiveNavigationScreenState();
}

enum NavigationState { browsing, preview, active }
enum MapOrientation { headingUp, northUp, free }

class _LiveNavigationScreenState extends State<LiveNavigationScreen> with TickerProviderStateMixin {
  late MapController _mapController;
  AnimationController? _mapAnimController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  NavigationState _navState = NavigationState.browsing;
  MapOrientation _mapOrientation = MapOrientation.headingUp;
  
  StreamSubscription? _positionSub;
  StreamSubscription? _compassSub;
  StreamSubscription? _fallSignalSub;
  double _deviceHeading = 0.0;
  DateTime? _lastFixTime;
  Duration _fixInterval = const Duration(milliseconds: 1000);
  double _currentDesiredZoom = 18.0;
  bool _hasCalculatedPreview = false;
  bool _userPannedMap = false; // Track if user dragged the map
  NavigationProvider? _navProvider;
  void _onNavProviderChanged() {
    if (!mounted || _navProvider == null) return;
    if (_navProvider!.routePolyline.isNotEmpty && _navState == NavigationState.browsing && !_hasCalculatedPreview) {
      setState(() {
        _navState = NavigationState.preview;
        _hasCalculatedPreview = true;
      });
      _fitRouteBounds(_navProvider!.routePolyline);
    }
    if (_navProvider!.routePolyline.isEmpty) {
      _hasCalculatedPreview = false;
    }
  }


  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _mapController = MapController();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = context.read<NavigationProvider>();
      _navProvider = nav;
      // Hardware compass for accurate heading when stationary
      _compassSub = FlutterCompass.events?.listen((event) {
        if (mounted && event.heading != null) {
          setState(() => _deviceHeading = event.heading!);
          if (_navState == NavigationState.active && _mapOrientation == MapOrientation.headingUp && !_userPannedMap) {
             final pos = nav.locationService.lastPosition;
             // Rotate map using device compass if stationary
             if (pos != null && pos.speed < 1.0) {
               _mapController.rotate(-_deviceHeading);
             }
          }
        }
      });

      // Listen to position updates to auto-follow user with SMOOTH animation
      _positionSub = nav.locationService.positionStream.listen((pos) {
        if (_navState == NavigationState.active && mounted && !_userPannedMap) {
          final now = DateTime.now();
          if (_lastFixTime != null) {
            final delta = now.difference(_lastFixTime!);
            if (delta.inMilliseconds > 200 && delta.inMilliseconds < 5000) {
              _fixInterval = Duration(
                milliseconds: (_fixInterval.inMilliseconds * 0.7 + delta.inMilliseconds * 0.3).round(),
              );
            }
          }
          _lastFixTime = now;

          final speedKmh = pos.speed * 3.6;
          
          // Disable speed-based auto-zoom based on user feedback to prevent disturbing zoom animations
          double targetZoom = _mapController.camera.zoom;
          
          if (_mapOrientation == MapOrientation.headingUp) {
            double heading = pos.heading;
            if (pos.speed < 1.0) {
              heading = _deviceHeading;
            }
            // Smooth animated move instead of instant snap
            _animatedMapMove(
              LatLng(pos.latitude, pos.longitude),
              targetZoom,
              -heading,
              continuous: true,
              duration: _fixInterval,
            );
          } else if (_mapOrientation == MapOrientation.northUp) {
            _animatedMapMove(
              LatLng(pos.latitude, pos.longitude),
              targetZoom,
              0.0,
              continuous: true,
              duration: _fixInterval,
            );
          }
          // In free mode, don't follow
        }
      });
      
      
      // Listen to nav provider changes to trigger preview when route is generated
      nav.addListener(_onNavProviderChanged);
      
      // Listen to automatic fall detection signal
      _fallSignalSub = nav.onFallSignal.listen((_) {
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AutoSosCountdownScreen(groupId: widget.groupId),
            ),
          );
        }
      });
      
      final currentUserId = context.read<AuthProvider>().currentUser?.id;
      final group = context.read<GroupProvider>().currentGroup;
      final isLeader = currentUserId != null && group?.isLeader(currentUserId) == true;
      TutorialController.startNavigationTutorial(context, isLeader: isLeader);
    });
  }

  /// Calculate zoom level based on driving speed (with hysteresis to prevent flip-flopping)
  double _calculateZoomForSpeed(double speedKmh) {
    if (_currentDesiredZoom == 18.0) {
      if (speedKmh > 30) _currentDesiredZoom = 17.0;
    } else if (_currentDesiredZoom == 17.0) {
      if (speedKmh > 55) _currentDesiredZoom = 16.0;
      else if (speedKmh < 20) _currentDesiredZoom = 18.0;
    } else if (_currentDesiredZoom == 16.0) {
      if (speedKmh > 85) _currentDesiredZoom = 15.0;
      else if (speedKmh < 45) _currentDesiredZoom = 17.0;
    } else if (_currentDesiredZoom == 15.0) {
      if (speedKmh < 75) _currentDesiredZoom = 16.0;
    }
    return _currentDesiredZoom;
  }

  void _fitRouteBounds(List<LatLng> polyline) {
    if (polyline.isEmpty) return;
    
    final bounds = LatLngBounds.fromPoints(polyline);
    _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50.0)));
    _mapController.rotate(0);
  }

  void _animatedMapMove(LatLng destLocation, double destZoom, double destRotation, {bool continuous = false, Duration? duration}) {
    _mapAnimController?.stop(); // Stop before reassignment
    _mapAnimController?.dispose();
    
    _mapAnimController = AnimationController(
      duration: duration ?? const Duration(milliseconds: 500), // Smooth glide
      vsync: this,
    );

    final latTween = Tween<double>(begin: _mapController.camera.center.latitude, end: destLocation.latitude);
    final lngTween = Tween<double>(begin: _mapController.camera.center.longitude, end: destLocation.longitude);
    final zoomTween = Tween<double>(begin: _mapController.camera.zoom, end: destZoom);

    // Calculate shortest rotation path
    double beginRot = _mapController.camera.rotation;
    double endRot = destRotation;
    final double diff = (endRot - beginRot) % 360;
    if (diff > 180) {
      endRot -= 360;
    } else if (diff < -180) {
      endRot += 360;
    } else {
      endRot = beginRot + diff;
    }
    final rotTween = Tween<double>(begin: beginRot, end: endRot);

    final animation = CurvedAnimation(
      parent: _mapAnimController!, 
      curve: continuous ? Curves.linear : Curves.easeInOut,
    );

    _mapAnimController!.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
      _mapController.rotate(rotTween.evaluate(animation));
    });

    _mapAnimController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Leave disposal to the next call to prevent double disposal
      }
    });

    _mapAnimController!.forward();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _compassSub?.cancel();
    _fallSignalSub?.cancel();
    _mapAnimController?.dispose();
    _navProvider?.removeListener(_onNavProviderChanged);
    WakelockPlus.disable();
    super.dispose();
  }

  void _centerOnMe() {
    setState(() {
      _userPannedMap = false;
    });

    if (_navState == NavigationState.preview) {
      setState(() {
        _navState = NavigationState.active;
        _mapOrientation = MapOrientation.headingUp;
      });
    } else {
      setState(() => _mapOrientation = MapOrientation.headingUp);
    }
    
    final nav = context.read<NavigationProvider>();
    final me = nav.locationService.lastPosition;
    if (me != null) {
      double heading = me.heading;
      if (me.speed < 1.0) {
        heading = _deviceHeading;
      }
      _animatedMapMove(LatLng(me.latitude, me.longitude), 18.0, -heading);
    }
  }

  void _toggleMapOrientation() {
    setState(() {
      _userPannedMap = false;
      if (_mapOrientation == MapOrientation.headingUp) {
        _mapOrientation = MapOrientation.northUp;
        _animatedMapMove(_mapController.camera.center, _mapController.camera.zoom, 0.0);
      } else if (_mapOrientation == MapOrientation.northUp) {
        _mapOrientation = MapOrientation.free;
      } else {
        _mapOrientation = MapOrientation.headingUp;
        final nav = context.read<NavigationProvider>();
        final me = nav.locationService.lastPosition;
        if (me != null) {
          double heading = me.heading;
          if (me.speed < 1.0) {
            heading = _deviceHeading;
          }
          _animatedMapMove(_mapController.camera.center, _mapController.camera.zoom, -heading);
        }
      }
    });
  }

  void _triggerSos() {
    final nav = context.read<NavigationProvider>();
    final me = nav.locationService.lastPosition;
    nav.wsService.triggerSOS(
      groupId: widget.groupId,
      lat: me?.latitude,
      lng: me?.longitude,
    );
  }

  void _triggerRegroup() {
    final nav = context.read<NavigationProvider>();
    final me = nav.locationService.lastPosition;
    final group = context.read<GroupProvider>().currentGroup;
    if (group != null && me != null) {
      nav.wsService.triggerRegroup(
        groupId: group.id,
        lat: me.latitude,
        lng: me.longitude,
      );
    }
  }

  void _triggerStopRequest() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _StopRequestSheet(
        onSubmit: (reason) {
          final nav = context.read<NavigationProvider>();
          final me = nav.locationService.lastPosition;
          final group = context.read<GroupProvider>().currentGroup;
          if (group != null && me != null) {
            nav.wsService.requestStop(
              groupId: group.id,
              lat: me.latitude,
              lng: me.longitude,
              reason: reason,
            );
          }
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _cancelSos() {
    context.read<NavigationProvider>().wsService.cancelSOS(widget.groupId);
  }

  void _onQuickStopCategoryTap(StopCategory category) async {
    final nav = context.read<NavigationProvider>();
    final pos = nav.locationService.lastPosition;
    if (pos == null) return;

    // Toggle category
    if (nav.activeStopCategory == category.label) {
      nav.clearStop();
      return;
    }

    nav.setActiveStopCategory(category.label);
    await nav.fetchNearbyPlaces(pos.latitude, pos.longitude, category.apiType);

    // We don't auto-select here anymore. The UI will display a horizontal
    // list of the options and let the user pick one.
  }

  void _confirmAddStop(BuildContext context, NavigationProvider navProvider, NearbyPlace place) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.of(context).primaryBackground,
        title: Text('Add Detour?', style: TextStyle(color: AppColors.of(context).textPrimary)),
        content: Text('Do you want to add ${place.name} to your route?', style: TextStyle(color: AppColors.of(context).textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: Text('Cancel', style: TextStyle(color: AppColors.of(context).textTertiary))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD600), foregroundColor: Colors.black),
            onPressed: () async {
              Navigator.pop(ctx);
              debugPrint('UI: Add Stop pressed for ${place.name}');
              await navProvider.selectStop(place);
              
              // Clear active category to minimize the stops menu
              navProvider.setActiveStopCategory(null);
              
              // Map Zoom out
              final pos = navProvider.locationService.lastPosition;
              if (pos != null && place.lat != null && place.lng != null) {
                debugPrint('UI: Fitting camera bounds to show current pos and detour');
                
                setState(() {
                  _userPannedMap = true;
                  _mapOrientation = MapOrientation.free;
                });
                
                final bounds = LatLngBounds.fromPoints([
                  LatLng(pos.latitude, pos.longitude),
                  LatLng(place.lat!, place.lng!),
                ]);
                _mapController.fitCamera(CameraFit.bounds(
                  bounds: bounds,
                  padding: const EdgeInsets.all(80.0),
                ));
              }
            },
            child: const Text('Add Stop', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showStepsSheet(BuildContext context) {
    final colors = AppColors.of(context);
    final nav = context.read<NavigationProvider>();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: colors.primaryBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: colors.borderColor),
          ),
          child: Column(
            children: [
              // Pull tab
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textTertiary.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(Icons.list_alt_rounded, color: colors.accentPrimary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Route Steps',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: nav.routeSteps.length,
                  itemBuilder: (context, index) {
                    final step = nav.routeSteps[index];
                    final isCurrent = index == nav.routeSteps.indexOf(nav.currentStep ?? nav.routeSteps.first);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? colors.accentPrimary.withValues(alpha: 0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: isCurrent
                            ? Border.all(color: colors.accentPrimary.withValues(alpha: 0.3))
                            : null,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? colors.accentPrimary.withValues(alpha: 0.2)
                                  : colors.surfaceColor,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isCurrent ? colors.accentPrimary : colors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              step.instruction,
                              style: TextStyle(
                                fontSize: 13,
                                color: isCurrent ? colors.textPrimary : colors.textSecondary,
                                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ),
                          Text(
                            step.distance > 1000
                                ? '${(step.distance / 1000).toStringAsFixed(1)} km'
                                : '${step.distance.toStringAsFixed(0)} m',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textTertiary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDarkMode = colors.brightness == Brightness.dark;

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildMembersDrawer(context),
      body: Consumer3<NavigationProvider, GroupProvider, AuthProvider>(
        builder: (context, navProvider, groupProvider, authProvider, _) {
          final currentUserId = authProvider.currentUser?.id;
          final leaderId = groupProvider.currentGroup?.leaderId;
          
          // Determine initial center
          LatLng center = LatLng(20.5937, 78.9629); // India center default
          if (navProvider.locationService.lastPosition != null) {
            center = LatLng(
              navProvider.locationService.lastPosition!.latitude,
              navProvider.locationService.lastPosition!.longitude,
            );
          } else if (navProvider.routePolyline.isNotEmpty) {
            center = navProvider.routePolyline.first;
          }

          return Stack(
            children: [
              // 1. Map Layer — detect user pan gestures
              TutorialController.buildShowcase(
                key: TutorialKeys.routeMap,
                title: 'Live Map',
                description: 'Follow the route. Pan to explore, re-center anytime',
                child: GestureDetector(
                  onPanStart: (_) {
                    if (_navState == NavigationState.active && _mapOrientation != MapOrientation.free) {
                      setState(() {
                        _userPannedMap = true;
                      });
                    }
                  },
                  child: TrailMapWidget(
                    mapController: _mapController,
                    initialCenter: center,
                  routePolyline: navProvider.routePolyline,
                  traveledPolyline: navProvider.traveledPolyline,
                  remainingPolyline: navProvider.remainingPolyline,
                  memberPositions: navProvider.memberPositions,
                  currentUserId: currentUserId,
                  leaderId: leaderId,
                  isDrivingMode: _navState == NavigationState.active,
                  animationDuration: _fixInterval,
                  initialRouteBearing: navProvider.initialRouteBearing,
                  deviceHeading: _deviceHeading,
                  aiWaypoints: groupProvider.currentGroup?.route.aiWaypoints ?? [],
                  waypoints: groupProvider.currentGroup?.route.waypoints ?? [],
                  onWaypointTap: (wp) => _showWaypointDetails(context, wp),
                  detourPolyline: navProvider.detourPolyline,
                  sosPolyline: navProvider.sosPolyline,
                  nearbyPlaces: navProvider.nearbyPlaces,
                  liveAlternativeRoutes: navProvider.liveAlternativeRoutes,
                  onAlternativeRouteSelected: (route) => navProvider.switchToAlternativeRoute(route),
                  isDarkMode: DateTime.now().hour >= 18 || DateTime.now().hour < 6, // Night time check
                  activeSuggestion: navProvider.activeSuggestion,
                  onSuggestionDismiss: navProvider.dismissSuggestion,
                  onSuggestionNavigate: () {
                    final suggestionName = navProvider.activeSuggestion!.name;
                    navProvider.dismissSuggestion();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Adding $suggestionName to your route...'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                ),
              ),

              // 2. Top Bar Layer (or Directions Banner if Driving)
              SafeArea(
                child: Builder(
                  builder: (context) {
                    final sz = MediaQuery.sizeOf(context);
                    final isLand = sz.width > sz.height && sz.width > 480;
                    
                    if (_navState == NavigationState.active) {
                      return Align(
                        alignment: isLand ? Alignment.topLeft : Alignment.topCenter,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: isLand ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                          children: [
                            TutorialController.buildShowcase(
                              key: TutorialKeys.tbtInstructions,
                              title: 'Navigation Instructions',
                              description: 'Upcoming turns and maneuvers will appear here',
                              child: navProvider.isRerouting
                                  ? ReroutingBanner()
                                  : DirectionsBanner(
                                      currentStep: navProvider.currentStep,
                                      upcomingStep: navProvider.upcomingStep,
                                      nextAfterUpcomingStep: navProvider.nextUpcomingStep,
                                      distanceToNextManeuver: navProvider.distanceToNextStep,
                                      detourCurrentStep: navProvider.detourSteps.isNotEmpty ? navProvider.detourSteps.first : null,
                                      distanceToDetourManeuver: navProvider.detourSteps.isNotEmpty ? navProvider.detourSteps.first.distance.toDouble() : 0.0,
                                      isLandscape: isLand,
                                    ),
                            ),
                            // Offline Banner
                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              child: navProvider.isOffline
                                  ? Container(
                                      margin: EdgeInsets.only(
                                        top: 8,
                                        left: isLand ? 16 : 16,
                                        right: 16,
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent.shade700,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black26,
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: const [
                                          Icon(Icons.cloud_off, color: Colors.white, size: 20),
                                          SizedBox(width: 8),
                                          Text(
                                            'Offline — GPS navigation active',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      );
                    }
                    
                    return Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Drawer button
                              TutorialController.buildShowcase(
                                key: TutorialKeys.groupStatus,
                                title: 'Group Status',
                                description: 'View everyone\'s live status, speed, and distance',
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: colors.cardColor.withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: colors.borderColor),
                                  ),
                                  child: IconButton(
                                    icon: Icon(Icons.people_alt_rounded, color: colors.textPrimary),
                                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                                  ),
                                ),
                              ),
                              
                              // Exit button
                              TutorialController.buildShowcase(
                                key: TutorialKeys.exitNavBtn,
                                title: 'End Trip',
                                description: 'Stop navigation and return to the home screen',
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: colors.cardColor.withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: colors.borderColor),
                                  ),
                                  child: IconButton(
                                    icon: Icon(Icons.close_rounded, color: colors.textPrimary),
                                    onPressed: () {
                                      navProvider.stopNavigation();
                                      setState(() {
                                        _navState = NavigationState.browsing;
                                        _mapOrientation = MapOrientation.free;
                                      });
                                      Navigator.of(context).pushReplacementNamed('/home');
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ),
                    );
                  }
                ),
              ),

              // 2.5 Alert Banners Layer
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(top: _navState == NavigationState.active ? 120 : 60), // Sit below the top bar/banner
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: 280),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ...navProvider.activeAlerts.asMap().entries.map((entry) {
                              return AlertBanner(
                                alert: entry.value,
                                onDismiss: () => navProvider.dismissAlert(entry.key),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // 2.7 Compass Widget (top-right during active navigation)
              if (_navState == NavigationState.active)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16, top: 120),
                      child: CompassWidget(heading: _deviceHeading),
                    ),
                  ),
                ),

              // 2.8 Speedometer Widget (top-left during active navigation)
              if (_navState == NavigationState.active)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16, top: 120),
                      child: SpeedometerWidget(
                        speedKmh: navProvider.memberPositions[currentUserId]?.speed ?? 0,
                      ),
                    ),
                  ),
                ),

              // 3. Floating Action Buttons (Distinct Circular FABs matching Google Maps)
              Builder(
                builder: (context) {
                  final size = MediaQuery.sizeOf(context);
                  final isLandscape = size.width > size.height && size.width > 480;
                  
                  return SafeArea(
                    child: Align(
                      // In landscape, push it further down so it doesn't overlap top banners or right panels
                      alignment: isLandscape ? const Alignment(1.0, 0.4) : const Alignment(1.0, -0.3),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // SOS Button (Needs custom wrapping if we want it to match distinct FABs)
                            TutorialController.buildShowcase(
                              key: TutorialKeys.sosBtn,
                              title: 'Emergency SOS',
                              description: 'Tap in case of emergency. It alerts your group and shares your location instantly',
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    )
                                  ],
                                ),
                                child: SosButton(
                                  isActive: navProvider.isSosActive && navProvider.sosUserId == currentUserId,
                                  onTrigger: _triggerSos,
                                  onCancel: _cancelSos,
                                ),
                              ),
                            ),
                            SizedBox(height: 12),
                            
                            if (currentUserId != null && groupProvider.currentGroup?.isLeader(currentUserId) == true) ...[
                              TutorialController.buildShowcase(
                                key: TutorialKeys.regroupBtn,
                                title: 'Regroup',
                                description: 'Ask all members to navigate to your current location',
                                child: _CompactActionButton(
                                  icon: Icons.group_add_rounded,
                                  color: colors.accentPrimary,
                                  backgroundColor: Colors.white,
                                  hasShadow: true,
                                  onTap: _triggerRegroup,
                                ),
                              ),
                              SizedBox(height: 12),
                            ],
                            _CompactActionButton(
                              icon: Icons.local_cafe_rounded,
                              color: colors.accentWarning,
                              backgroundColor: Colors.white,
                              hasShadow: true,
                              onTap: _triggerStopRequest,
                            ),
                            SizedBox(height: 12),
                            
                            // TTS Toggle
                            _CompactActionButton(
                              icon: navProvider.ttsEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                              color: navProvider.ttsEnabled ? Colors.black87 : Colors.grey, 
                              backgroundColor: Colors.white,
                              hasShadow: true,
                              onTap: navProvider.toggleTts,
                            ),
                            SizedBox(height: 12),
                            
                            // Compass Orientation
                            TutorialController.buildShowcase(
                              key: TutorialKeys.mapOrientBtn,
                              title: 'Map Orientation',
                              description: 'Toggle between North-up, Heading-up, or Free look',
                              child: _CompactActionButton(
                                icon: _mapOrientation == MapOrientation.headingUp ? Icons.explore_rounded : 
                                    (_mapOrientation == MapOrientation.northUp ? Icons.explore_off_rounded : Icons.threesixty_rounded),
                                color: Colors.black87,
                                backgroundColor: Colors.white,
                                hasShadow: true,
                                onTap: _toggleMapOrientation,
                              ),
                            ),
                            SizedBox(height: 12),
                            
                            // Center on me
                            TutorialController.buildShowcase(
                              key: TutorialKeys.centerMapBtn,
                              title: 'Re-center Map',
                              description: 'Snap the map back to your current location',
                              child: _CompactActionButton(
                                icon: Icons.my_location_rounded,
                                color: _userPannedMap ? Colors.black87 : Colors.blueAccent,
                                backgroundColor: Colors.white,
                                hasShadow: true,
                                onTap: _centerOnMe,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
              ),

              // Speedometer moved to top-left (section 2.8)

              // 3.5 Floating "Re-center" button when user panned away
              if (_userPannedMap && _navState == NavigationState.active)
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 300),
                      child: GestureDetector(
                        onTap: _centerOnMe,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            color: colors.accentPrimary,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: colors.accentPrimary.withValues(alpha: 0.4),
                                blurRadius: 16,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.navigation_rounded, color: Colors.white, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Re-center',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // 3.7 Quick Stops Bar (above bottom sheet during navigation)
              if (_navState == NavigationState.active)
                Builder(
                  builder: (context) {
                    final size = MediaQuery.sizeOf(context);
                    final isLandscape = size.width > size.height && size.width > 480;
                    return SafeArea(
                      child: Align(
                        alignment: isLandscape ? Alignment.bottomRight : Alignment.bottomCenter,
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: isLandscape ? 16 : 170, // Adjusted after removing mode selector
                            left: isLandscape ? 380 : 0, // Avoid bottom sheet
                          ),
                          child: QuickStopsBar(
                            onCategoryTap: _onQuickStopCategoryTap,
                            activeCategory: navProvider.activeStopCategory,
                          ),
                        ),
                      ),
                    );
                  }
                ),

              // 3.75 Nearby Places List (above quick stops bar)
              if (_navState == NavigationState.active && navProvider.activeStopCategory != null && navProvider.nearbyPlaces.isNotEmpty)
                Builder(
                  builder: (context) {
                    final size = MediaQuery.sizeOf(context);
                    final isLandscape = size.width > size.height && size.width > 480;
                    return SafeArea(
                      child: Align(
                        alignment: isLandscape ? Alignment.bottomRight : Alignment.bottomCenter,
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: isLandscape ? 80 : 230, // Above the quick stops bar
                            left: isLandscape ? 380 : 0,
                          ),
                          child: SizedBox(
                            height: 110,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: navProvider.nearbyPlaces.length,
                              itemBuilder: (context, index) {
                                final place = navProvider.nearbyPlaces[index];
                                final isSelected = navProvider.selectedStop == place;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: _NearbyPlaceCard(
                                    place: place,
                                    isSelected: isSelected,
                                    onTap: () => _confirmAddStop(context, navProvider, place),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                ),

              // (Suggestion card moved to map popup bubbles in Component 6)

              // 4. Bottom Layer
              if (_navState == NavigationState.active)
                Builder(
                  builder: (context) {
                    final size = MediaQuery.sizeOf(context);
                    final isLandscape = size.width > size.height && size.width > 480;
                    return Align(
                      alignment: Alignment.bottomCenter,
                      child: SafeArea(
                        child: Container(
                          width: double.infinity,
                          child: SingleChildScrollView(
                            physics: const NeverScrollableScrollPhysics(),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [

                                TutorialController.buildShowcase(
                                  key: TutorialKeys.etaBox,
                                  title: 'Trip Progress',
                                  description: 'Check your ETA, distance, and speed here',
                                  child: TripBottomSheet(
                                    distanceRemaining: navProvider.remainingDistance > 0 ? navProvider.remainingDistance : navProvider.routeDistance,
                                    durationRemaining: navProvider.remainingDuration > 0 ? navProvider.remainingDuration : navProvider.routeDuration,
                                    currentSpeed: navProvider.memberPositions[currentUserId]?.speed ?? 0,
                                    memberPositions: navProvider.memberPositions,
                                    currentUserId: currentUserId,
                                    isLandscape: isLandscape,
                                    onExit: () async {
                                      navProvider.stopNavigation();
                                    setState(() {
                                       _navState = NavigationState.browsing;
                                       _mapOrientation = MapOrientation.free;
                                    });
                                    
                                    // Request In-App Review
                                    try {
                                      final InAppReview inAppReview = InAppReview.instance;
                                      if (await inAppReview.isAvailable()) {
                                        await inAppReview.requestReview();
                                      }
                                    } catch (e) {
                                      debugPrint('In-App Review error: $e');
                                    }
                                  },
                                  onMemberTap: (userId) {
                                    final pos = navProvider.memberPositions[userId];
                                    if (pos != null) {
                                      _mapController.move(pos.latLng, 16.0);
                                    }
                                  },
                                  onStepsTap: () => _showStepsSheet(context),
                                ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                )
              else if (_navState == NavigationState.preview)
                Builder(
                  builder: (context) {
                    final size = MediaQuery.sizeOf(context);
                    final colors = AppColors.of(context);
                    final isLandscape = size.width > size.height && size.width > 480;
                    return Stack(
                      children: [
                        // Start Navigation Card (Bottom Left in Landscape, Bottom Center in Portrait)
                        Align(
                          alignment: isLandscape ? Alignment.bottomLeft : Alignment.bottomCenter,
                          child: SafeArea(
                            child: SingleChildScrollView(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  bottom: 24,
                                  left: 16,
                                  right: isLandscape ? 0 : 16,
                                ),
                                child: Container(
                                  width: isLandscape ? 350 : double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: colors.cardColor,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 15, offset: Offset(0, 5))
                                    ]
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                        children: [
                                          _buildDashboardStat(Icons.directions_car_rounded, 'Distance', '${(navProvider.routeDistance / 1000).toStringAsFixed(1)} km'),
                                          Container(width: 1, height: 40, color: Colors.grey.shade300),
                                          _buildDashboardStat(Icons.timer_rounded, 'ETA', '${(navProvider.routeDuration / 60).toStringAsFixed(0)} min'),
                                        ],
                                      ),
                                      SizedBox(height: 16),
                                      SizedBox(
                                        width: double.infinity,
                                        height: 56,
                                        child: ElevatedButton(
                                          onPressed: _centerOnMe,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF1976D2), // Google Blue
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                                            elevation: 0,
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.navigation_rounded, color: Colors.white),
                                              SizedBox(width: 8),
                                              Text('Start Navigation', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        
                        // Location Details Card (Top Left in Landscape)
                        if (isLandscape)
                          Align(
                            alignment: Alignment.topLeft,
                            child: SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 16, left: 16),
                                child: Container(
                                  width: 350,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, offset: Offset(0, 4))
                                    ]
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.my_location_rounded, color: Colors.blueAccent, size: 20),
                                          SizedBox(width: 12),
                                          Expanded(
                                            child: Text('Your Location', style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w500)),
                                          ),
                                        ],
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(left: 9),
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Container(width: 2, height: 16, color: Colors.grey.shade300),
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Icon(Icons.location_on_rounded, color: Colors.redAccent, size: 20),
                                          SizedBox(width: 12),
                                          Expanded(
                                            child: Text('Destination', style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w500)),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  }
                )
              else if (navProvider.nearbyPlaces.isNotEmpty)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    child: Container(
                      height: 120,
                      margin: const EdgeInsets.only(bottom: 24),
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: navProvider.nearbyPlaces.length,
                        itemBuilder: (context, index) {
                          return PoiCard(
                            place: navProvider.nearbyPlaces[index],
                            onTap: () {
                              final place = navProvider.nearbyPlaces[index];
                              if (place.lat != null && place.lng != null) {
                                _mapController.move(LatLng(place.lat!, place.lng!), 16.0);
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),

              // 5. Arrival Overlay
              if (navProvider.hasArrived)
                ArrivalScreen(
                  totalDistance: navProvider.totalDistanceTraveled,
                  tripDuration: navProvider.tripStartTime != null 
                      ? DateTime.now().difference(navProvider.tripStartTime!)
                      : Duration.zero,
                  destinationName: navProvider.selectedStop?.name ?? groupProvider.currentGroup?.route.destination.name,
                  onDone: () {
                    navProvider.dismissArrival();
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDashboardStat(IconData icon, String label, String value) {
    final colors = AppColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: colors.textSecondary),
            SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, color: colors.textSecondary)),
          ],
        ),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: colors.textPrimary),
        ),
      ],
    );
  }

  Widget _buildModeIcon(String mode, IconData icon, NavigationProvider navProvider) {
    final colors = AppColors.of(context);
    final isSelected = navProvider.runtimeTransportMode == mode;
    return GestureDetector(
      onTap: () => navProvider.setTransportMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? colors.accentPrimary : colors.cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? Colors.transparent : colors.borderColor.withValues(alpha: 0.5),
            width: 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: colors.accentPrimary.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ] : [],
        ),
        child: Icon(
          icon,
          size: 24,
          color: isSelected ? Colors.white : colors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildMembersDrawer(BuildContext context) {
    final colors = AppColors.of(context);
    return Drawer(
      backgroundColor: colors.primaryBackground,
      child: SafeArea(
        child: Consumer2<NavigationProvider, GroupProvider>(
          builder: (context, navProvider, groupProvider, _) {
            final group = groupProvider.currentGroup;
            if (group == null) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: colors.textPrimary),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Live Locations',
                        style: TextStyle(fontSize: 14, color: colors.accentPrimary),
                      ),
                    ],
                  ),
                ),
                Divider(color: colors.borderColor),
                Expanded(
                  child: ListView.builder(
                    itemCount: group.members.length,
                    itemBuilder: (context, index) {
                      final member = group.members[index];
                      final pos = navProvider.memberPositions[member.userId];
                      
                      // Status color
                      Color statusColor = colors.textSecondary;
                      if (pos != null) {
                        if (pos.status == 'sos') {
                          statusColor = colors.accentDanger;
                        } else if (pos.status == 'deviated' || pos.status == 'separated') {
                          statusColor = colors.accentWarning;
                        } else {
                          statusColor = colors.accentSecondary;
                        }
                      }

                      return ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: colors.cardColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: statusColor, width: 2),
                          ),
                          child: Center(
                            child: Text(
                              member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                              style: TextStyle(fontWeight: FontWeight.w700, color: colors.textPrimary),
                            ),
                          ),
                        ),
                        title: Text(member.name, style: TextStyle(color: colors.textPrimary)),
                        subtitle: Text(
                          pos != null ? '${pos.speed.toStringAsFixed(0)} km/h • ${pos.status}' : 'Waiting for GPS...',
                          style: TextStyle(color: colors.textSecondary, fontSize: 12),
                        ),
                        onTap: () {
                          if (pos != null) {
                            Navigator.pop(context); // Close drawer
                            _mapController.move(pos.latLng, 16.0);
                          }
                        },
                      );
                    },
                  ),
                ),
                
                // Fetch Nearby POIs tools
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Find Nearby',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary),
                      ),
                      SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildPoiButton(context, 'Fuel', Icons.local_gas_station_rounded, 'gas_station'),
                          _buildPoiButton(context, 'Food', Icons.restaurant_rounded, 'restaurant'),
                          _buildPoiButton(context, 'Hospital', Icons.local_hospital_rounded, 'hospital'),
                        ],
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
  }

  Widget _buildPoiButton(BuildContext context, String label, IconData icon, String type) {
    final colors = AppColors.of(context);
    return InkWell(
      onTap: () async {
        Navigator.pop(context); // close drawer
        final nav = context.read<NavigationProvider>();
        final pos = nav.locationService.lastPosition;
        if (pos != null) {
          await nav.fetchNearbyPlaces(pos.latitude, pos.longitude, type);
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.borderColor),
            ),
            child: Icon(icon, color: colors.accentPrimary),
          ),
          SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 12, color: colors.textSecondary)),
        ],
      ),
    );
  }

  Future<Map<String, String>> _fetchWikiData(String query, double lat, double lng) async {
    try {
      // Use geosearch to find Wikipedia articles near the exact coordinates (within 5km)
      final uri = Uri.parse('https://en.wikipedia.org/w/api.php?action=query&generator=geosearch&ggscoord=$lat|$lng&ggsradius=5000&ggslimit=10&prop=pageimages|extracts&exintro&explaintext&pithumbsize=600&format=json');
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final pages = data['query']?['pages'] as Map<String, dynamic>?;
        if (pages != null && pages.isNotEmpty) {
          // Find the first page that has a thumbnail
          Map<String, dynamic>? bestPage;
          for (final page in pages.values) {
            if (page['thumbnail'] != null && page['thumbnail']['source'] != null) {
              bestPage = page as Map<String, dynamic>;
              break;
            }
          }
          // Fallback to the very first result if none have images
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

  void _showWaypointDetails(BuildContext context, AIWaypoint wp) {
    final colors = AppColors.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: colors.primaryBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: colors.borderColor),
          ),
          child: FutureBuilder<Map<String, String>>(
            future: _fetchWikiData(wp.name, wp.lat, wp.lng),
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
                        color: colors.textTertiary.withValues(alpha: 0.5),
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
                            color: colors.surfaceColor,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (isLoading)
                                  Center(child: CircularProgressIndicator())
                                else if (hasImage)
                                  Image.network(
                                    wikiData['image']!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Center(
                                      child: Icon(Icons.landscape_rounded, size: 64, color: colors.textTertiary),
                                    ),
                                  )
                                else
                                  Center(
                                    child: Icon(Icons.landscape_rounded, size: 64, color: colors.textTertiary),
                                  ),
                                Positioned(
                                  top: 12,
                                  right: 12,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.6),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.favorite_border_rounded, color: Colors.white, size: 20),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 20),
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF4CAF50), width: 2),
                              ),
                              child: Icon(wp.iconData, color: const Color(0xFF4CAF50), size: 28),
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    wp.name,
                                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colors.textPrimary),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    wp.type.toUpperCase().replaceAll('_', ' '),
                                    style: TextStyle(color: colors.accentPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Why we recommended this:',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colors.textPrimary),
                        ),
                        SizedBox(height: 8),
                        Text(
                          wp.reason,
                          style: TextStyle(fontSize: 15, color: colors.textSecondary, height: 1.5),
                        ),
                        SizedBox(height: 24),
                        
                        // Factual Info Section
                        Text(
                          'Factual Information',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colors.textPrimary),
                        ),
                        SizedBox(height: 16),
                        if (isLoading)
                          Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                        else if (hasExtract)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colors.surfaceColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: colors.borderColor),
                            ),
                            child: Text(
                              wikiData['extract']!,
                              style: TextStyle(color: colors.textSecondary, height: 1.5, fontSize: 14),
                            ),
                          )
                        else
                          Text(
                            'No extended factual information available from Open Data sources.',
                            style: TextStyle(color: colors.textTertiary, fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                  ),
                  // Action Bar
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                    decoration: BoxDecoration(
                      color: colors.primaryBackground,
                      border: Border(top: BorderSide(color: colors.borderColor)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 56,
                            decoration: BoxDecoration(
                              color: colors.surfaceColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: colors.borderColor),
                            ),
                            child: Center(
                              child: Text('Save', style: TextStyle(fontWeight: FontWeight.w600, color: colors.textPrimary)),
                            ),
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: Container(
                            height: 56,
                            decoration: BoxDecoration(
                              color: colors.accentPrimary,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Text('Navigate', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
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
      ),
    );
  }
}

/// Compact action button for the floating pill (40×40 with tap animation)
class _CompactActionButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final bool hasShadow;

  const _CompactActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.backgroundColor,
    this.hasShadow = false,
  });

  @override
  State<_CompactActionButton> createState() => _CompactActionButtonState();
}

class _CompactActionButtonState extends State<_CompactActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _tapController;
  late Animation<double> _tapScale;

  @override
  void initState() {
    super.initState();
    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );
    _tapScale = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _tapController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _tapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _tapController,
      builder: (context, child) {
        return GestureDetector(
          onTapDown: (_) => _tapController.forward(),
          onTapUp: (_) {
            _tapController.reverse();
            widget.onTap();
          },
          onTapCancel: () => _tapController.reverse(),
          child: Transform.scale(
            scale: _tapScale.value,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.backgroundColor ?? Colors.transparent,
                shape: BoxShape.circle,
                boxShadow: widget.hasShadow
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        )
                      ]
                    : null,
              ),
              child: Icon(
                widget.icon,
                color: widget.color,
                size: 24,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NearbyPlaceCard extends StatelessWidget {
  final NearbyPlace place;
  final bool isSelected;
  final VoidCallback onTap;

  const _NearbyPlaceCard({
    required this.place,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? colors.accentPrimary : colors.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? colors.accentPrimary : colors.borderColor,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              place.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : colors.textPrimary,
              ),
            ),
            if (place.address != null)
              Text(
                place.address!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected ? Colors.white70 : colors.textTertiary,
                ),
              ),
            if (place.rating != null || place.distance != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  if (place.rating != null) ...[
                    Icon(
                      Icons.star_rounded,
                      color: isSelected ? Colors.white : const Color(0xFFFFC107),
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      place.rating!.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : colors.textSecondary,
                      ),
                    ),
                  ],
                  if (place.rating != null && place.distance != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text('•', style: TextStyle(color: isSelected ? Colors.white70 : colors.textTertiary, fontSize: 10)),
                    ),
                  if (place.distance != null)
                    Text(
                      place.distance! > 1000 
                        ? '${(place.distance! / 1000).toStringAsFixed(1)} km'
                        : '${place.distance!.toInt()} m',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isSelected ? Colors.white : colors.accentPrimary,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StopRequestSheet extends StatelessWidget {
  final Function(String) onSubmit;

  const _StopRequestSheet({required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final reasons = ['Fuel', 'Food', 'Restroom', 'Mechanical Issue', 'Other'];

    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 16, top: 24, left: 24, right: 24),
      decoration: BoxDecoration(
        color: colors.primaryBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(width: 40, height: 4, decoration: BoxDecoration(color: colors.textTertiary, borderRadius: BorderRadius.circular(2))),
          ),
          SizedBox(height: 24),
          Text('Request Stop', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colors.textPrimary)),
          SizedBox(height: 8),
          Text('Let the group know why you need to stop.', style: TextStyle(color: colors.textSecondary)),
          SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: reasons.map((reason) {
              return InkWell(
                onTap: () => onSubmit(reason),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: colors.cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colors.borderColor),
                  ),
                  child: Text(
                    reason,
                    style: TextStyle(fontWeight: FontWeight.w600, color: colors.textPrimary),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
