
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../widgets/theme_switcher_sheet.dart';
import '../../widgets/skeleton_loader.dart';
import '../../core/app_colors.dart';
import '../../services/explore_service.dart';
import '../../services/place_image_service.dart';
import 'search_destinations_screen.dart';
import 'destination_details_screen.dart';
import '../../core/tutorial_controller.dart';
import '../../core/tutorial_keys.dart';
import '../../core/legal_docs.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _bottomNavIndex = 0;
  List<TouristPlace> _nearbyPlaces = [];
  bool _isLoadingPlaces = true;

  // Pre-fetched image futures — stored in state so FutureBuilder
  // doesn't recreate them on every widget rebuild.
  static const _trendingNames = ['Manali', 'Goa', 'Jaipur'];
  final Map<String, Future<String>> _trendingImageFutures = {};

  @override
  void initState() {
    super.initState();

    for (final name in _trendingNames) {
      _trendingImageFutures[name] = PlaceImageService.fetchImageUrl(name);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final groupProvider = context.read<GroupProvider>();
      final navProvider = context.read<NavigationProvider>();
      
      groupProvider.setToken(auth.token);
      groupProvider.fetchMyGroups();
      
      if (auth.token != null && auth.currentUser != null) {
        navProvider.initialize(auth.token!, auth.currentUser!.id, auth.currentUser!.name);
      }
      
      _fetchPlaces().then((_) {
        // Start tutorial if first time
        TutorialController.startHomeTutorial(context);
      });
    });
  }

  Future<void> _fetchPlaces() async {
    try {
      final token = context.read<AuthProvider>().token;
      final places = await ExploreService.fetchNearbyPlaces(token: token);
      if (mounted) {
        setState(() {
          _nearbyPlaces = places;
          _isLoadingPlaces = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingPlaces = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.surfaceColor,
      body: SafeArea(
        child: IndexedStack(
          index: _bottomNavIndex,
          children: [
            _buildHomeTab(colors),
            _buildExploreTab(colors),
            _buildTripsTab(colors),
            _buildProfileTab(colors),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(colors),
    );
  }

  Widget _buildHomeTab(AppColorScheme colors) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopHeader(colors),
          _buildGreeting(colors),
          _buildActionCardsRow(colors),
          _buildContinueJourney(colors),
          _buildExploreNearby(colors),
          _buildYourTrips(colors),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildExploreTab(AppColorScheme colors) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: Text(
              'Explore',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: colors.textPrimary),
            ),
          ),
          _buildSearchBar(colors),
          _buildCategories(colors),
          const SizedBox(height: 16),
          _buildTrendingDestinations(colors),
          const SizedBox(height: 16),
          _buildExploreNearby(colors),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildCategories(AppColorScheme colors) {
    final categories = [
      {'name': 'Mountains', 'icon': Icons.terrain_rounded, 'color': Colors.green},
      {'name': 'Beaches', 'icon': Icons.beach_access_rounded, 'color': Colors.blue},
      {'name': 'Heritage', 'icon': Icons.account_balance_rounded, 'color': Colors.orange},
      {'name': 'Forests', 'icon': Icons.park_rounded, 'color': Colors.teal},
      {'name': 'City', 'icon': Icons.location_city_rounded, 'color': Colors.purple},
    ];

    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SearchDestinationsScreen(initialQuery: cat['name'] as String),
              ),
            ),
            child: Container(
              width: 72,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: (cat['color'] as Color).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(cat['icon'] as IconData, color: cat['color'] as Color, size: 28),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    cat['name'] as String,
                    style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTrendingDestinations(AppColorScheme colors) {
    // Trending destination names — images fetched once in initState
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Trending Destinations', 'See all', colors),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _trendingNames.length,
            itemBuilder: (context, index) {
              final name = _trendingNames[index];
              // Use the pre-created future — never recreated on rebuild
              final future = _trendingImageFutures[name]!;
              return Container(
                width: 140,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                child: FutureBuilder<String>(
                  future: future,
                  builder: (context, snapshot) {
                    final isLoading = snapshot.connectionState == ConnectionState.waiting;
                    final imageUrl = snapshot.data ?? '';
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => DestinationDetailsScreen(
                              place: TouristPlace(
                                name: name,
                                lat: 0.0,
                                lon: 0.0,
                                type: 'trending',
                                distanceKm: 0.0,
                                imageUrl: imageUrl,
                              ),
                            ),
                          ),
                        );
                      },
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: _buildNetworkImage(
                                imageUrl: imageUrl,
                                colors: colors,
                                isLoading: isLoading,
                              ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.8),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 16,
                            left: 16,
                            child: Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTripsTab(AppColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Text(
            'My Trips',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colors.textPrimary),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: _buildYourTrips(colors),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileTab(AppColorScheme colors) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final user = auth.currentUser;
        final name = user?.name ?? 'User';
        final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Row(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1A1A1A),
                        border: Border.all(color: colors.accentSecondary, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 32,
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colors.textPrimary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user?.email ?? user?.phone ?? 'Not provided',
                            style: TextStyle(fontSize: 14, color: colors.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: colors.accentSecondary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              user?.title ?? 'Novice Traveler',
                              style: TextStyle(color: colors.accentSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _buildStatCard('${user?.trips ?? 0}', 'Trips', colors),
                    const SizedBox(width: 16),
                    _buildStatCard('${user?.kmTravelled ?? 0}', 'km Travelled', colors),
                    const SizedBox(width: 16),
                    _buildStatCard('${user?.badges ?? 0}', 'Badges', colors),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _buildSettingsList(colors, auth),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String value, String label, AppColorScheme colors) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: colors.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.borderColor.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsList(AppColorScheme colors, AuthProvider auth) {
    return Column(
      children: [
        _buildSettingsItem(Icons.person_outline, 'Account Settings', 'Manage your personal information', colors, onTap: () {
          _showAccountSettings(context, auth, colors);
        }),
        _buildSettingsItem(Icons.notifications_outlined, 'Notifications', 'Stay updated on your trips and activity', colors, onTap: () {
          _showNotificationSettings(context, colors);
        }),
        _buildSettingsItem(Icons.palette_outlined, 'Appearance', 'Choose your theme and display preferences', colors, onTap: () => ThemeSwitcherSheet.show(context)),
        _buildSettingsItem(Icons.shield_outlined, 'Privacy & Security', 'Keep your data safe', colors, onTap: () {
          _showPrivacyPolicy(context, colors);
        }),
        _buildSettingsItem(Icons.help_outline, 'Help & Support', 'Get help, FAQs and contact us', colors, onTap: () {
          _showHelpAndSupport(context, colors);
        }),
        _buildSettingsItem(Icons.feedback_outlined, 'Give Feedback', 'Help us make RoUniity better', colors, onTap: () => Navigator.of(context).pushNamed('/feedback')),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Divider(height: 32),
        ),
        _buildSettingsItem(Icons.logout_rounded, 'Log Out', 'Sign out from your account', colors, color: Colors.redAccent, onTap: () async {
          await auth.logout();
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/');
          }
        }),
      ],
    );
  }

  Widget _buildSettingsItem(IconData icon, String title, String subtitle, AppColorScheme colors, {Color? color, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Material(
        color: const Color(0xFF161A1E),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap ?? () {},
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (color ?? colors.accentPrimary).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color ?? colors.accentPrimary, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: color ?? colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: colors.textTertiary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAccountSettings(BuildContext context, AuthProvider auth, AppColorScheme colors) {
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Account Settings', style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              ListTile(
                leading: Icon(Icons.person, color: colors.accentPrimary),
                title: Text('Name', style: TextStyle(color: colors.textSecondary, fontSize: 14)),
                subtitle: Text(auth.currentUser?.name ?? 'User', style: TextStyle(color: colors.textPrimary, fontSize: 16)),
              ),
              ListTile(
                leading: Icon(Icons.email, color: colors.accentPrimary),
                title: Text('Email', style: TextStyle(color: colors.textSecondary, fontSize: 14)),
                subtitle: Text(auth.currentUser?.email ?? 'Email', style: TextStyle(color: colors.textPrimary, fontSize: 16)),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accentPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNotificationSettings(BuildContext context, AppColorScheme colors) {
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Notifications', style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              SwitchListTile(
                title: Text('Push Notifications', style: TextStyle(color: colors.textPrimary)),
                subtitle: Text('Receive alerts about your trips', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                value: true,
                activeColor: colors.accentPrimary,
                onChanged: (val) {},
              ),
              SwitchListTile(
                title: Text('Email Updates', style: TextStyle(color: colors.textPrimary)),
                subtitle: Text('Get newsletters and offers', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                value: false,
                activeColor: colors.accentPrimary,
                onChanged: (val) {},
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accentPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPrivacyPolicy(BuildContext context, AppColorScheme colors) {
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.cardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Privacy & Security', style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: Text(
                        LegalDocs.termsAndConditions,
                        style: TextStyle(color: colors.textSecondary, fontSize: 14, height: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.accentPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Accept & Close'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showHelpAndSupport(BuildContext context, AppColorScheme colors) {
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Help & Support', style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.email_outlined, color: colors.accentPrimary),
                title: Text('Contact Us', style: TextStyle(color: colors.textPrimary)),
                subtitle: Text('services.rouniity@gmail.com', style: TextStyle(color: colors.accentPrimary)),
                onTap: () {},
              ),
              ListTile(
                leading: Icon(Icons.tour_rounded, color: colors.accentPrimary),
                title: Text('RoUniity Tour', style: TextStyle(color: colors.textPrimary)),
                subtitle: Text('Replay the interactive app tutorial', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await TutorialController.resetTutorial();
                  if (context.mounted) {
                    setState(() {
                      _bottomNavIndex = 0;
                    });
                    Future.delayed(const Duration(milliseconds: 300), () {
                      if (context.mounted) {
                        TutorialController.startHomeTutorial(context);
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(AppColorScheme colors) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final name = auth.currentUser?.name ?? 'Dev';
        final initial = name.isNotEmpty ? name[0].toUpperCase() : 'D';

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      children: [
                        Image.asset(
                          'assets/logo_transparent.png',
                          height: 40,
                          fit: BoxFit.contain,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Stack(
                    children: [
                      IconButton(
                        icon: Icon(Icons.notifications_none_rounded, color: colors.textPrimary, size: 28),
                        onPressed: () {},
                      ),
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: colors.accentSecondary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => ThemeSwitcherSheet.show(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1A1A1A), 
                        border: Border.all(color: colors.accentSecondary, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGreeting(AppColorScheme colors) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final name = auth.currentUser?.name ?? 'Traveler';
        
        final hour = DateTime.now().hour;
        String greeting = 'Good evening';
        if (hour < 12) {
          greeting = 'Good morning';
        } else if (hour < 17) {
          greeting = 'Good afternoon';
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      '$greeting, $name!',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('👋', style: TextStyle(fontSize: 24)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Where are we exploring today?',
                style: TextStyle(
                  fontSize: 15,
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchBar(AppColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SearchDestinationsScreen()),
        ),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: colors.cardColor,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: colors.borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: colors.accentSecondary, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Search destinations, places or trips...',
                  style: TextStyle(
                    color: colors.textSecondary.withValues(alpha: 0.7),
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 24,
                color: colors.borderColor,
                margin: const EdgeInsets.symmetric(horizontal: 12),
              ),
              Icon(Icons.tune_rounded, color: colors.accentSecondary, size: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCardsRow(AppColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TutorialController.buildShowcase(
              key: TutorialKeys.planTripBtn,
              title: 'Plan a Trip',
              description: 'Plan your journey — Start by choosing where you want to go',
              disposeOnTap: true,
              onTargetClick: () {
                Navigator.of(context).pushNamed('/create-group');
              },
              child: GestureDetector(
                onTap: () => Navigator.of(context).pushNamed('/create-group'),
              child: Container(
                height: 140,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF558D46), Color(0xFF2E5E24)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              const Icon(Icons.route_outlined, color: Colors.black, size: 24),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.add_circle, color: Color(0xFF2E5E24), size: 18),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          'Plan a Trip',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Plan, invite friends\nand create memories',
                          style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.2),
                        ),
                      ],
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                      ),
                    )
                  ],
                ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
          child: TutorialController.buildShowcase(
            key: TutorialKeys.joinTripBtn,
            title: 'Join a Trip',
            description: 'Enter a party code or scan a QR code to join an existing group',
            child: GestureDetector(
              onTap: () => Navigator.of(context).pushNamed('/join-group'),
              child: Container(
                height: 140,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: const Color(0xFF101418),
                ),
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.people_alt_rounded, color: Colors.black, size: 24),
                        ),
                        const Spacer(),
                        const Text(
                          'Join a Trip',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Enter code or scan\nan invite',
                          style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.2),
                        ),
                      ],
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                      ),
                    )
                  ],
                ),
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String action, AppColorScheme colors, {VoidCallback? onActionTap}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          InkWell(
            onTap: onActionTap,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  Text(
                    action,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.accentSecondary,
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: colors.accentSecondary, size: 20),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildContinueJourney(AppColorScheme colors) {
    return Consumer<GroupProvider>(
      builder: (context, groupProvider, _) {
        final currentUserId = context.read<AuthProvider>().currentUser?.id ?? '';
        final activeGroups = groupProvider.myGroups.where((g) {
          final isParticipant = g.isLeader(currentUserId) || g.isMember(currentUserId);
          return g.status != 'completed' && isParticipant;
        }).toList();
        
        if (activeGroups.isEmpty) {
          return const SizedBox.shrink(); // Hide section if no active trips
        }
        
        final group = activeGroups.first;
        final hasRoute = group.route.hasRoute;
        final originName = hasRoute ? group.route.origin.name : 'Unknown';
        final destName = hasRoute ? group.route.destination.name : 'Unknown';
        final startDate = group.createdAt != null ? DateFormat('MMM d, yyyy').format(group.createdAt!) : 'Upcoming';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Continue Your Journey', 'View all', colors, onActionTap: () {
              setState(() {
                _bottomNavIndex = 2;
              });
            }),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GestureDetector(
                onTap: () {
                  groupProvider.setCurrentGroup(group);
                  Navigator.of(context).pushNamed('/group-lobby', arguments: group.id);
                },
                child: SizedBox(
                  height: 180,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: _buildNetworkImage(
                            imageUrl: 'https://images.unsplash.com/photo-1469854523086-cc02fe5d8800?q=80&w=640&auto=format&fit=crop', // Generic roadtrip image
                            colors: colors,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          color: Colors.black.withValues(alpha: 0.4),
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: colors.accentSecondary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                group.status.toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        hasRoute ? '$originName \u2192 $destName' : group.name,
                                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          const Icon(Icons.people_outline_rounded, color: Colors.white70, size: 14),
                                          Text('${group.members.length} travelers', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                          const Text('•', style: TextStyle(color: Colors.white70)),
                                          const Icon(Icons.calendar_today_outlined, color: Colors.white70, size: 14),
                                          Text(startDate, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          const Icon(Icons.directions_car_outlined, color: Colors.white70, size: 14),
                                          Text(group.route.distanceText, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                          const Text('•', style: TextStyle(color: Colors.white70)),
                                          const Icon(Icons.schedule_rounded, color: Colors.white70, size: 14),
                                          Text(group.route.durationText, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    groupProvider.setCurrentGroup(group);
                                    Navigator.of(context).pushNamed('/group-lobby', arguments: group.id);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          'Continue',
                                          style: TextStyle(
                                            color: colors.accentSecondaryDark,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(Icons.chevron_right_rounded, color: colors.accentSecondaryDark, size: 18),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildExploreNearby(AppColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Explore Nearby', 'See all', colors, onActionTap: () {
          setState(() {
            _bottomNavIndex = 1; // Explore tab
          });
        }),
        SizedBox(
          height: 140,
          child: _isLoadingPlaces 
              ? ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: const [
                    SkeletonNearbyCard(),
                    SkeletonNearbyCard(),
                    SkeletonNearbyCard(),
                  ],
                )
              : _nearbyPlaces.isEmpty 
                  ? Center(child: Text('No places found nearby.', style: TextStyle(color: colors.textSecondary)))
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _nearbyPlaces.length,
                      itemBuilder: (context, index) {
                        final place = _nearbyPlaces[index];
                        return GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => DestinationDetailsScreen(place: place),
                            ),
                          ),
                          child: Container(
                            width: 120,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: _buildNetworkImage(
                                    imageUrl: place.imageUrl,
                                    colors: colors,
                                  ),
                                ),
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.1),
                                      Colors.black.withValues(alpha: 0.8),
                                    ],
                                  ),
                                ),
                                padding: const EdgeInsets.all(12),
                                child: Stack(
                                  children: [
                                    Positioned(
                                      top: 0,
                                      right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.location_on, color: Colors.black, size: 14),
                                      ),
                                    ),
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          place.name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(Icons.location_on_outlined, color: colors.accentSecondary, size: 12),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${place.distanceKm.toStringAsFixed(1)} km',
                                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
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

  Widget _buildYourTrips(AppColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Your Trips', 'View all', colors, onActionTap: () {
          setState(() {
            _bottomNavIndex = 2; // Trips tab
          });
        }),
        Consumer<GroupProvider>(
          builder: (context, groupProvider, _) {
            if (groupProvider.isLoading) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: const [
                    SkeletonTripCard(),
                    SkeletonTripCard(),
                    SkeletonTripCard(),
                  ],
                ),
              );
            }

            final currentUserId = context.read<AuthProvider>().currentUser?.id ?? '';
            final userGroups = groupProvider.myGroups.where((g) {
              return g.isLeader(currentUserId) || g.isMember(currentUserId);
            }).toList();

            if (userGroups.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'No active trips yet. Start planning one above!',
                  style: TextStyle(color: colors.textSecondary),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: userGroups.length,
              itemBuilder: (context, index) {
                final group = userGroups[index];
                return _buildTripCard(group, colors, index);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildTripCard(GroupModel group, AppColorScheme colors, int index) {
    // Use the group's destination name and coordinates to fetch its real photo
    final dest = group.route.destination;
    final destinationName = dest.name.isNotEmpty ? dest.name : group.name;
    final destLat = dest.lat;
    final destLon = dest.lng;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.borderColor.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: InkWell(
        onTap: () {
          context.read<GroupProvider>().setCurrentGroup(group);
          Navigator.of(context).pushNamed('/group-lobby', arguments: group.id);
        },
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: FutureBuilder<String>(
                future: PlaceImageService.fetchImageUrl(
                  destinationName,
                  lat: destLat,
                  lon: destLon,
                ),
                builder: (context, snapshot) {
                  final isLoading = snapshot.connectionState == ConnectionState.waiting;
                  final imageUrl = snapshot.data ?? '';
                  return Stack(
                    children: [
                      _buildNetworkImage(
                        imageUrl: imageUrl,
                        width: 72,
                        height: 72,
                        colors: colors,
                        isLoading: isLoading,
                      ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: colors.accentSecondary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${group.members.length} members',
                        style: TextStyle(color: colors.textSecondary, fontSize: 12),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text('•', style: TextStyle(color: colors.textSecondary)),
                      ),
                      Expanded(
                        child: Text(
                          group.createdAt != null
                              ? 'Created ${group.createdAt!.day}/${group.createdAt!.month}/${group.createdAt!.year}'
                              : 'Starts soon',
                          style: TextStyle(color: colors.textSecondary, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.directions_bike_rounded, color: colors.textTertiary, size: 14),
                      const SizedBox(width: 4),
                      Text(group.route.distanceText, style: TextStyle(color: colors.textTertiary, fontSize: 12)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text('•', style: TextStyle(color: colors.textTertiary)),
                      ),
                      Icon(Icons.schedule_rounded, color: colors.textTertiary, size: 14),
                      const SizedBox(width: 4),
                      Text(group.route.durationText, style: TextStyle(color: colors.textTertiary, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.accentSecondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.arrow_forward_rounded, color: colors.accentSecondary, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkImage({
    required String imageUrl,
    required AppColorScheme colors,
    double? width,
    double? height,
    bool isLoading = false,
  }) {
    // Show skeleton shimmer when explicitly loading
    if (isLoading) {
      return SkeletonBox(
        width: width,
        height: height,
        borderRadius: 12,
      );
    }

    // Show fallback icon if loaded but URL is empty (not found/timeout)
    if (imageUrl.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: colors.borderColor.withValues(alpha: 0.3),
        child: Center(
          child: Icon(
            Icons.landscape,
            color: colors.textTertiary,
            size: 32,
          ),
        ),
      );
    }

    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return SkeletonBox(
          width: width,
          height: height,
          borderRadius: 12,
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: width,
          height: height,
          color: colors.borderColor.withValues(alpha: 0.3),
          child: Icon(Icons.image_not_supported_outlined,
              color: colors.textTertiary),
        );
      },
    );
  }

  Widget _buildBottomNav(AppColorScheme colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceColor,
        border: Border(top: BorderSide(color: colors.borderColor, width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: _bottomNavIndex,
        onTap: (index) {
          setState(() {
            _bottomNavIndex = index;
          });
        },
        backgroundColor: Colors.transparent,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: colors.accentSecondary,
        unselectedItemColor: colors.textTertiary,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_filled),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            label: 'Explore',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.luggage_outlined),
            label: 'Trips',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
