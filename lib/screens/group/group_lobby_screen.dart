import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../core/app_colors.dart';
import '../../core/theme.dart';
import '../../widgets/skeleton_loader.dart';
import '../../utils/polyline_decoder.dart';
import '../../core/tutorial_controller.dart';
import '../../core/tutorial_keys.dart';

class GroupLobbyScreen extends StatefulWidget {
  final String groupId;

  const GroupLobbyScreen({super.key, required this.groupId});

  @override
  State<GroupLobbyScreen> createState() => _GroupLobbyScreenState();
}

class _GroupLobbyScreenState extends State<GroupLobbyScreen> {
  bool _isRefreshing = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  final MapController _mapController = MapController();
  final DraggableScrollableController _sheetController = DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _loadGroup();
      if (!await TutorialController.hasCompletedTutorial()) {
        // Expand the sheet so all tutorial items are visible
        if (mounted) {
          _sheetController.animateTo(0.9, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (mounted) {
        TutorialController.startLobbyTutorial(context);
      }
    });
  }

  Future<void> _loadGroup() async {
    setState(() => _isRefreshing = true);
    await context.read<GroupProvider>().fetchGroup(widget.groupId);
    if (mounted) setState(() => _isRefreshing = false);
  }

  void _copyInviteCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Invite code copied!'),
        backgroundColor: AppColors.of(context).accentPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _shareInviteCode(String code, String groupName) {
    Share.share('Join my group "$groupName" on RoUniity! Use invite code: $code');
  }

  void _startTrip(GroupModel group) async {
    final navProvider = context.read<NavigationProvider>();
    final authProvider = context.read<AuthProvider>();

    if (group.isLeader(authProvider.currentUser!.id)) {
      await context.read<GroupProvider>().updateStatus(group.id, 'active');
      navProvider.wsService.startTrip(group.id);
    }
    
    if (mounted) {
      await navProvider.startNavigation(group);
      Navigator.of(context).pushReplacementNamed('/live-navigation', arguments: group.id);
    }
  }

  void _downloadMap(GroupModel group) {
    if (!group.route.hasRoute || group.route.polyline == null) return;
    
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    final polyline = decodePolyline(group.route.polyline!);
    final region = RectangleRegion(LatLngBounds.fromPoints(polyline));
    
    final downloadableRegion = region.toDownloadable(
      minZoom: 12,
      maxZoom: 18,
      options: TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.vorniity.rouniity',
      ),
    );

    final store = const FMTCStore('mapStore');
    
    final streams = store.download.startForeground(
      region: downloadableRegion,
    );
    
