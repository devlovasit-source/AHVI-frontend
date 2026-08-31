import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static const String frontendSha = String.fromEnvironment(
    'AHVI_FRONTEND_SHA',
    defaultValue: String.fromEnvironment('AHVI_GIT_SHA', defaultValue: 'unknown'),
  );

  static const String build = String.fromEnvironment(
    'AHVI_BUILD',
    defaultValue: 'dev_0',
  );

  // Keep the existing names used by style diagnostics while sourcing the
  // values from the release provenance contract above.
  static const String gitSha = frontendSha;
  static const String appBuildVersion = build;

  static String get runtimeProvenanceLog =>
      'frontend_sha=$frontendSha build=$build';

  static Map<String, String> get runtimeProvenance => {
    'frontend_sha': frontendSha,
    'build': build,
  };

  static const String buildMode = bool.fromEnvironment('dart.vm.product')
      ? 'release'
      : bool.fromEnvironment('dart.vm.profile')
      ? 'profile'
      : 'debug';
  static const String canonicalRendererVersion = 'editorial_board_canonical_v1';

  static String get appwriteEndpoint =>
      dotenv.env['EXPO_PUBLIC_APPWRITE_ENDPOINT'] ?? '';
  static String get appwriteProjectId =>
      dotenv.env['EXPO_PUBLIC_APPWRITE_PROJECT_ID'] ?? '';
  static String get appwriteDatabaseId =>
      dotenv.env['EXPO_PUBLIC_APPWRITE_DATABASE_ID'] ?? '';

  static String get outfitsCollection =>
      dotenv.env['EXPO_PUBLIC_APPWRITE_COLLECTION_OUTFITS'] ?? '';
  static String get usersCollection =>
      dotenv.env['EXPO_PUBLIC_APPWRITE_COLLECTION_USERS'] ?? '';
  static String get plansCollection => dotenv.env['PLANS_COLLECTION_ID'] ?? '';
  static String get savedBoardsCollection =>
      dotenv.env['EXPO_PUBLIC_APPWRITE_COLLECTION_SAVED_BOARDS'] ?? '';
  static String get skincareCollection =>
      dotenv.env['EXPO_PUBLIC_APPWRITE_COLLECTION_SKINCARE'] ?? '';
  static String get workoutOutfitsCollection =>
      dotenv.env['EXPO_PUBLIC_APPWRITE_COLLECTION_WORKOUT_OUTFITS'] ?? '';
  static String get billsCollection =>
      dotenv.env['EXPO_PUBLIC_APPWRITE_COLLECTION_BILLS'] ?? '';
  static String get couponsCollection =>
      dotenv.env['EXPO_PUBLIC_APPWRITE_COLLECTION_COUPONS'] ?? '';
  static String get medsCollection =>
      dotenv.env['EXPO_PUBLIC_APPWRITE_COLLECTION_MEDS'] ?? '';
  static String get medLogsCollection =>
      dotenv.env['EXPO_PUBLIC_APPWRITE_COLLECTION_MED_LOGS'] ?? '';
  static String get lifeGoalsCollection =>
      dotenv.env['EXPO_PUBLIC_APPWRITE_COLLECTION_LIFE_GOALS'] ?? '';
  static String get backendApiUrl =>
      dotenv.env['EXPO_PUBLIC_BACKEND_API_URL'] ??
      dotenv.env['BACKEND_URL'] ??
      '';
  static String get mealPlansCollection =>
      dotenv.env['EXPO_PUBLIC_APPWRITE_COLLECTION_MEAL_PLANS'] ?? '';

  static Map<String, String> get requiredConfig => {
    'EXPO_PUBLIC_APPWRITE_ENDPOINT': appwriteEndpoint,
    'EXPO_PUBLIC_APPWRITE_PROJECT_ID': appwriteProjectId,
    'EXPO_PUBLIC_APPWRITE_DATABASE_ID': appwriteDatabaseId,
    'EXPO_PUBLIC_APPWRITE_COLLECTION_OUTFITS': outfitsCollection,
    'EXPO_PUBLIC_APPWRITE_COLLECTION_USERS': usersCollection,
    'EXPO_PUBLIC_APPWRITE_COLLECTION_SAVED_BOARDS': savedBoardsCollection,
    'EXPO_PUBLIC_APPWRITE_COLLECTION_SKINCARE': skincareCollection,
    'EXPO_PUBLIC_APPWRITE_COLLECTION_WORKOUT_OUTFITS': workoutOutfitsCollection,
    'EXPO_PUBLIC_APPWRITE_COLLECTION_BILLS': billsCollection,
    'EXPO_PUBLIC_APPWRITE_COLLECTION_COUPONS': couponsCollection,
    'EXPO_PUBLIC_APPWRITE_COLLECTION_MEDS': medsCollection,
    'EXPO_PUBLIC_APPWRITE_COLLECTION_MED_LOGS': medLogsCollection,
    'EXPO_PUBLIC_APPWRITE_COLLECTION_MEAL_PLANS': mealPlansCollection,
    'EXPO_PUBLIC_APPWRITE_COLLECTION_LIFE_GOALS': lifeGoalsCollection,
    'PLANS_COLLECTION_ID': plansCollection,
    'EXPO_PUBLIC_BACKEND_API_URL': backendApiUrl,
  };

  static List<String> get missingRequiredKeys => requiredConfig.entries
      .where((entry) => entry.value.trim().isEmpty)
      .map((entry) => entry.key)
      .toList(growable: false);

  static bool get isConfigured => missingRequiredKeys.isEmpty;

  static void debugPrintMissingConfig() {
    final missing = missingRequiredKeys;
    if (missing.isEmpty) return;
    debugPrint('AHVI config missing: ${missing.join(', ')}');
  }

  static void debugPrintRuntimeTarget() {
    debugPrint('AHVI backend configured=$isConfigured');
  }

  static void debugPrintBuildProvenance() {
    debugPrint(
      'AHVI_BUILD_PROVENANCE '
      '$runtimeProvenanceLog '
      'build_mode=$buildMode '
      'app_version=$appBuildVersion '
      'canonical_renderer=$canonicalRendererVersion',
    );
  }
}
