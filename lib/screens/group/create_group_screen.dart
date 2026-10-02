import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../services/ola_maps_service.dart';
import '../../services/location_service.dart';
import '../../utils/polyline_decoder.dart';
import '../../widgets/skeleton_loader.dart';
import 'route_style_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _fromController = TextEditingController();
  final _toController = TextEditingController();
  final _tripNameController = TextEditingController();

  final _fromFocus = FocusNode();
  final _toFocus = FocusNode();

  final OlaMapsService _mapsService = OlaMapsService();
  String _selectedMode = 'driving';
  String _travelType = 'group';
  bool _isGeocoding = false;
  bool _isLoadingRoute = false;

  // Live route data — populated after geocoding
  LatLng? _originLatLng;
  LatLng? _destLatLng;
  String? _originLabel;
  String? _destLabel;
  String? _routeDistance;
  String? _routeTime;
  String? _routePolyline;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _fromFocus.addListener(() => setState(() {}));
    _toFocus.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null && args.containsKey('destinationName')) {
        _toController.text = args['destinationName'] as String;
        // Automatically fetch current location and geocode
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _useCurrentLocation(_fromController);
        });
      }
    }
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _tripNameController.dispose();
    _fromFocus.dispose();
    _toFocus.dispose();
    super.dispose();
  }

  Future<Iterable<String>> _getPlaceSuggestions(String query) async {
    if (query.length < 3) return const Iterable<String>.empty();
    try {
      if (mounted) _mapsService.setToken(context.read<AuthProvider>().token ?? '');
      final res = await _mapsService.autocomplete(input: query).timeout(const Duration(seconds: 5));
      if (res['predictions'] != null) {
        return (res['predictions'] as List).map((e) => e['description'] as String);
      }
    } catch (e) {
      debugPrint('[CreateGroup] Autocomplete error: $e');
    }
    return const Iterable<String>.empty();
  }

  /// Geocode both locations, get live route data, and update preview
  Future<void> _geocodeAndPreview() async {
    if (_fromController.text.trim().isEmpty || _toController.text.trim().isEmpty) return;

    setState(() { _isLoadingRoute = true; });

    try {
      if (mounted) _mapsService.setToken(context.read<AuthProvider>().token ?? '');

      final origin = await _resolveLocation(_fromController.text.trim());
      final destination = await _resolveLocation(_toController.text.trim());

      if (origin.lat != null && origin.lng != null && destination.lat != null && destination.lng != null && mounted) {
        String oLabel = origin.name;
        if (oLabel.contains(',')) oLabel = oLabel.split(',').first.trim();
        String dLabel = destination.name;
        if (dLabel.contains(',')) dLabel = dLabel.split(',').first.trim();

        String? distStr;
        String? timeStr;

        try {
          // Fetch live directions from Ola API
          final routeData = await _mapsService.getDirections(
            originLat: origin.lat!,
            originLng: origin.lng!,
            destLat: destination.lat!,
            destLng: destination.lng!,
            mode: _selectedMode == 'walking' ? 'walking' : _selectedMode == 'two_wheeler' ? 'motorcycle' : 'driving',
            alternatives: true,
          );
          
          if (routeData['routes']?.isNotEmpty == true) {
            final leg = routeData['routes'][0]['legs'][0];
            final distMeters = leg['distance'] ?? 0;
            final timeSeconds = leg['duration'] ?? 0;
            
            // Format distance (e.g. "124 km")
            if (distMeters > 1000) {
              distStr = '${(distMeters / 1000).toStringAsFixed(0)} km';
            } else {
              distStr = '$distMeters m';
            }
            
            // Format time (e.g. "2h 45m" or "45m")
            final hours = timeSeconds ~/ 3600;
            final minutes = (timeSeconds % 3600) ~/ 60;
            if (hours > 0) {
              timeStr = '${hours}h ${minutes}m';
            } else {
              timeStr = '${minutes}m';
            }

            final route = routeData['routes'][0];
            _routePolyline = route['overview_polyline'] ?? route['geometry'];
          }
        } catch (e) {
          debugPrint('[CreateGroup] Directions fetch failed: $e');
        }

        if (mounted) {
          setState(() {
            _originLatLng = LatLng(origin.lat!, origin.lng!);
            _destLatLng = LatLng(destination.lat!, destination.lng!);
            _originLabel = oLabel;
            _destLabel = dLabel;
            _routeDistance = distStr;
            _routeTime = timeStr;
          });
        }
      }
    } catch (e) {
      debugPrint('[CreateGroup] Preview geocode error: $e');
    } finally {
      if (mounted) setState(() { _isLoadingRoute = false; });
    }
  }

  Future<void> _handleFinalSubmit() async {
    if (_fromController.text.trim().isEmpty || _toController.text.trim().isEmpty) {
      _showError('Please set both origin and destination');
      return;
    }

    setState(() => _isGeocoding = true);
    try {
      if (mounted) _mapsService.setToken(context.read<AuthProvider>().token ?? '');

      final origin = await _resolveLocation(_fromController.text.trim());
      final destination = await _resolveLocation(_toController.text.trim());

      if (mounted) setState(() => _isGeocoding = false);

      if (origin.lat != null && origin.lng != null && destination.lat != null && destination.lng != null && mounted) {
        String destName = destination.name;
        if (destName.contains(',')) {
          destName = destName.split(',').first.trim();
        }
        final tripName = _tripNameController.text.trim().isNotEmpty 
            ? _tripNameController.text.trim() 
            : "Trip to $destName";

        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => RouteStyleScreen(
            tripName: tripName,
            transportMode: _selectedMode,
            travelType: _travelType,
            origin: origin,
            destination: destination,
          ),
        ));
      } else {
        _showError('Could not find precise coordinates. Try being more specific.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGeocoding = false);
        _showError('Failed to geocode locations: $e');
      }
    }
  }

  Future<PlaceModel> _resolveLocation(String query) async {
    // 1. Try to parse as raw coordinates (e.g., "13.0845, 77.4865")
    final parts = query.split(',');
    if (parts.length == 2) {
      final lat = double.tryParse(parts[0].trim());
      final lng = double.tryParse(parts[1].trim());
      if (lat != null && lng != null) {
        return PlaceModel(lat: lat, lng: lng, name: 'Current Location', address: query);
      }
    }

    // 2. Otherwise hit the geocoder
    try {
      final res = await _mapsService.geocode(query);
      if (res['geocodingResults']?.isNotEmpty == true) {
        final loc = res['geocodingResults'][0]['geometry']['location'];
        final addr = res['geocodingResults'][0]['formatted_address'];
        return PlaceModel(
          lat: (loc['lat'] as num?)?.toDouble(),
          lng: (loc['lng'] as num?)?.toDouble(),
          name: query,
          address: addr ?? query,
        );
      }
    } catch (e) {
      debugPrint('[CreateGroup] Resolve location error: $e');
    }
    return PlaceModel(name: query, address: query);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.of(context).accentDanger),
    );
  }

  Future<void> _useCurrentLocation(TextEditingController controller) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fetching live location...'), duration: Duration(seconds: 2)),
    );

    final locService = LocationService();
    Position? pos;
    try {
      pos = await locService.getCurrentPosition().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[CreateGroup] GPS error: $e');
    }

    if (pos == null) {
      debugPrint('[CreateGroup] Using fallback mock location');
      controller.text = 'Bengaluru, Karnataka';
      _geocodeAndPreview();
      return;
    }

    try {
      if (mounted) _mapsService.setToken(context.read<AuthProvider>().token ?? '');
      final res = await _mapsService.reverseGeocode(lat: pos.latitude, lng: pos.longitude).timeout(const Duration(seconds: 8));
      if (res['geocodingResults']?.isNotEmpty == true) {
        controller.text = res['geocodingResults'][0]['formatted_address'];
        _geocodeAndPreview();
        return;
      }
    } catch (e) {
      debugPrint('[CreateGroup] Reverse geocode error: $e');
    }

    controller.text = '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
    _geocodeAndPreview();
  }

  // ===================== BUILD =====================

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.surfaceColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Image.asset(
          'assets/logo_transparent.png',
          height: 32,
          fit: BoxFit.contain,
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTitleSection(colors),
              const SizedBox(height: 20),
              _buildStepper(colors),
              const SizedBox(height: 28),
              _buildTripTitleInput(colors),
              const SizedBox(height: 16),
              _buildLocationsCard(colors),
              const SizedBox(height: 28),
              _buildTravelModeSection(colors),
              const SizedBox(height: 28),
              _buildWhoIsTravellingSection(colors),
              const SizedBox(height: 28),
              _buildRoutePreviewSection(colors),
              const SizedBox(height: 28),
              _buildContinueButton(colors),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ===================== TITLE =====================

  Widget _buildTitleSection(AppColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Plan your journey',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.terrain_rounded, color: const Color(0xFF2E7D32), size: 30),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Where are you heading next?',
          style: TextStyle(fontSize: 15, color: colors.textSecondary),
        ),
      ],
    );
  }

  // ===================== STEPPER =====================

  Widget _buildStepper(AppColorScheme colors) {
    return Row(
      children: [
        _buildStepIndicator(1, 'Route', true, colors),
        _buildStepDivider(colors),
        _buildStepIndicator(2, 'Style', false, colors),
        _buildStepDivider(colors),
        _buildStepIndicator(3, 'People', false, colors),
        _buildStepDivider(colors),
        _buildStepIndicator(4, 'Ready', false, colors),
      ],
    );
  }

  Widget _buildStepIndicator(int number, String label, bool isActive, AppColorScheme colors) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? colors.accentPrimary : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive ? colors.accentPrimary : colors.textTertiary,
              width: 1.5,
            ),
          ),
          child: Text(
            number.toString(),
            style: TextStyle(
              color: isActive ? Colors.white : colors.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: isActive ? colors.textPrimary : colors.textTertiary,
            fontSize: 13,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildStepDivider(AppColorScheme colors) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: CustomPaint(
          size: const Size(double.infinity, 1),
          painter: _DashedLinePainter(color: colors.borderColor),
        ),
      ),
    );
  }

  // ===================== LOCATIONS CARD =====================

  Widget _buildTripTitleInput(AppColorScheme colors) {
    return TextField(
      controller: _tripNameController,
      style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: 'Trip Title (Optional)',
        labelStyle: TextStyle(color: colors.textSecondary, fontSize: 13),
        hintText: 'e.g. Weekend Getaway',
        hintStyle: TextStyle(color: colors.textTertiary, fontWeight: FontWeight.normal, fontSize: 14),
        prefixIcon: Icon(Icons.edit_note_rounded, color: colors.accentPrimary, size: 22),
        filled: true,
        fillColor: colors.cardColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.borderColor)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.borderColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.accentPrimary, width: 2)),
      ),
    );
  }

  Widget _buildLocationsCard(AppColorScheme colors) {
    return Column(
      children: [
        _buildLocationInput(
          controller: _fromController,
          focusNode: _fromFocus,
          label: 'Starting point',
          hint: 'e.g. Bengaluru, Karnataka',
          prefixIcon: Icons.my_location_rounded,
          prefixColor: Colors.blue,
          colors: colors,
          trailing: IconButton(
            icon: Icon(Icons.gps_fixed, color: colors.textSecondary, size: 20),
            onPressed: () => _useCurrentLocation(_fromController),
          ),
        ),
        const SizedBox(height: 12),
        _buildLocationInput(
          controller: _toController,
          focusNode: _toFocus,
          label: 'Destination',
          hint: 'e.g. Udupi, Karnataka',
          prefixIcon: Icons.location_on_rounded,
          prefixColor: Colors.red,
          colors: colors,
          trailing: IconButton(
            icon: Icon(Icons.swap_vert_rounded, color: colors.textSecondary, size: 22),
            onPressed: () {
              final temp = _fromController.text;
              _fromController.text = _toController.text;
              _toController.text = temp;
              _geocodeAndPreview();
            },
          ),
        ),
        if (_originLatLng != null && _destLatLng != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colors.primaryBackground.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.borderColor),
            ),
            child: _isLoadingRoute
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Row(
                        children: [
                          Icon(_selectedMode == 'driving' ? Icons.directions_car_rounded
                              : _selectedMode == 'two_wheeler' ? Icons.two_wheeler_rounded
                              : Icons.directions_walk_rounded, color: colors.accentPrimary, size: 20),
                          const SizedBox(width: 8),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonLine(width: 60, height: 16),
                              SizedBox(height: 4),
                              SkeletonLine(width: 40, height: 10),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(Icons.schedule_rounded, color: colors.accentPrimary, size: 20),
                          const SizedBox(width: 8),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonLine(width: 60, height: 16),
                              SizedBox(height: 4),
                              SkeletonLine(width: 40, height: 10),
                            ],
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildRouteStatItem(
                        _selectedMode == 'driving' ? Icons.directions_car_rounded
                        : _selectedMode == 'two_wheeler' ? Icons.two_wheeler_rounded
                        : Icons.directions_walk_rounded, 
                        _routeDistance ?? '—', 'Distance', colors
                      ),
                      _buildRouteStatItem(Icons.schedule_rounded, _routeTime ?? '—', 'Est. Time', colors),
                    ],
                  ),
          ),
        ],
      ],
    );
  }

  Widget _buildRouteStatItem(IconData icon, String value, String label, AppColorScheme colors) {
    return Row(
      children: [
        Icon(icon, color: colors.accentPrimary, size: 20),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
            Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 11)),
          ],
        ),
      ],
    );
  }

  Widget _buildLocationInput({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required IconData prefixIcon,
    required Color prefixColor,
    required AppColorScheme colors,
    required Widget? trailing,
  }) {
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      optionsBuilder: (TextEditingValue textEditingValue) {
        return _getPlaceSuggestions(textEditingValue.text);
      },
      onSelected: (String selection) {
        _geocodeAndPreview();
      },
      fieldViewBuilder: (context, textController, currentFocusNode, onFieldSubmitted) {
        return TextField(
          controller: textController,
          focusNode: currentFocusNode,
          style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(color: colors.textSecondary, fontSize: 13),
            hintText: hint,
            hintStyle: TextStyle(color: colors.textTertiary, fontWeight: FontWeight.normal, fontSize: 14),
            prefixIcon: Icon(prefixIcon, color: prefixColor, size: 22),
            suffixIcon: trailing,
            filled: true,
            fillColor: colors.cardColor,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.borderColor)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.borderColor)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.accentPrimary, width: 2)),
          ),
          onSubmitted: (_) => _geocodeAndPreview(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            color: colors.surfaceColor,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 40, maxHeight: 200),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final String option = options.elementAt(index);
                  return InkWell(
                    onTap: () {
                      onSelected(option);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Text(option, style: TextStyle(color: colors.textPrimary, fontSize: 14)),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // ===================== TRAVEL MODE =====================

  Widget _buildTravelModeSection(AppColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Travel by', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Which mode is right for you?', style: TextStyle(color: colors.accentPrimary, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 14),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildTravelModeCard('driving', 'Car', 'Fastest routes via major roads.', Icons.directions_car_filled_rounded, colors)),
              const SizedBox(width: 10),
              Expanded(child: _buildTravelModeCard('two_wheeler', 'Bike', 'Scenic & bike-friendly roads.', Icons.two_wheeler_rounded, colors)),
              const SizedBox(width: 10),
              Expanded(child: _buildTravelModeCard('walking', 'Walk', 'Pedestrian paths & walkable routes.', Icons.directions_walk_rounded, colors)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTravelModeCard(String modeValue, String title, String subtitle, IconData icon, AppColorScheme colors) {
    final isSelected = _selectedMode == modeValue;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedMode = modeValue);
        _geocodeAndPreview();
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? colors.accentPrimary.withValues(alpha: 0.1) : colors.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? colors.accentPrimary : colors.borderColor,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Icon(icon, size: 22, color: isSelected ? colors.accentPrimary : colors.textSecondary),
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? colors.accentPrimary : colors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: colors.textSecondary, fontSize: 11, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== WHO'S TRAVELLING =====================

  Widget _buildWhoIsTravellingSection(AppColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Who's travelling?", style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _buildTravelTypeCard('solo', 'Solo', '', Icons.person_outline_rounded, colors)),
            const SizedBox(width: 12),
            Expanded(child: _buildTravelTypeCard('group', 'Group', 'Invite friends after creating the trip.', Icons.people_outline_rounded, colors)),
          ],
        ),
      ],
    );
  }

  Widget _buildTravelTypeCard(String typeValue, String title, String subtitle, IconData icon, AppColorScheme colors) {
    final isSelected = _travelType == typeValue;
    return GestureDetector(
      onTap: () => setState(() => _travelType = typeValue),
      child: Container(
        height: 80,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? colors.accentPrimary.withValues(alpha: 0.1) : colors.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? colors.accentPrimary : colors.borderColor,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: Icon(icon, size: 24, color: isSelected ? colors.accentPrimary : colors.textSecondary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? colors.accentPrimary : colors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(subtitle, style: TextStyle(color: colors.textSecondary, fontSize: 10, height: 1.2)),
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== ROUTE PREVIEW (LIVE) =====================

  Widget _buildRoutePreviewSection(AppColorScheme colors) {
    final hasRoute = _originLatLng != null && _destLatLng != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Route preview', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
            if (hasRoute)
              GestureDetector(
                onTap: _showFullScreenMap,
                child: Row(
                  children: [
                    Text('View on map', style: TextStyle(color: colors.accentPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 4),
                    Icon(Icons.open_in_new_rounded, color: colors.accentPrimary, size: 14),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: colors.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.borderColor),
          ),
          child: hasRoute 
              ? (_isLoadingRoute ? const SkeletonBox(height: 200, borderRadius: 16) : _buildLiveMapPreview(colors))
              : _buildEmptyMapPlaceholder(colors),
        ),
      ],
    );
  }

  Widget _buildLiveMapPreview(AppColorScheme colors) {
    final centerLat = (_originLatLng!.latitude + _destLatLng!.latitude) / 2;
    final centerLng = (_originLatLng!.longitude + _destLatLng!.longitude) / 2;

    // Calculate zoom based on distance
    final latDiff = (_originLatLng!.latitude - _destLatLng!.latitude).abs();
    final lngDiff = (_originLatLng!.longitude - _destLatLng!.longitude).abs();
    final maxDiff = max(latDiff, lngDiff);
    double zoom = 7.5;
    if (maxDiff > 5) {
      zoom = 5.5;
    } else if (maxDiff > 3) {
      zoom = 6.5;
    } else if (maxDiff > 1) {
      zoom = 7.5;
    } else {
      zoom = 9.0;
    }

    return Column(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
          child: SizedBox(
            height: 160,
            child: IgnorePointer(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(centerLat, centerLng),
                  initialZoom: zoom,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.rouniity.app',
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePolyline != null 
                            ? decodePolyline(_routePolyline!)
                            : [_originLatLng!, LatLng(centerLat, centerLng), _destLatLng!],
                        color: const Color(0xFF2E7D32),
                        strokeWidth: 3.5,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _originLatLng!,
                        width: 90,
                        height: 28,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B3D2F),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _originLabel ?? 'Origin',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      Marker(
                        point: _destLatLng!,
                        width: 90,
                        height: 28,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B3D2F),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _destLabel ?? 'Destination',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_routeDistance != null || _routeTime != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildPreviewInfoItem(_routeDistance ?? '—', 'Distance', Icons.directions_car_rounded, colors),
                _buildPreviewInfoItem(_routeTime ?? '—', 'Est. time', Icons.schedule_rounded, colors),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyMapPlaceholder(AppColorScheme colors) {
    return Container(
      height: 140,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.map_outlined, color: colors.textTertiary, size: 40),
          const SizedBox(height: 10),
          Text(
            'Enter both locations to see\na live route preview',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textTertiary, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewInfoItem(String value, String label, IconData icon, AppColorScheme colors) {
    return Row(
      children: [
        Icon(icon, color: colors.textSecondary, size: 18),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
            Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 10)),
          ],
        ),
      ],
    );
  }

  // ===================== CONTINUE BUTTON =====================

  Widget _buildContinueButton(AppColorScheme colors) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _isGeocoding ? null : _handleFinalSubmit,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1B3D2F),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF1B3D2F).withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
          elevation: 0,
        ),
        child: _isGeocoding
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Choose Route Style', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 20),
                ],
              ),
      ),
    );
  }

  void _showFullScreenMap() {
    if (_originLatLng == null || _destLatLng == null) return;
    
    final mapController = MapController();

    showDialog(
      context: context,
      builder: (context) {
        return Dialog.fullscreen(
          child: Stack(
            children: [
              FlutterMap(
                mapController: mapController,
                options: MapOptions(
                  initialCenter: LatLng(
                    (_originLatLng!.latitude + _destLatLng!.latitude) / 2,
                    (_originLatLng!.longitude + _destLatLng!.longitude) / 2,
                  ),
                  initialZoom: 6,
                  onMapReady: () {
                    final points = _routePolyline != null 
                        ? decodePolyline(_routePolyline!)
                        : [_originLatLng!, _destLatLng!];
                    final bounds = LatLngBounds.fromPoints(points);
                    mapController.fitCamera(
                      CameraFit.bounds(
                        bounds: bounds,
                        padding: const EdgeInsets.all(50),
                      ),
                    );
                  }
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.rouniity.app',
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePolyline != null 
                            ? decodePolyline(_routePolyline!)
                            : [_originLatLng!, _destLatLng!],
                        color: const Color(0xFF2E7D32),
                        strokeWidth: 4,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _originLatLng!,
                        child: const Icon(Icons.location_on, color: Colors.green, size: 40),
                      ),
                      Marker(
                        point: _destLatLng!,
                        child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                      ),
                    ],
                  ),
                ],
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.close, color: Colors.black),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ===================== DASHED LINE PAINTER =====================

class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const dashWidth = 4.0;
    const dashSpace = 3.0;

    if (size.width >= size.height) {
      // Horizontal dashes
      double startX = 0;
      while (startX < size.width) {
        canvas.drawLine(
          Offset(startX, size.height / 2),
          Offset(min(startX + dashWidth, size.width), size.height / 2),
          paint,
        );
        startX += dashWidth + dashSpace;
      }
    } else {
      // Vertical dashes
      double startY = 0;
      while (startY < size.height) {
        canvas.drawLine(
          Offset(size.width / 2, startY),
          Offset(size.width / 2, min(startY + dashWidth, size.height)),
          paint,
        );
        startY += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
