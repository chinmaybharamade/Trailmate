import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tutorial_keys.dart';

class TutorialController {
  static Future<bool> hasCompletedTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('has_completed_tutorial') ?? false;
  }

  static Future<void> markTutorialCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_completed_tutorial', true);
  }

  static Future<void> resetTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_completed_tutorial', false);
  }

  // Starts the Home Screen tutorial
  static void startHomeTutorial(BuildContext context) async {
    final hasCompleted = await hasCompletedTutorial();
    if (!hasCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ShowCaseWidget.of(context).startShowCase([
          TutorialKeys.planTripBtn,
          TutorialKeys.joinTripBtn,
        ]);
      });
    }
  }

  // Starts the Create Trip Screen tutorial
  static void startCreateTripTutorial(BuildContext context) async {
    final hasCompleted = await hasCompletedTutorial();
    if (!hasCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ShowCaseWidget.of(context).startShowCase([
          TutorialKeys.searchField,
        ]);
      });
    }
  }

  // Starts the Route Style Screen tutorial
  static void startRouteStyleTutorial(BuildContext context) async {
    final hasCompleted = await hasCompletedTutorial();
    if (!hasCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ShowCaseWidget.of(context).startShowCase([
          TutorialKeys.routeStyles,
          TutorialKeys.createTripBtn,
        ]);
      });
    }
  }

  // Starts the Lobby Screen tutorial
  static void startLobbyTutorial(BuildContext context) async {
    final hasCompleted = await hasCompletedTutorial();
    if (!hasCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ShowCaseWidget.of(context).startShowCase([
          TutorialKeys.partyCode,
          TutorialKeys.groupMembers,
          TutorialKeys.offlineBtn,
          TutorialKeys.startNavBtn,
        ]);
      });
    }
  }

  // Starts the Navigation Screen tutorial
  static void startNavigationTutorial(BuildContext context, {bool isLeader = false}) async {
    final hasCompleted = await hasCompletedTutorial();
    if (!hasCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ShowCaseWidget.of(context).startShowCase([
          TutorialKeys.routeMap,
          TutorialKeys.tbtInstructions,
          TutorialKeys.etaBox,
          TutorialKeys.groupStatus,
          if (isLeader) TutorialKeys.regroupBtn,
          TutorialKeys.mapOrientBtn,
          TutorialKeys.centerMapBtn,
          TutorialKeys.sosBtn,
          TutorialKeys.exitNavBtn,
        ]);
      });
    }
  }

  static Widget buildShowcase({
    required GlobalKey key,
    required String title,
    required String description,
    required Widget child,
    ShapeBorder? shapeBorder,
    VoidCallback? onTargetClick,
    bool? disposeOnTap,
  }) {
    return Showcase(
      key: key,
      title: title,
      description: description,
      disposeOnTap: onTargetClick != null ? disposeOnTap : null,
      onTargetClick: onTargetClick,
      tooltipBackgroundColor: const Color(0xFF1E293B),
      textColor: Colors.white,
      titleTextStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
      descTextStyle: const TextStyle(fontSize: 14, color: Colors.white70),
      overlayColor: Colors.black.withOpacity(0.8),
      overlayOpacity: 0.8,
      targetBorderRadius: BorderRadius.circular(16),
      targetPadding: const EdgeInsets.all(8),
      child: child,
    );
  }
}
