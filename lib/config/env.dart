import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static const String appBuildVersion = String.fromEnvironment(
    'AHVI_APP_BUILD_VERSION',
    defaultValue: '1.0.0+1',
  );

  /// Developer-only Style diagnostics (AHVI UNDERSTOOD / Source / Request /
  /// CONSTRAINT CHECK). Default OFF. Must NOT rely on kDebugMode — the beta
  /// APK is a debug build, so these are gated by an explicit env flag instead.
  static bool get showStyleDebug {
    try {
      final raw = (dotenv.env['EXPO_PUBLIC_SHOW_STYLE_DEBUG'] ??
              dotenv.env['SHOW_STYLE_DEBUG'] ??
              '')
          .trim()
          .toLowerCase();
      return raw == 'true' || raw == '1' || raw == 'yes' || raw == 'on';
    } catch (_) {
      return false;
    }
  }

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
    debugPrint('AHVI Backend URL: $backendApiUrl');
    debugPrint('AHVI App build version: $appBuildVersion');
  }
}
