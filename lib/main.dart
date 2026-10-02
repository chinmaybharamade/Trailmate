import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/group_provider.dart';
import 'providers/navigation_provider.dart';

import 'providers/theme_provider.dart';
import 'core/theme.dart';
import 'core/app_colors.dart';
import 'services/ola_tile_proxy.dart';

import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/group/create_group_screen.dart';
import 'screens/group/join_group_screen.dart';
import 'screens/group/group_lobby_screen.dart';
import 'screens/navigation/live_navigation_screen.dart';
import 'screens/settings/feedback_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await OlaTileProxy.start();
  
  await FMTCObjectBoxBackend().initialise();
  await const FMTCStore('mapStore').manage.create();
  
  final themeProvider = ThemeProvider();
  await themeProvider.initialize();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => GroupProvider()),
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
      ],
      child: RoUniityApp(),
    ),
  );
}

class RoUniityApp extends StatelessWidget {
  RoUniityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return AppColors(
          colors: themeProvider.colors,
          child: MaterialApp(
            title: 'RoUniity',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.buildTheme(themeProvider.colors),
            builder: (context, child) {
              return AnimatedTheme(
                data: AppTheme.buildTheme(themeProvider.colors),
                duration: Duration(milliseconds: 400),
                child: child!,
              );
            },
            initialRoute: '/',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(builder: (_) => SplashScreen(), settings: settings);
          case '/login':
            return MaterialPageRoute(builder: (_) => LoginScreen(), settings: settings);
          case '/register':
            final googleData = settings.arguments as Map<String, dynamic>?;
            return MaterialPageRoute(builder: (_) => RegisterScreen(googleData: googleData), settings: settings);
          case '/home':
            return MaterialPageRoute(builder: (_) => HomeScreen(), settings: settings);
          case '/create-group':
            return MaterialPageRoute(builder: (_) => CreateGroupScreen(), settings: settings);
          case '/join-group':
            return MaterialPageRoute(builder: (_) => JoinGroupScreen(), settings: settings);
          case '/group-lobby':
            final groupId = settings.arguments as String;
            return MaterialPageRoute(builder: (_) => GroupLobbyScreen(groupId: groupId), settings: settings);
          case '/live-navigation':
            final groupId = settings.arguments as String;
            return MaterialPageRoute(builder: (_) => LiveNavigationScreen(groupId: groupId), settings: settings);
          case '/feedback':
            return MaterialPageRoute(builder: (_) => FeedbackScreen(), settings: settings);
          default:
            return MaterialPageRoute(
              builder: (_) => Scaffold(
                body: Center(child: Text('Page not found')),
              ),
              settings: settings,
            );
        }
      },
          ),
        );
      },
    );
  }
}