    streams.downloadProgress.listen((progress) {
      if (mounted) {
        setState(() {
          _downloadProgress = progress.percentageProgress / 100.0;
        });
      }
    }, onDone: () {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Map saved for offline use!'),
            backgroundColor: AppColors.of(context).accentSecondary,
          ),
        );
      }
    }, onError: (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: AppColors.of(context).accentDanger,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: colors.primaryBackground,
      body: Consumer2<GroupProvider, AuthProvider>(
        builder: (context, groupProvider, authProvider, _) {
          final group = groupProvider.currentGroup;
          
          if (group == null || group.id != widget.groupId) {
            return const SkeletonLobby();
          }

          final isLeader = group.isLeader(authProvider.currentUser!.id);

          return Stack(
            children: [
              // MAP BACKGROUND
              Builder(
                builder: (context) {
                  final size = MediaQuery.sizeOf(context);
                  final isLandscape = size.width > size.height && size.width > 480;
                  final panelWidth = isLandscape ? (size.width * 0.45 < 350.0 ? 350.0 : size.width * 0.45) : 0.0;
                  return Positioned.fill(
                    bottom: isLandscape ? 0 : size.height * 0.4,
                    right: panelWidth,
                    child: _buildMapPreview(group, colors),
                  );
                }
              ),

              // HEADER
              Builder(
                builder: (context) {
                  final size = MediaQuery.sizeOf(context);
                  final isLandscape = size.width > size.height && size.width > 480;
                  final panelWidth = isLandscape ? (size.width * 0.45 < 350.0 ? 350.0 : size.width * 0.45) : 0.0;
                  return Positioned(
                    top: 0, left: 0, right: panelWidth,
                    child: _buildHeader(group, colors, theme),
                  );
                }
              ),

              // DRAGGABLE BOTTOM SHEET LOBBY
              Builder(
                builder: (context) {
                  final size = MediaQuery.sizeOf(context);
                  final isLandscape = size.width > size.height && size.width > 480;
                  final panelWidth = isLandscape ? (size.width * 0.45 < 350.0 ? 350.0 : size.width * 0.45) : 0.0;
                  if (isLandscape) {
                    return Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: panelWidth,
                        child: _buildDraggableLobby(group, isLeader, colors, theme),
                      ),
                    );
                  }
                  return _buildDraggableLobby(group, isLeader, colors, theme);
                }
              ),
            ],
          );
        },
      ),
    );
  }

  List<Marker> _buildManeuverMarkers(List<dynamic> steps) {
    if (steps.isEmpty) return [];
    
    final markers = <Marker>[];
    
    // Skip the first and last step to avoid crowding origin/destination
    for (int i = 1; i < steps.length - 1; i++) {
      final step = steps[i];
      final maneuver = (step['maneuver'] as String?)?.toLowerCase() ?? '';
      final instruction = (step['instruction'] as String?) ?? (step['html_instructions'] as String?) ?? '';
      
      if (maneuver.isEmpty && instruction.isEmpty) continue;
      
      bool isSignificant = false;
      IconData icon = Icons.turn_right_rounded;
      String shortText = '';
      
      if (maneuver.contains('left') || instruction.toLowerCase().contains('turn left')) {
        isSignificant = true; icon = Icons.turn_left_rounded; shortText = 'Turn left';
      } else if (maneuver.contains('right') || instruction.toLowerCase().contains('turn right')) {
        isSignificant = true; icon = Icons.turn_right_rounded; shortText = 'Turn right';
      } else if (maneuver.contains('u-turn') || instruction.toLowerCase().contains('u-turn')) {
        isSignificant = true; icon = Icons.u_turn_left_rounded; shortText = 'U-Turn';
      } else if (maneuver.contains('roundabout') || instruction.toLowerCase().contains('roundabout')) {
        isSignificant = true; icon = Icons.roundabout_right_rounded; shortText = 'Roundabout';
      } else if (maneuver.contains('merge') || maneuver.contains('fork') || instruction.toLowerCase().contains('merge') || instruction.toLowerCase().contains('exit')) {
        isSignificant = true; icon = Icons.merge_type_rounded; shortText = 'Transition';
      }
      
      if (!isSignificant) continue;
      
      final startLoc = step['start_location'] ?? step['startLocation']; // Account for different case styles
      if (startLoc == null || startLoc['lat'] == null || startLoc['lng'] == null) continue;
      
      final pt = LatLng((startLoc['lat'] as num).toDouble(), (startLoc['lng'] as num).toDouble());
      
      markers.add(
        Marker(
          point: pt,
          width: 120, // Enough width for text
          height: 40,
          alignment: Alignment.topRight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                bottom: -2,
                left: 12,
                child: Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(
                    width: 12, height: 12,
                    color: const Color(0xFF0022AA),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0022AA),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 3))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(shortText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    return markers;
  }

  /// Finds the nearest point on the polyline for a given waypoint
  LatLng _nearestPointOnPolyline(LatLng point, List<LatLng> polyline) {
    if (polyline.isEmpty) return point;
    
    double minDist = double.infinity;
    LatLng nearest = polyline.first;
    
    for (final p in polyline) {
      final dist = _distanceSq(point, p);
      if (dist < minDist) {
        minDist = dist;
        nearest = p;
      }
    }
    return nearest;
  }
  
  double _distanceSq(LatLng a, LatLng b) {
    final dlat = a.latitude - b.latitude;
    final dlng = a.longitude - b.longitude;
    return dlat * dlat + dlng * dlng;
  }

  Widget _buildMapPreview(GroupModel group, AppColorScheme colors) {
    LatLng? origin;
    LatLng? dest;
    List<LatLng> polyline = [];
    
    if (group.route.hasRoute) {
      if (group.route.origin.hasLocation) {
        origin = LatLng(group.route.origin.lat!, group.route.origin.lng!);
      }
      if (group.route.destination.hasLocation) {
        dest = LatLng(group.route.destination.lat!, group.route.destination.lng!);
      }
      if (group.route.polyline != null) {
        polyline = decodePolyline(group.route.polyline!);
      }
    }

    // (Waypoint connectors removed since AI waypoints are now natively part of the route)
    final List<Polyline<Object>> waypointConnectors = [];


    final bounds = (origin != null && dest != null) ? LatLngBounds.fromPoints([origin, dest, ...polyline]) : null;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: origin ?? const LatLng(0, 0),
        initialZoom: 12,
        initialCameraFit: bounds != null ? CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(40)) : null,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.vorniity.rouniity',
          tileProvider: const FMTCStore('mapStore').getTileProvider(),
        ),
        if (polyline.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(points: polyline, color: colors.accentPrimary, strokeWidth: 5.0),
            ],
          ),
        // Waypoint connector lines (drawn before markers so they appear behind)
        if (waypointConnectors.isNotEmpty)
          PolylineLayer(polylines: waypointConnectors),
        if (group.route.steps.isNotEmpty)
          MarkerLayer(
            markers: _buildManeuverMarkers(group.route.steps),
          ),
        MarkerLayer(
          markers: [
            // AI Waypoints
            if (group.route.hasRoute && group.route.aiWaypoints != null)
              ...group.route.aiWaypoints!.map((wp) => Marker(
                point: LatLng(wp.lat, wp.lng),
                width: 44,
                height: 44,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                    border: Border.all(color: const Color(0xFF4CAF50), width: 2.5),
                  ),
                  child: Center(
                    child: Icon(wp.iconData, color: const Color(0xFF4CAF50), size: 20),
                  ),
                ),
              )),
            // Origin & Dest
            if (origin != null)
              Marker(point: origin, width: 40, height: 40, child: Icon(Icons.my_location, color: colors.accentSecondary, size: 30)),
            if (dest != null)
              Marker(point: dest, width: 40, height: 40, child: Icon(Icons.location_on, color: colors.accentDanger, size: 40)),
          ],
        ),
      ],
    );
  }

  Widget _buildHeader(GroupModel group, AppColorScheme colors, ThemeData theme) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8, bottom: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [colors.primaryBackground.withValues(alpha: 0.8), Colors.transparent],
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: colors.surfaceColor.withValues(alpha: 0.8), shape: BoxShape.circle),
                  child: Icon(Icons.arrow_back_rounded, color: colors.textPrimary, size: 20),
                ),
              ),
              Expanded(
                child: Text(
                  group.name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: colors.textPrimary),
                ),
              ),
              const SizedBox(width: 56),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDraggableLobby(GroupModel group, bool isLeader, AppColorScheme colors, ThemeData theme) {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.55,
      minChildSize: 0.2,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              decoration: BoxDecoration(
                color: colors.primaryBackground.withValues(alpha: 0.85),
                border: Border(top: BorderSide(color: colors.borderColor.withValues(alpha: 0.5))),
              ),
              child: Stack(
                children: [
                  RefreshIndicator(
                    onRefresh: _loadGroup,
                    color: colors.accentPrimary,
                    child: SingleChildScrollView(
                      controller: scrollController,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 40, height: 5,
                              decoration: BoxDecoration(
                                color: colors.textTertiary.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          _buildInviteCodeCard(group, colors, theme),
                          const SizedBox(height: 32),
                          _buildRouteDetails(group, isLeader, colors, theme),
                          const SizedBox(height: 32),
                          _buildMembersList(group, colors, theme),
                        ],
                      ),
                    ),
                  ),
                  
                  // Start Button fixed at bottom
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter, end: Alignment.topCenter,
                          colors: [colors.primaryBackground, colors.primaryBackground.withValues(alpha: 0.0)],
                        ),
                      ),
                      child: TutorialController.buildShowcase(
                        key: TutorialKeys.startNavBtn,
                        title: 'Ready to go?',
                        description: 'Tap here to start navigation once everyone is ready',
                        disposeOnTap: true,
                        onTargetClick: (!isLeader && group.status != 'active') ? null : () => _startTrip(group),
                        child: SizedBox(
                          width: double.infinity, height: 56,
                          child: Container(
                          decoration: BoxDecoration(
                            gradient: colors.accentGradient,
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: [BoxShadow(color: colors.accentPrimary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 5))],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: (!isLeader && group.status != 'active') ? null : () => _startTrip(group),
                            icon: Icon(isLeader ? Icons.navigation_rounded : Icons.login_rounded, color: Colors.white),
                            label: Text(
                              isLeader ? 'Start Trip' : 'Join Navigation',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                            ),
                          ),
                        ),
                      ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInviteCodeCard(GroupModel group, AppColorScheme colors, ThemeData theme) {
    return TutorialController.buildShowcase(
      key: TutorialKeys.partyCode,
      title: 'Invite your group',
      description: 'Share this Party Code or QR Code with your friends to join the journey',
      child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: colors.surfaceColor,
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: colors.accentPrimary.withValues(alpha: 0.15),
            blurRadius: 40,
            spreadRadius: 10,
          ),
        ],
        border: Border.all(
          color: colors.accentPrimary.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: colors.accentPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.stars_rounded, color: colors.accentPrimary, size: 16),
                const SizedBox(width: 8),
                Text('YOUR INVITE CODE', style: theme.textTheme.labelMedium?.copyWith(color: colors.accentPrimary, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              ],
            ),
          ),
          const SizedBox(height: 32),
          // QR Code for easy scanning
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: colors.accentPrimary.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  )
                ]
              ),
              child: QrImageView(
                data: group.inviteCode,
                version: QrVersions.auto,
                size: 160.0,
                backgroundColor: Colors.white,
                eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
              ),
            ),
          ),
          const SizedBox(height: 32),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: group.inviteCode.split('').map((char) {
              return Container(
                width: 42,
                height: 52,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: colors.surfaceColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.accentPrimary.withValues(alpha: 0.5), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: colors.accentPrimary.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  char.toUpperCase(),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: colors.accentPrimary,
                  ),
                ),
              );
            }).toList(),
          ),
          ),
          const SizedBox(height: 40),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(Icons.copy_rounded, 'Copy', colors.textPrimary, () => _copyInviteCode(group.inviteCode), colors),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildActionButton(Icons.share_rounded, 'Share', colors.accentExtra, () => _shareInviteCode(group.inviteCode, group.name), colors),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color, VoidCallback onTap, AppColorScheme colors) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: color),
      label: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.1),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }

  Widget _buildRouteDetails(GroupModel group, bool isLeader, AppColorScheme colors, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Route', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: colors.textPrimary)),
            if (isLeader)
              TextButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Route editing coming soon!'), backgroundColor: colors.accentPrimary));
                },
                icon: Icon(Icons.edit_location_alt_outlined, size: 18, color: colors.accentPrimary),
                label: Text(group.route.hasRoute ? 'Edit' : 'Add Route', style: TextStyle(color: colors.accentPrimary)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colors.surfaceColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: colors.borderColor),
          ),
          child: group.route.hasRoute ? Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: colors.accentPrimary.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: Icon(Icons.my_location_rounded, color: colors.accentPrimary, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Text(group.route.origin.name.isNotEmpty ? group.route.origin.name : group.route.origin.address, style: theme.textTheme.bodyLarge?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 17, top: 4, bottom: 4),
                child: Align(alignment: Alignment.centerLeft, child: Container(width: 2, height: 24, color: colors.borderColor)),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: colors.accentSecondary.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: Icon(Icons.location_on_rounded, color: colors.accentSecondary, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Text(group.route.destination.name.isNotEmpty ? group.route.destination.name : group.route.destination.address, style: theme.textTheme.bodyLarge?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat(Icons.route_outlined, group.route.distanceText, colors, theme),
                  _buildStat(Icons.access_time_rounded, group.route.durationText, colors, theme),
                  _buildStat(Icons.place_outlined, '${group.route.waypoints.length} stops', colors, theme),
                ],
              ),
              if (group.route.hasRoute) ...[
                const SizedBox(height: 24),
                _isDownloading
                  ? Column(
                      children: [
                        Text('Downloading map tiles...', style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary)),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: _downloadProgress, color: colors.accentSecondary, backgroundColor: colors.borderColor),
                      ],
                    )
                  : TutorialController.buildShowcase(
                      key: TutorialKeys.offlineBtn,
                      title: 'Offline Navigation',
                      description: 'Download the route to keep navigating even if you lose signal',
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _downloadMap(group),
                          icon: Icon(Icons.download_for_offline_rounded, color: colors.accentSecondary),
                          label: Text('Save Map for Offline', style: TextStyle(color: colors.accentSecondary, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: colors.accentSecondary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                    ),
              ],
            ],
          ) : Center(child: Text('No route planned yet.', style: TextStyle(color: colors.textSecondary))),
        ),
      ],
    );
  }

  Widget _buildStat(IconData icon, String text, AppColorScheme colors, ThemeData theme) {
    return Column(
      children: [
        Icon(icon, size: 24, color: colors.textSecondary),
        const SizedBox(height: 8),
        Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildMembersList(GroupModel group, AppColorScheme colors, ThemeData theme) {
    final myId = context.read<AuthProvider>().currentUser?.id;
    return TutorialController.buildShowcase(
      key: TutorialKeys.groupMembers,
      title: 'Your group',
      description: 'See everyone who has joined your journey',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Row(
          children: [
            Text('Members', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: colors.textPrimary)),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: colors.surfaceColor, borderRadius: BorderRadius.circular(12)),
              child: Text('${group.members.length}', style: TextStyle(fontWeight: FontWeight.bold, color: colors.textSecondary)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: group.members.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final member = group.members[index];
            final isMe = member.userId == myId;

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceColor.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: isMe ? colors.accentPrimary.withValues(alpha: 0.3) : Colors.transparent),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: member.isLeader ? colors.accentExtra.withValues(alpha: 0.2) : colors.cardColor,
                      shape: BoxShape.circle,
                    ),
                    child: Center(child: Text(member.name.isNotEmpty ? member.name[0].toUpperCase() : '?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: member.isLeader ? colors.accentExtra : colors.textPrimary))),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(member.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: colors.textPrimary)),
                            if (isMe) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: colors.accentPrimary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                                child: Text('You', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colors.accentPrimary)),
                              ),
                            ]
                          ],
                        ),
                        if (member.isLeader) ...[
                          const SizedBox(height: 4),
                          Text('Trip Leader', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colors.accentExtra)),
                        ],
                      ],
                    ),
                  ),
                  Icon(Icons.check_circle_rounded, color: colors.accentSecondary.withValues(alpha: 0.8), size: 24),
                ],
              ),
            );
          },
        ),
      ],
      ),
    );
  }
}
