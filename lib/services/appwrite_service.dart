import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:appwrite/enums.dart';
import 'package:myapp/config/env.dart';
import 'package:myapp/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppwriteService extends ChangeNotifier {
  static final AppwriteService _shared = AppwriteService._internal();

  factory AppwriteService() => _shared;

  late Client client;
  late Account account;
  late Databases databases;
  late Avatars avatars;

  // Cached user — avoid repeated network calls
  User? _cachedUser;
  Map<String, dynamic>? _cachedUserProfileData;

  Map<String, dynamic>? get cachedUserProfileData => _cachedUserProfileData;

  /// Synchronous getter for the cached user ID.
  /// Returns null if the user has not been fetched yet — call
  /// [getCurrentUser] or [cacheCurrentUser] first (both auth paths already do this).
  String? get currentUserId => _cachedUser?.$id;

  // Wardrobe TTL cache — cuts redundant listDocuments calls from planner pages.
  List<Map<String, dynamic>>? _wardrobeCache;
  DateTime? _wardrobeCacheAt;
  Future<List<Map<String, dynamic>>>? _wardrobeInflight;
  static const Duration _wardrobeTtl = Duration(seconds: 60);

  // Optional write-through to offline cache.
  void Function(List<Map<String, dynamic>>)? _onWardrobeFetched;
  void Function(String occasion, List<Document>)? _onSavedBoardsFetched;

  void attachOfflineWriteThrough({
    void Function(List<Map<String, dynamic>>)? onWardrobe,
    void Function(String occasion, List<Document>)? onSavedBoards,
  }) {
    _onWardrobeFetched = onWardrobe;
    _onSavedBoardsFetched = onSavedBoards;
  }

  void invalidateWardrobeCache() {
    _wardrobeCache = null;
    _wardrobeCacheAt = null;
    _wardrobeInflight = null;
  }

  AppwriteService._internal() {
    client = Client()
      ..setEndpoint(Env.appwriteEndpoint)
      ..setProject(Env.appwriteProjectId);

    account = Account(client);
    databases = Databases(client);
    avatars = Avatars(client);
  }

  // =========================================================================
  // PROFILE SYNC OPTIMIZATION: RETRY & CIRCUIT BREAKER
  // =========================================================================

  static const int _maxProfileSyncRetries = 2;
  static const Duration _initialRetryDelay = Duration(milliseconds: 100);

  /// Circuit breaker to prevent rapid-fire retry storms after repeated failures
  late final _profileSyncCircuitBreaker = _ProfileSyncCircuitBreaker();

  // =========================================================================
  // AUTHENTICATION METHODS
  // =========================================================================

  // ================= AHVI AUTH SESSION GUARD V1 =================

  // ================= AHVI PERSISTED USER SESSION V2 BEGIN =================
  static const String _ahviCachedUserIdKey = 'ahvi_current_appwrite_user_id';
  static const String _ahviCachedUserEmailKey =
      'ahvi_current_appwrite_user_email';

  Future<void> _persistCurrentUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ahviCachedUserIdKey, user.$id);
    await prefs.setString(_ahviCachedUserEmailKey, user.email);
  }

  Future<String?> getCachedUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_ahviCachedUserIdKey);
    if (id == null || id.trim().isEmpty) return null;
    return id.trim();
  }

  Future<void> clearCachedUserIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_ahviCachedUserIdKey);
    await prefs.remove(_ahviCachedUserEmailKey);
  }
  // ================= AHVI PERSISTED USER SESSION V2 END =================

  Future<User?> getCurrentUser() async {
    try {
      _cachedUser = await account.get();

      // Canonical source of truth is Appwrite Auth account id.
      await _persistCurrentUser(_cachedUser!);

      return _cachedUser;
    } catch (e) {
      _cachedUser = null;

      // Important:
      // No active Appwrite session. Do not create a new account/profile here.
      // Caller should route to sign-in/onboarding.
      return null;
    }
  }

  // Call this after login to pre-cache user
  Future<void> cacheCurrentUser() async {
    try {
      _cachedUser = await account.get();
      await _persistCurrentUser(_cachedUser!);
    } catch (e) {
      _cachedUser = null;
    }
  }

  // Clear all per-user state. Called on logout AND on every successful
  // login so a freshly authed user never sees the previous user's data.
  void clearUserCache() {
    _cachedUser = null;
    _cachedUserProfileData = null;
    invalidateWardrobeCache();
  }

  Future<void> _deleteExistingSessionsForAuthSwitch() async {
    try {
      await account.deleteSessions();
    } catch (_) {
      try {
        await account.deleteSession(sessionId: 'current');
      } catch (_) {}
    }
  }

  Future<Session?> loginEmailPassword(String email, String password) async {
    try {
      // Wipe any previous user's in-memory state before authenticating
      // the new user. Prevents wardrobe/profile data from one account
      // leaking into the next account on the same device.
      clearUserCache();

      final session = await account.createEmailPasswordSession(
        email: email,
        password: password,
      );

      await cacheCurrentUser();
      await ensureCurrentUserProfile();
      await refreshCurrentUserProfile();

      notifyListeners();
      return session;
    } catch (e) {
      debugPrint("Login error: $e");
      rethrow;
    }
  }

  Future<bool> loginWithGoogle() async {
    try {
      clearUserCache();
      await account.createOAuth2Session(provider: OAuthProvider.google);
      await cacheCurrentUser();
      await ensureCurrentUserProfile();
      await refreshCurrentUserProfile();

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("Google login error: $e");
      return false;
    }
  }

  Future<bool> loginWithApple() async {
    try {
      clearUserCache();
      await account.createOAuth2Session(provider: OAuthProvider.apple);
      await cacheCurrentUser();
      await ensureCurrentUserProfile();
      await refreshCurrentUserProfile();

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("Apple login error: $e");
      return false;
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await account.createRecovery(
        email: email,
        url: '${Env.appwriteEndpoint}/reset-password',
      );
    } catch (e) {
      debugPrint("Password reset error: $e");
      rethrow;
    }
  }

  // ================= EMAIL OTP LOGIN (FIXED - persists state) ==========
  // Appwrite's "email token" flow: createEmailToken() emails a 6-digit
  // secret and returns a Token whose userId we persist to SharedPreferences
  // so it survives app restarts. The subsequent createSession() call needs
  // BOTH the userId and the secret the user typed in, not just the email.

  static const String _otpUserIdKey = 'ahvi_otp_user_id';
  static const String _otpEmailKey = 'ahvi_otp_email';
  static const String _otpTimestampKey = 'ahvi_otp_timestamp';
  static const Duration _otpTimeout = Duration(minutes: 10);

  /// Send OTP to user's email
  ///
  /// Appwrite's createEmailToken() sends a 6-digit code to the email.
  /// We persist the userId so it survives app restarts.
  Future<void> sendOTP(String email) async {
    try {
      // Normalize email
      final normalizedEmail = email.toLowerCase().trim();

      debugPrint('📧 Sending OTP to: $normalizedEmail');

      // Create Appwrite email token (this sends the 6-digit code)
      final token = await account.createEmailToken(
        userId: ID.unique(),
        email: normalizedEmail,
      );

      // ✅ Persist to SharedPreferences (survives app restart!)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_otpUserIdKey, token.userId);
      await prefs.setString(_otpEmailKey, normalizedEmail);
      await prefs.setInt(
        _otpTimestampKey,
        DateTime.now().millisecondsSinceEpoch,
      );

      debugPrint('✅ OTP sent & persisted: userId=${token.userId}');
    } catch (e) {
      debugPrint("❌ Send OTP error: $e");
      rethrow;
    }
  }

  /// Verify OTP code entered by user
  ///
  /// Retrieves the persisted userId and validates the OTP.
  /// Returns true on success, false on any validation failure.
  Future<bool> verifyOTP(String email, String otp) async {
    try {
      // Normalize email
      final normalizedEmail = email.toLowerCase().trim();

      debugPrint('🔐 Verifying OTP for: $normalizedEmail, code: ${otp.substring(0, 2)}***');

      // ✅ Retrieve from persistent storage
      final prefs = await SharedPreferences.getInstance();
      final savedUserId = prefs.getString(_otpUserIdKey);
      final savedEmail = prefs.getString(_otpEmailKey);
      final savedTimestamp = prefs.getInt(_otpTimestampKey);

      // Check if OTP request exists
      if (savedUserId == null || savedEmail == null || savedTimestamp == null) {
        debugPrint("❌ Verify OTP error: no pending OTP request for this email");
        return false;
      }

      // Validate email consistency
      if (normalizedEmail != savedEmail) {
        debugPrint("❌ Verify OTP error: email mismatch (got: $normalizedEmail, expected: $savedEmail)");
        await _clearOTPState();
        return false;
      }

      // Check OTP expiry (10 minutes)
      final otpAge = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(savedTimestamp),
      );
      if (otpAge > _otpTimeout) {
        debugPrint("❌ Verify OTP error: OTP expired (${otpAge.inSeconds}s old, max ${_otpTimeout.inSeconds}s)");
        await _clearOTPState();
        return false;
      }

      // ✅ CRITICAL: Delete all existing sessions BEFORE creating new one
      debugPrint('🔑 Deleting existing sessions before creating new one...');
      try {
        await account.deleteSessions();
        debugPrint('✅ All sessions deleted');
      } catch (e) {
        debugPrint('⚠️  Could not delete all sessions, trying current: $e');
        try {
          await account.deleteSession(sessionId: 'current');
          debugPrint('✅ Current session deleted');
        } catch (e2) {
          debugPrint('⚠️  Could not delete current session: $e2');
          // Continue anyway, might still work
        }
      }

      // Small delay to ensure session deletion is processed
      await Future.delayed(Duration(milliseconds: 500));

      // ✅ NOW create new session with the OTP secret
      debugPrint('🔑 Creating new session with userId: $savedUserId');

      // Wipe any previous user's in-memory state before establishing the
      // new session — same rule as the password login path.
      clearUserCache();

      await account.createSession(userId: savedUserId, secret: otp);

      debugPrint('✅ Session created successfully');

      // ✅ Success! Cache user and profile data
      await cacheCurrentUser();
      await ensureCurrentUserProfile();
      await refreshCurrentUserProfile();

      // ✅ Clean up after successful verification
      await _clearOTPState();
      notifyListeners();

      debugPrint('✅ OTP verification successful!');
      return true;
    } catch (e) {
      debugPrint("❌ Verify OTP error: $e");
      // Don't clear state on Appwrite verification failure
      // (user might retry with correct code)
      return false;
    }
  }

  /// Clear OTP state (call after successful verification or when user cancels)
  Future<void> _clearOTPState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_otpUserIdKey);
      await prefs.remove(_otpEmailKey);
      await prefs.remove(_otpTimestampKey);
      debugPrint('🗑️  OTP state cleared');
    } catch (e) {
      debugPrint('⚠️  Error clearing OTP state: $e');
    }
  }

  /// Allow user to cancel the OTP request and request a new one
  Future<void> cancelOTPRequest() async {
    await _clearOTPState();
    debugPrint('❌ OTP request cancelled by user');
  }

  /// Debug helper: Check current OTP state
  Future<void> debugPrintOTPState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString(_otpUserIdKey);
      final email = prefs.getString(_otpEmailKey);
      final timestamp = prefs.getInt(_otpTimestampKey);

      if (userId == null) {
        debugPrint('🔍 OTP State: [EMPTY - No pending request]');
        return;
      }

      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(timestamp!),
      );
      final isExpired = age > _otpTimeout;

      debugPrint('''
🔍 OTP State:
   userId: $userId
   email: $email
   age: ${age.inSeconds}s
   expired: $isExpired
   timeout: ${_otpTimeout.inMinutes}m
''');
    } catch (e) {
      debugPrint('🔍 OTP State: Error reading - $e');
    }
  }
  // ================= EMAIL OTP LOGIN END (FIXED) ======================

  Future<User> registerEmailPassword(
      String email,
      String password,
      String name,
      ) async {
    final cleanEmail = email.trim();
    final cleanName = name.trim();
    try {
      debugPrint("AHVI_EMAIL_SIGNUP_CREATE_START email=$cleanEmail");
      clearUserCache();
      await clearCachedUserIdentity();
      await _deleteExistingSessionsForAuthSwitch();

      final user = await account.create(
        userId: ID.unique(),
        email: cleanEmail,
        password: password,
        name: cleanName,
      );

      debugPrint("AHVI_EMAIL_SIGNUP_ACCOUNT_CREATED userId=${user.$id}");

      await account.createEmailPasswordSession(
        email: cleanEmail,
        password: password,
      );

      debugPrint("AHVI_EMAIL_SIGNUP_SESSION_CREATED");

      await cacheCurrentUser();
      await ensureCurrentUserProfile();
      await refreshCurrentUserProfile();

      debugPrint("AHVI_EMAIL_SIGNUP_PROFILE_READY");

      notifyListeners();
      return user;
    } catch (e, st) {
      debugPrint("AHVI_EMAIL_SIGNUP_FAILED error=$e");
      debugPrint("$st");
      rethrow;
    }
  }

  Future<void> logout() async {
    // Clear local identity first so any race between the SDK call and a
    // subsequent UI rebuild can never see the previous user.
    await clearCachedUserIdentity();
    try {
      await AhviNotificationService.instance.unregisterForCurrentUser(this);
    } catch (e) {
      debugPrint("Push unregister error: $e");
    }
    // Tear down EVERY session for this user, not just the current one.
    // Prevents the next sign-in on the same device from inheriting an
    // orphan session that still resolves account.get() to the previous
    // user before the new login completes.
    try {
      await account.deleteSessions();
    } catch (e) {
      debugPrint("deleteSessions failed, falling back to current: $e");
      try {
        await account.deleteSession(sessionId: 'current');
      } catch (e2) {
        debugPrint("deleteSession('current') also failed: $e2");
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('onboardingComplete');
    await prefs.remove('user_id');
    await prefs.remove('user_profile');
    clearUserCache();
    notifyListeners();
  }

  // Deletes all active sessions — effectively signs the user out everywhere.
  // Note: Appwrite SDK v22 does not support client-side account deletion.
  // Full account deletion requires an Appwrite Function (server-side).
  Future<void> deleteAccount() async {
    try {
      await AhviNotificationService.instance.unregisterForCurrentUser(this);
      // Delete all sessions so the user is fully signed out on all devices
      await account.deleteSessions();
      notifyListeners();
    } catch (e) {
      debugPrint("Delete account error: $e");
      // Fallback: delete only current session
      try {
        await account.deleteSession(sessionId: 'current');
        notifyListeners();
      } catch (_) {}
    }
  }

  /// Calls the FastAPI backend to wipe the user's account, wardrobe, and
  /// style history from the server.  Throws on any non-200 response so the
  /// caller can show an error and abort the local teardown.
  ///
  /// TODO: replace Env.appwriteEndpoint with Env.backendUrl once that key
  /// is added to config/env.dart.
  Future<void> deleteAccountFromBackend(String userId) async {
    // Retrieve a fresh session JWT to authorise the request.
    // account.createJWT() returns a short-lived token without needing extras.
    String jwt = '';
    try {
      final token = await account.createJWT();
      jwt = token.jwt;
    } catch (e) {
      debugPrint('AHVI_DELETE_BACKEND_JWT_ERROR: $e');
      // If JWT creation fails we still send the request; the backend can
      // fall back to validating the Appwrite session cookie.
    }

    final uri = Uri.parse('${Env.appwriteEndpoint}/api/user/delete-account');
    final response = await http.delete(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (jwt.isNotEmpty) 'Authorization': 'Bearer $jwt',
      },
      body: jsonEncode({'user_id': userId}),
    );

    if (response.statusCode != 200) {
      debugPrint(
        'AHVI_DELETE_BACKEND_FAIL status=${response.statusCode} body=${response.body}',
      );
      throw Exception(
        'Backend returned ${response.statusCode} — account not deleted from server.',
      );
    }

    debugPrint('AHVI_DELETE_BACKEND_OK userId=$userId');
  }

  Future<Uint8List?> getUserAvatar(String name) async {
    try {
      return await avatars.getInitials(name: name);
    } catch (e) {
      debugPrint("Avatar error: $e");
      return null;
    }
  }

  // =========================================================================

  bool _userProfileSyncInFlight = false;
  bool _userProfileSyncInFlight2 = false; // Secondary guard for profile sync

  String _safeUsernameFromUser(dynamic user) {
    // ✅ SAFE: Handle email without @ symbol
    final emailPrefix = user.email.toString().contains('@')
        ? user.email.toString().split('@').first
        : user.email.toString();
    final raw =
    (user.name.toString().trim().isNotEmpty
        ? user.name.toString()
        : emailPrefix)
        .toLowerCase();

    final cleaned = raw
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    if (cleaned.isNotEmpty) return cleaned;
    return 'user_${user.$id.toString().substring(0, 8)}';
  }

  Future<Document?> getCurrentUserProfileDocument({
    bool createIfMissing = true,
  }) async {
    try {
      final usersCollectionId = Env.usersCollection.trim();
      if (usersCollectionId.isEmpty) {
        debugPrint(
          '⚠️ Users collection env is empty. Cannot load user profile.',
        );
        return null;
      }

      final user = await account.get();

      // 🛡️ ANTI-FREEZE GUARD: Prevent recursive calls to ensureCurrentUserProfile
      if (createIfMissing && !_userProfileSyncInFlight) {
        await ensureCurrentUserProfile();
      }

      final document = await databases.getDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: usersCollectionId,
        documentId: user.$id,
      );

      _cachedUserProfileData = Map<String, dynamic>.from(document.data);
      return document;
    } catch (e) {
      debugPrint('❌ Failed to load current user profile: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> refreshCurrentUserProfile() async {
    final document = await getCurrentUserProfileDocument(createIfMissing: true);
    if (document == null) return null;
    _cachedUserProfileData = Map<String, dynamic>.from(document.data);
    return _cachedUserProfileData;
  }

  bool isOnboardingCompleteFromProfile(Map<String, dynamic>? profile) {
    final gender = (profile?['gender'] ?? '').toString().trim();

    final done =
        profile?['onboarding1'] == true &&
            profile?['onboarding2'] == true &&
            profile?['onboarding3'] == true &&
            gender.isNotEmpty;

    debugPrint(
      'AHVI_ONBOARDING_PROFILE '
          'gender=${profile?['gender']} '
          'onboarding1=${profile?['onboarding1']} '
          'onboarding2=${profile?['onboarding2']} '
          'onboarding3=${profile?['onboarding3']} '
          'done=$done',
    );

    return done;
  }

  Future<bool> isCurrentUserOnboardingComplete() async {
    final profile = await refreshCurrentUserProfile();
    final done = isOnboardingCompleteFromProfile(profile);

    // Keep SharedPreferences as a local cache only.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboardingComplete', done);

    return done;
  }

  int? _sanitizeSkinToneForAppwrite(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) {
      if (value.trim().isEmpty) return null;
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
    return null;
  }

  Map<String, dynamic> _cleanProfilePayload(Map<String, dynamic> data) {
    final Map<String, dynamic> cleaned = Map<String, dynamic>.from(data);

    if (cleaned.containsKey('skinTone')) {
      final sanitizedSkinTone = _sanitizeSkinToneForAppwrite(cleaned['skinTone']);
      if (sanitizedSkinTone != null) {
        cleaned['skinTone'] = sanitizedSkinTone;
      } else {
        cleaned.remove('skinTone');
      }
    }

    return cleaned..removeWhere((key, value) => value == null);
  }

  Map<String, dynamic> _coreProfilePayload(Map<String, dynamic> data) {
    const coreKeys = {
      'name',
      'username',
      'email',
      'phone',
      'dob',
      'gender',
      'skinTone',
      'bodyShape',
      'avatar_url',
      'stylePreferences',
      'shopPrefs',
      'onboarding1',
      'onboarding2',
      'onboarding3',
      // ✅ REMOVED: updatedAt and createdAt - Appwrite manages these as system fields ($updatedAt, $createdAt)
      // Never send these manually to the database
    };
    final out = <String, dynamic>{};
    for (final entry in data.entries) {
      if (coreKeys.contains(entry.key) && entry.value != null) {
        out[entry.key] = entry.value;
      }
    }
    return out;
  }

  Future<Document> _updateProfileDocumentWithFallback({
    required String usersCollectionId,
    required String documentId,
    required Map<String, dynamic> payload,
  }) async {
    final cleaned = _cleanProfilePayload(payload);
    try {
      return await databases.updateDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: usersCollectionId,
        documentId: documentId,
        data: cleaned,
      );
    } on AppwriteException catch (e) {
      final fallback = _coreProfilePayload(cleaned);

      bool retryWithSkinToneZero = false;
      if (e.message != null && e.message!.contains('skinTone')) {
        fallback['skinTone'] = 0;
        retryWithSkinToneZero = true;
      }

      if (!retryWithSkinToneZero && (fallback.isEmpty || fallback.length == cleaned.length)) rethrow;

      debugPrint(
        'AHVI_PROFILE_UPDATE_SCHEMA_RETRY error=${e.message} keys=${fallback.keys.toList()}',
      );
      return await databases.updateDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: usersCollectionId,
        documentId: documentId,
        data: fallback,
      );
    }
  }

  Future<Document> _createProfileDocumentWithFallback({
    required String usersCollectionId,
    required String documentId,
    required Map<String, dynamic> payload,
  }) async {
    final cleaned = _cleanProfilePayload(payload);
    try {
      return await databases.createDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: usersCollectionId,
        documentId: documentId,
        data: cleaned,
        permissions: [
          Permission.read(Role.user(documentId)),
          Permission.update(Role.user(documentId)),
          Permission.delete(Role.user(documentId)),
        ],
      );
    } on AppwriteException catch (e) {
      final fallback = _coreProfilePayload(cleaned);

      bool retryWithSkinToneZero = false;
      if (e.message != null && e.message!.contains('skinTone')) {
        fallback['skinTone'] = 0;
        retryWithSkinToneZero = true;
      }

      if (!retryWithSkinToneZero && (fallback.isEmpty || fallback.length == cleaned.length)) rethrow;

      debugPrint(
        'AHVI_PROFILE_CREATE_SCHEMA_RETRY error=${e.message} keys=${fallback.keys.toList()}',
      );
      return await databases.createDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: usersCollectionId,
        documentId: documentId,
        data: fallback,
        permissions: [
          Permission.read(Role.user(documentId)),
          Permission.update(Role.user(documentId)),
          Permission.delete(Role.user(documentId)),
        ],
      );
    }
  }

  /// ✅ NEW: Retry wrapper with exponential backoff and max retry limit
  Future<Document> _updateProfileDocumentWithFallbackRetry({
    required String usersCollectionId,
    required String documentId,
    required Map<String, dynamic> payload,
    int retryCount = 0,
  }) async {
    // Circuit breaker check: if too many failures, fail fast
    if (!_profileSyncCircuitBreaker.canRetry()) {
      debugPrint(
        '⚠️ Profile sync circuit breaker OPEN. Too many failures. Skipping retry.',
      );
      throw Exception('Profile sync circuit breaker is open');
    }

    try {
      final result = await _updateProfileDocumentWithFallback(
        usersCollectionId: usersCollectionId,
        documentId: documentId,
        payload: payload,
      );
      _profileSyncCircuitBreaker.recordSuccess();
      return result;
    } catch (e) {
      _profileSyncCircuitBreaker.recordFailure();

      if (retryCount < _maxProfileSyncRetries) {
        // Exponential backoff: 100ms, 200ms, etc.
        final delay = _initialRetryDelay * (retryCount + 1);
        debugPrint(
          'AHVI_PROFILE_UPDATE_RETRY attempt=${retryCount + 1} '
              'delay=${delay.inMilliseconds}ms error=$e',
        );
        await Future.delayed(delay);
        return _updateProfileDocumentWithFallbackRetry(
          usersCollectionId: usersCollectionId,
          documentId: documentId,
          payload: payload,
          retryCount: retryCount + 1,
        );
      }

      debugPrint(
        '❌ Profile update failed after $_maxProfileSyncRetries retries: $e',
      );
      rethrow;
    }
  }

  /// ✅ NEW: Retry wrapper for document creation
  Future<Document> _createProfileDocumentWithFallbackRetry({
    required String usersCollectionId,
    required String documentId,
    required Map<String, dynamic> payload,
    int retryCount = 0,
  }) async {
    // Circuit breaker check
    if (!_profileSyncCircuitBreaker.canRetry()) {
      debugPrint(
        '⚠️ Profile sync circuit breaker OPEN. Too many failures. Skipping retry.',
      );
      throw Exception('Profile sync circuit breaker is open');
    }

    try {
      final result = await _createProfileDocumentWithFallback(
        usersCollectionId: usersCollectionId,
        documentId: documentId,
        payload: payload,
      );
      _profileSyncCircuitBreaker.recordSuccess();
      return result;
    } catch (e) {
      _profileSyncCircuitBreaker.recordFailure();

      if (retryCount < _maxProfileSyncRetries) {
        final delay = _initialRetryDelay * (retryCount + 1);
        debugPrint(
          'AHVI_PROFILE_CREATE_RETRY attempt=${retryCount + 1} '
              'delay=${delay.inMilliseconds}ms error=$e',
        );
        await Future.delayed(delay);
        return _createProfileDocumentWithFallbackRetry(
          usersCollectionId: usersCollectionId,
          documentId: documentId,
          payload: payload,
          retryCount: retryCount + 1,
        );
      }

      debugPrint(
        '❌ Profile create failed after $_maxProfileSyncRetries retries: $e',
      );
      rethrow;
    }
  }

  Future<void> updateCurrentUserProfileFields(Map<String, dynamic> data) async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception('User not authenticated');

      final usersCollectionId = Env.usersCollection.trim();
      if (usersCollectionId.isEmpty) {
        throw Exception('Users collection env is empty');
      }

      debugPrint('AHVI_PROFILE_UPDATE_START fields=${data.keys.toList()}');

      await ensureCurrentUserProfile();

      // ✅ NOW USES RETRY WRAPPER INSTEAD OF DIRECT CALL
      // ✅ REMOVED: 'updatedAt' - Appwrite manages this as $updatedAt system field
      final updated = await _updateProfileDocumentWithFallbackRetry(
        usersCollectionId: usersCollectionId,
        documentId: user.$id,
        payload: data,  // Don't add updatedAt - let Appwrite handle it
      );

      _cachedUserProfileData = Map<String, dynamic>.from(updated.data);
      await refreshCurrentUserProfile();
      debugPrint('AHVI_PROFILE_UPDATE_SUCCESS userId=${user.$id}');
      notifyListeners();
    } catch (e, st) {
      debugPrint('AHVI_PROFILE_UPDATE_FAILED error=$e');
      debugPrint('$st');
      rethrow;
    }
  }

  Future<Document?> ensureCurrentUserProfile() async {
    // ✅ IMPROVED: Dual guard system to prevent any re-entry
    if (_userProfileSyncInFlight || _userProfileSyncInFlight2) {
      debugPrint('⚠️ Profile sync already in flight, skipping duplicate call');
      return null;
    }

    final usersCollectionId = Env.usersCollection.trim();
    if (usersCollectionId.isEmpty) {
      debugPrint(
        '⚠️ Users collection env is empty. Skipping user profile sync.',
      );
      return null;
    }

    _userProfileSyncInFlight = true;
    _userProfileSyncInFlight2 = true;

    try {
      final user = await account.get();
      debugPrint('AHVI_PROFILE_ENSURE_START userId=${user.$id}');

      final displayName = user.name.toString().trim().isNotEmpty
          ? user.name.toString().trim()
          : (user.email.toString().contains('@')
          ? user.email.toString().split('@').first
          : user.email.toString());

      final createData = <String, dynamic>{
        'name': displayName,
        'username': _safeUsernameFromUser(user),
        'email': user.email,
        // Keep onboarding/profile fields persistent in Appwrite.
        // These are defaults only for first-time users; existing users are never reset.
        'gender': '',
        'onboarding1': false,
        'onboarding2': false,
        'onboarding3': false,
        'stylePreferences': <String>[],
        'skinTone': '',
        'bodyShape': '',
        'shopPrefs': <String>[],
        'dob': '',
        'phone': '',
        // ✅ REMOVED: createdAt and updatedAt - Appwrite manages these as $createdAt and $updatedAt
      };

      try {
        final existing = await databases.getDocument(
          databaseId: Env.appwriteDatabaseId,
          collectionId: usersCollectionId,
          documentId: user.$id,
        );
        debugPrint('AHVI_PROFILE_EXISTS userId=${user.$id}');

        // IMPORTANT: Do not overwrite onboarding/profile answers on relogin.
        // Only refresh identity fields that come from Appwrite Auth.
        // ✅ NOW USES RETRY WRAPPER
        final updated = await _updateProfileDocumentWithFallbackRetry(
          usersCollectionId: usersCollectionId,
          documentId: user.$id,
          payload: {
            'name': displayName,
            'username': _safeUsernameFromUser(user),
            'email': user.email,
            // ✅ REMOVED: 'updatedAt' - Appwrite manages this as $updatedAt
          },
        );

        _cachedUserProfileData = Map<String, dynamic>.from({
          ...existing.data,
          ...updated.data,
        });

        debugPrint('✅ User profile synced: ${user.$id}');
        return updated;
      } on AppwriteException catch (e) {
        if (e.code == 404) {
          debugPrint('AHVI_PROFILE_CREATE_START userId=${user.$id}');
          // ✅ NOW USES RETRY WRAPPER
          final created = await _createProfileDocumentWithFallbackRetry(
            usersCollectionId: usersCollectionId,
            documentId: user.$id,
            payload: createData,
          );

          _cachedUserProfileData = Map<String, dynamic>.from(created.data);
          debugPrint('✅ User profile created: ${user.$id}');
          debugPrint('AHVI_PROFILE_CREATE_SUCCESS userId=${user.$id}');
          return created;
        }

        debugPrint(
          '❌ User profile sync AppwriteException: code=${e.code}, type=${e.type}, message=${e.message}',
        );
        debugPrint('AHVI_PROFILE_CREATE_FAILED error=${e.message}');
        rethrow;
      }
    } catch (e, st) {
      debugPrint('❌ User profile sync failed: $e');
      debugPrint('AHVI_PROFILE_CREATE_FAILED error=$e');
      debugPrint('$st');
      rethrow;
    } finally {
      _userProfileSyncInFlight = false;
      _userProfileSyncInFlight2 = false;
    }
  }

  // 👔 WARDROBE (OUTFITS) DB METHODS
  // =========================================================================

  Future<List<Map<String, dynamic>>> getWardrobeItems({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _wardrobeCache;
      final at = _wardrobeCacheAt;
      if (cached != null &&
          at != null &&
          DateTime.now().difference(at) < _wardrobeTtl) {
        return cached;
      }
      final inflight = _wardrobeInflight;
      if (inflight != null) return inflight;
    }

    final fetch = _fetchWardrobeItems();
    _wardrobeInflight = fetch;
    try {
      final items = await fetch;
      _wardrobeCache = items;
      _wardrobeCacheAt = DateTime.now();
      _onWardrobeFetched?.call(items);
      return items;
    } finally {
      _wardrobeInflight = null;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchWardrobeItems() async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception("User not authenticated");

      dynamic result;
      try {
        result = await databases.listDocuments(
          databaseId: Env.appwriteDatabaseId,
          collectionId: Env.outfitsCollection,
          queries: [
            Query.equal('userId', user.$id),
            Query.orderDesc('\$createdAt'),
            // Appwrite defaults to 25 docs without an explicit limit, which
            // silently truncated larger wardrobes and dropped whole categories
            // (e.g. footwear), so the backend saw no shoes and refused to build
            // a complete outfit board. Lift the cap to cover full wardrobes.
            Query.limit(100),
          ],
        );
      } catch (_) {
        result = null;
      }

      if (result == null || result.documents.isEmpty) {
        result = await databases.listDocuments(
          databaseId: Env.appwriteDatabaseId,
          collectionId: Env.outfitsCollection,
          queries: [
            Query.equal('user_id', user.$id),
            Query.orderDesc('\$createdAt'),
            Query.limit(100),
          ],
        );
      }

      return result.documents.map<Map<String, dynamic>>((doc) {
        return <String, dynamic>{
          "id": doc.$id,
          r"$id": doc.$id,
          "name": doc.data['name'],
          "category": doc.data['category'],
          "sub_category": doc.data['sub_category'],
          "color_code": doc.data['color_code'],
          "pattern": doc.data['pattern'],
          "occasions": doc.data['occasions'],
          "image_url":
          doc.data['normalized_url'] ??
              doc.data['masked_url'] ??
              doc.data['image_url'] ??
              doc.data['raw_url'],
          "masked_url": doc.data['masked_url'],
          "normalized_url": doc.data['normalized_url'],
          "raw_url": doc.data['raw_url'],
          // ── Favourite / like flags ────────────────────────────────────────
          // Exposed so FavouritesScreen can filter liked wardrobe items
          // without a separate query. Both keys are checked because the
          // field name may vary by collection schema version.
          "isLiked": doc.data['isLiked'] ?? doc.data['isFavourite'] ?? false,
          "isFavourite": doc.data['isFavourite'] ?? doc.data['isLiked'] ?? false,
          "imageUrl": doc.data['imageUrl'] ??
              doc.data['normalized_url'] ??
              doc.data['masked_url'] ??
              doc.data['image_url'] ??
              doc.data['raw_url'],
        };
      }).toList();
    } catch (e) {
      debugPrint("👕 Error fetching wardrobe items: $e");
      return [];
    }
  }

  /// ✅ NEW: Update a wardrobe item (e.g., toggle isLiked/isFavourite flag)
  Future<Document> updateWardrobeItem(
      String itemId,
      Map<String, dynamic> updates,
      ) async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception("User not authenticated");

      debugPrint("📝 Updating wardrobe item: $itemId with $updates");

      final doc = await databases.updateDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.outfitsCollection,
        documentId: itemId,
        data: updates,
      );

      // Invalidate cache so next fetch gets fresh data
      invalidateWardrobeCache();

      debugPrint("✅ Wardrobe item updated: $itemId");
      return doc;
    } catch (e) {
      debugPrint("❌ Error updating wardrobe item: $e");
      rethrow;
    }
  }

  // =========================================================================
  // CALENDAR PLANS DB METHODS
  // =========================================================================

  Future<Document> createPlan(Map<String, dynamic> data) async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception("User not authenticated");

      data['userId'] = user.$id; // FIXED to userId

      return await databases.createDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.plansCollection,
        documentId: ID.unique(),
        data: data,
      );
    } catch (e) {
      debugPrint("Error creating plan: $e");
      rethrow;
    }
  }

  Future<List<Document>> getUserPlans() async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception("User not authenticated");

      final result = await databases.listDocuments(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.plansCollection,
        queries: [
          Query.equal('userId', user.$id), // FIXED to userId
        ],
      );
      return result.documents;
    } catch (e) {
      debugPrint("Error fetching plans: $e");
      return [];
    }
  }

  Future<void> deletePlan(String documentId) async {
    try {
      await databases.deleteDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.plansCollection,
        documentId: documentId,
      );
    } catch (e) {
      debugPrint("Error deleting plan: $e");
      rethrow;
    }
  }

  Future<void> updatePlanReminder(String documentId, bool reminder) async {
    try {
      await databases.updateDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.plansCollection,
        documentId: documentId,
        data: {'reminder': reminder},
      );
    } catch (e) {
      debugPrint("Error updating plan reminder: $e");
      rethrow;
    }
  }

  // =========================================================================
  // SAVED BOARDS DB METHODS
  // =========================================================================

  Future<List<Document>> getSavedBoardsByOccasion(String occasion) async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception("User not authenticated");
      final normalizedOccasion = _savedBoardOccasionLabel(occasion);

      final result = await databases.listDocuments(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.savedBoardsCollection,
        queries: [
          Query.equal('userId', user.$id), // FIXED to userId
          Query.equal('occasion', normalizedOccasion),
          Query.orderDesc('\$createdAt'),
        ],
      );
      _onSavedBoardsFetched?.call(occasion, result.documents);
      return result.documents;
    } catch (e) {
      debugPrint("Error fetching $occasion boards: $e");
      return [];
    }
  }

  Future<List<Document>> getAllSavedBoards() async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception("User not authenticated");

      final result = await databases.listDocuments(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.savedBoardsCollection,
        queries: [
          Query.equal('userId', user.$id), // FIXED to userId
          Query.orderDesc('\$createdAt'),
        ],
      );
      return result.documents;
    } catch (e) {
      debugPrint("Error fetching all boards: $e");
      return [];
    }
  }

  // Persist a chat-generated style board to Appwrite so it shows up in the
  // planner pages (occasion / office / party / vacation / everything_else).
  // Schema fields the planner reads:
  //   userId, occasion, outfitDescription, emoji, imageUrl, $createdAt.
  Future<Document?> saveBoardToCollection({
    required String occasion,
    required String outfitDescription,
    String? imageUrl,
    String? emoji,
    String? boardCategory,
    String? boardCategoryLabel,
    String? title,
    String? prompt,
    Map<String, dynamic>? extra,
  }) async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception('User not authenticated');

      final cleanImageUrl = (imageUrl ?? '').trim();
      if (cleanImageUrl.isEmpty) {
        throw Exception('Cannot save board without imageUrl');
      }

      final rawItemIds = extra?['itemIds'] ?? extra?['item_ids'] ?? <dynamic>[];
      final itemIds = rawItemIds is Iterable
          ? rawItemIds
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList()
          : <String>[];
      final outfitItems = _savedBoardItemList(extra?['outfitItems']);
      final items = _savedBoardItemList(extra?['items']);
      final boardPayload = _savedBoardPayload(extra?['board_payload']);
      final boardPayloadCamel = _savedBoardPayload(extra?['boardPayload']);

      final storageOccasion = _savedBoardOccasionLabel(occasion);
      final categoryLabel = boardCategoryLabel?.trim().isNotEmpty == true
          ? boardCategoryLabel!.trim()
          : storageOccasion;
      final categoryKey = boardCategory?.trim().isNotEmpty == true
          ? boardCategory!.trim()
          : _savedBoardCategoryKey(categoryLabel);
      final nowIso = DateTime.now().toIso8601String();

      final richData = <String, dynamic>{
        'userId': user.$id,
        'occasion': storageOccasion,
        'imageUrl': cleanImageUrl,
        'itemIds': itemIds,
        'boardCategory': categoryKey,
        'boardCategoryLabel': categoryLabel,
        'title': (title ?? '').trim().isEmpty
            ? _fallbackSavedBoardTitle(categoryLabel, outfitDescription)
            : title!.trim(),
        'prompt': (prompt ?? '').trim(),
        'outfitDescription': outfitDescription.trim(),
        'thumbnailUrl': cleanImageUrl,
        'emoji': (emoji ?? '').trim().isEmpty ? '✨' : emoji!.trim(),
        // ✅ REMOVED: 'createdAt' - Appwrite manages this as $createdAt
      };
      if (outfitItems.isNotEmpty) richData['outfitItems'] = outfitItems;
      if (items.isNotEmpty) richData['items'] = items;
      if (boardPayload.isNotEmpty) richData['board_payload'] = boardPayload;
      if (boardPayloadCamel.isNotEmpty) {
        richData['boardPayload'] = boardPayloadCamel;
      }

      try {
        return await databases.createDocument(
          databaseId: Env.appwriteDatabaseId,
          collectionId: Env.savedBoardsCollection,
          documentId: ID.unique(),
          data: richData,
        );
      } catch (e) {
        debugPrint(
          'Rich saved board write failed, retrying JSON payload schema: $e',
        );
      }

      if (outfitItems.isNotEmpty || items.isNotEmpty) {
        final payloadItems = outfitItems.isNotEmpty ? outfitItems : items;
        final jsonPayload = jsonEncode({
          'title': richData['title'],
          'occasion': storageOccasion,
          'items': payloadItems,
        });
        try {
          return await databases.createDocument(
            databaseId: Env.appwriteDatabaseId,
            collectionId: Env.savedBoardsCollection,
            documentId: ID.unique(),
            data: {
              'userId': user.$id,
              'occasion': storageOccasion,
              'imageUrl': cleanImageUrl,
              'thumbnailUrl': cleanImageUrl,
              'itemIds': itemIds,
              'boardCategory': categoryKey,
              'boardCategoryLabel': categoryLabel,
              'title': richData['title'],
              'prompt': richData['prompt'],
              'outfitDescription': richData['outfitDescription'],
              'emoji': richData['emoji'],
              // ✅ REMOVED: 'createdAt' - Appwrite manages this as $createdAt
              'board_payload': jsonPayload,
            },
          );
        } catch (e) {
          debugPrint(
            'JSON saved board write failed, retrying minimal schema: $e',
          );
        }
      }

      return await databases.createDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.savedBoardsCollection,
        documentId: ID.unique(),
        data: {
          'userId': user.$id,
          'occasion': storageOccasion,
          'imageUrl': cleanImageUrl,
          'itemIds': itemIds,
        },
      );
    } catch (e) {
      debugPrint('Error saving board: $e');
      return null;
    }
  }

  List<Map<String, dynamic>> _savedBoardItemList(Object? raw) {
    if (raw is! Iterable) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) {
      final url =
          (item['imageUrl'] ??
              item['image_url'] ??
              item['masked_url'] ??
              item['maskedUrl'] ??
              item['url'] ??
              item['thumbnailUrl'])
              ?.toString()
              .trim() ??
              '';
      return url.isNotEmpty;
    })
        .toList();
  }

  Map<String, dynamic> _savedBoardPayload(Object? raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const <String, dynamic>{};
  }

  String _savedBoardOccasionLabel(String value) {
    final raw = value.trim();
    final key = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    switch (key) {
      case 'party':
      case 'party_looks':
      case 'date':
      case 'date_night':
        return 'Party';
      case 'office':
      case 'office_fit':
      case 'office_fits':
      case 'work':
        return 'Office';
      case 'vacation':
      case 'travel':
      case 'airport':
      case 'holiday':
        return 'Vacation';
      case 'occasion':
      case 'wedding':
      case 'event':
      case 'festival':
        return 'Occasion';
      case 'everything_else':
      case 'everything':
      case 'other':
      case 'unclear':
        return 'Everything Else';
      default:
        return raw.isEmpty ? 'Everything Else' : raw;
    }
  }

  String _savedBoardCategoryKey(String label) {
    switch (_savedBoardOccasionLabel(label).toLowerCase()) {
      case 'party':
        return 'party_looks';
      case 'office':
        return 'office_fits';
      case 'vacation':
        return 'vacation';
      case 'occasion':
        return 'occasion';
      default:
        return 'everything_else';
    }
  }

  String _fallbackSavedBoardTitle(String categoryLabel, String desc) {
    final cleanDesc = desc
        .split('+')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(2)
        .join(' ');
    final stem = cleanDesc.isEmpty ? categoryLabel : cleanDesc;
    return '$stem Look';
  }

  Future<void> deleteSavedBoard(String documentId) async {
    try {
      await databases.deleteDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.savedBoardsCollection,
        documentId: documentId,
      );
    } catch (e) {
      debugPrint("Error deleting board: $e");
      throw Exception("Failed to delete board");
    }
  }

  // =========================================================================
  // FAVOURITES DB METHODS (for Saved Boards)
  // =========================================================================

  /// Fetch all favourite saved boards for the current user
  Future<List<Document>> getFavouriteSavedBoards() async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception("User not authenticated");

      final result = await databases.listDocuments(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.savedBoardsCollection,
        queries: [
          Query.equal('userId', user.$id),
          Query.equal('isFavourite', true),
          Query.orderDesc('\$createdAt'),
        ],
      );
      return result.documents;
    } catch (e) {
      debugPrint("Error fetching favourite boards: $e");
      return [];
    }
  }

  /// Add a saved board to favourites
  Future<void> addFavouriteSavedBoard(String documentId) async {
    try {
      await databases.updateDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.savedBoardsCollection,
        documentId: documentId,
        data: {
          'isFavourite': true,
          'favouriteAddedAt': DateTime.now().toIso8601String(),
        },
      );
      debugPrint("Board added to favourites: $documentId");
    } catch (e) {
      debugPrint("Error adding board to favourites: $e");
      throw Exception("Failed to add board to favourites");
    }
  }

  /// Remove a saved board from favourites
  Future<void> removeFavouriteSavedBoard(String documentId) async {
    try {
      await databases.updateDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.savedBoardsCollection,
        documentId: documentId,
        data: {
          'isFavourite': false,
          'favouriteAddedAt': null,
        },
      );
      debugPrint("Board removed from favourites: $documentId");
    } catch (e) {
      debugPrint("Error removing board from favourites: $e");
      throw Exception("Failed to remove board from favourites");
    }
  }

  /// Check if a board is in favourites
  Future<bool> isBoardFavourite(String documentId) async {
    try {
      final result = await databases.getDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.savedBoardsCollection,
        documentId: documentId,
      );
      return (result.data['isFavourite'] ?? false) == true;
    } catch (e) {
      debugPrint("Error checking if board is favourite: $e");
      return false;
    }
  }

  /// Toggle favourite status of a board
  Future<void> toggleBoardFavourite(String documentId) async {
    try {
      final isFav = await isBoardFavourite(documentId);
      if (isFav) {
        await removeFavouriteSavedBoard(documentId);
      } else {
        await addFavouriteSavedBoard(documentId);
      }
    } catch (e) {
      debugPrint("Error toggling board favourite: $e");
      throw Exception("Failed to toggle favourite");
    }
  }

  // =========================================================================
  // SKINCARE DB METHODS
  // =========================================================================

  Future<Document?> getSkincareProfile() async {
    try {
      final user = await getCurrentUser();
      if (user == null) return null;

      final result = await databases.listDocuments(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.skincareCollection,
        queries: [Query.equal('userId', user.$id)], // FIXED to userId
      );

      if (result.documents.isEmpty) {
        return await databases.createDocument(
          databaseId: Env.appwriteDatabaseId,
          collectionId: Env.skincareCollection,
          documentId: ID.unique(),
          data: {
            'userId': user.$id, // FIXED to userId
            'skinType': '',
            'concerns': [],
            'daySteps': [],
            'nightSteps': [],
            'lastUpdated': DateTime.now().toIso8601String(),
          },
        );
      }
      return result.documents.first;
    } catch (e) {
      debugPrint("Error fetching skincare profile: $e");
      return null;
    }
  }

  Future<void> updateSkincareProfile({
    required String documentId,
    String? skinType,
    List<String>? concerns,
    List<int>? daySteps,
    List<int>? nightSteps,
  }) async {
    try {
      Map<String, dynamic> updateData = {};
      if (skinType != null) updateData['skinType'] = skinType;
      if (concerns != null) updateData['concerns'] = concerns;
      if (daySteps != null) updateData['daySteps'] = daySteps;
      if (nightSteps != null) updateData['nightSteps'] = nightSteps;
      updateData['lastUpdated'] = DateTime.now().toIso8601String();

      await databases.updateDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.skincareCollection,
        documentId: documentId,
        data: updateData,
      );
    } catch (e) {
      debugPrint("Error updating skincare profile: $e");
    }
  }

  // =========================================================================
  // WORKOUT OUTFITS DB METHODS
  // =========================================================================

  Future<List<Document>> getWorkoutOutfits() async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception("User not authenticated");

      final result = await databases.listDocuments(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.workoutOutfitsCollection,
        queries: [
          Query.equal('userId', user.$id), // FIXED to userId
          Query.orderDesc('\$createdAt'),
        ],
      );
      return result.documents;
    } catch (e) {
      debugPrint("Error fetching workout outfits: $e");
      return [];
    }
  }

  Future<Document> createWorkoutOutfit(Map<String, dynamic> data) async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception("User not authenticated");

      data['userId'] = user.$id; // FIXED to userId

      return await databases.createDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.workoutOutfitsCollection,
        documentId: ID.unique(),
        data: data,
      );
    } catch (e) {
      debugPrint("Error creating workout outfit: $e");
      rethrow;
    }
  }

  Future<void> deleteWorkoutOutfit(String documentId) async {
    try {
      await databases.deleteDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.workoutOutfitsCollection,
        documentId: documentId,
      );
    } catch (e) {
      debugPrint("Error deleting workout outfit: $e");
      rethrow;
    }
  }

  // =========================================================================
  // BILLS & COUPONS DB METHODS
  // =========================================================================

  Future<List<Document>> getBills() async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception("User not authenticated");

      final result = await databases.listDocuments(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.billsCollection,
        queries: [
          Query.equal('userId', user.$id), // FIXED to userId
          Query.orderDesc('\$createdAt'),
        ],
      );
      return result.documents;
    } catch (e) {
      debugPrint("Error fetching bills: $e");
      return [];
    }
  }

  Future<Document> createBill(Map<String, dynamic> data) async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception("User not authenticated");

      data['userId'] = user.$id; // FIXED to userId

      return await databases.createDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.billsCollection,
        documentId: ID.unique(),
        data: data,
      );
    } catch (e) {
      debugPrint("Error creating bill: $e");
      rethrow;
    }
  }

  Future<void> deleteBill(String documentId) async {
    try {
      await databases.deleteDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.billsCollection,
        documentId: documentId,
      );
    } catch (e) {
      debugPrint("Error deleting bill: $e");
      rethrow;
    }
  }

  Future<List<Document>> getCoupons() async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception("User not authenticated");

      final result = await databases.listDocuments(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.couponsCollection,
        queries: [
          Query.equal('userId', user.$id), // FIXED to userId
          Query.orderDesc('\$createdAt'),
        ],
      );
      return result.documents;
    } catch (e) {
      debugPrint("Error fetching coupons: $e");
      return [];
    }
  }

  Future<Document> createCoupon(Map<String, dynamic> data) async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception("User not authenticated");

      data['userId'] = user.$id; // FIXED to userId

      return await databases.createDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.couponsCollection,
        documentId: ID.unique(),
        data: data,
      );
    } catch (e) {
      debugPrint("Error creating coupon: $e");
      rethrow;
    }
  }

  Future<void> deleteCoupon(String documentId) async {
    try {
      await databases.deleteDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.couponsCollection,
        documentId: documentId,
      );
    } catch (e) {
      debugPrint("Error deleting coupon: $e");
      rethrow;
    }
  }

  // =========================================================================
  // MEDI TRACKER DB METHODS
  // =========================================================================

  Future<List<Document>> getMeds() async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception("User not authenticated");

      final result = await databases.listDocuments(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.medsCollection,
        queries: [
          Query.equal('userId', user.$id), // FIXED to userId
          Query.orderDesc('\$createdAt'),
        ],
      );
      return result.documents;
    } catch (e) {
      debugPrint("Error fetching meds: $e");
      return [];
    }
  }

  Future<Document> createMed(Map<String, dynamic> data) async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception("User not authenticated");
      data['userId'] = user.$id; // FIXED to userId

      return await databases.createDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.medsCollection,
        documentId: ID.unique(),
        data: data,
      );
    } catch (e) {
      debugPrint("Error creating med: $e");
      rethrow;
    }
  }

  Future<void> updateMed(String documentId, Map<String, dynamic> data) async {
    try {
      await databases.updateDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.medsCollection,
        documentId: documentId,
        data: data,
      );
    } catch (e) {
      debugPrint("Error updating med: $e");
      rethrow;
    }
  }

  Future<void> deleteMed(String documentId) async {
    try {
      await databases.deleteDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.medsCollection,
        documentId: documentId,
      );
    } catch (e) {
      debugPrint("Error deleting med: $e");
      rethrow;
    }
  }

  Future<List<Document>> getMedLogs() async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception("User not authenticated");

      final result = await databases.listDocuments(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.medLogsCollection,
        queries: [
          Query.equal('userId', user.$id), // FIXED to userId
          Query.orderDesc('time'),
        ],
      );
      return result.documents;
    } catch (e) {
      debugPrint("Error fetching med logs: $e");
      return [];
    }
  }

  Future<Document> createMedLog(Map<String, dynamic> data) async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception("User not authenticated");
      data['userId'] = user.$id; // FIXED to userId

      debugPrint(
        'AHVI_MEDLOG_CREATE userId=${user.$id} '
            'medId=${data['medId']} status=${data['status']} '
            'collection=${Env.medLogsCollection}',
      );

      final doc = await databases.createDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.medLogsCollection,
        documentId: ID.unique(),
        data: data,
      );
      debugPrint('AHVI_MEDLOG_OK id=${doc.$id}');
      return doc;
    } catch (e, st) {
      // Appwrite errors usually carry a `.code` + `.message`. Stringify
      // so adb logcat shows EXACTLY why the write failed — most common
      // case is collection permission (Users role lacks create).
      debugPrint('AHVI_MEDLOG_FAIL err=$e');
      debugPrint('AHVI_MEDLOG_FAIL stack=$st');
      rethrow;
    }
  }

  // =========================================================================
  // MEAL PLANNER DB METHODS
  // =========================================================================

  Future<List<Document>> getMealPlans() async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception("User not authenticated");

      final result = await databases.listDocuments(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.mealPlansCollection,
        queries: [
          Query.equal('userId', user.$id), // FIXED to userId
          Query.orderDesc('\$createdAt'),
        ],
      );
      return result.documents;
    } catch (e) {
      debugPrint("Error fetching meal plans: $e");
      return [];
    }
  }

  Future<Document> createMealPlan(Map<String, dynamic> data) async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception("User not authenticated");
      data['userId'] = user.$id; // FIXED to userId

      return await databases.createDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.mealPlansCollection,
        documentId: ID.unique(),
        data: data,
      );
    } catch (e) {
      debugPrint("Error creating meal plan: $e");
      rethrow;
    }
  }

  Future<void> deleteMealPlan(String documentId) async {
    try {
      await databases.deleteDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.mealPlansCollection,
        documentId: documentId,
      );
    } catch (e) {
      debugPrint("Error deleting meal plan: $e");
      rethrow;
    }
  }

  // =========================================================================
  // LIFE GOALS DB METHODS
  // =========================================================================

  Future<List<Document>> getLifeGoals() async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception("User not authenticated");

      final result = await databases.listDocuments(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.lifeGoalsCollection,
        queries: [
          Query.equal('userId', user.$id), // FIXED to userId
          Query.orderDesc('\$createdAt'),
        ],
      );
      return result.documents;
    } catch (e) {
      debugPrint("Error fetching life goals: $e");
      return [];
    }
  }

  Future<Document> createLifeGoal(Map<String, dynamic> data) async {
    try {
      final user = await getCurrentUser();
      if (user == null) throw Exception("User not authenticated");
      data['userId'] = user.$id; // FIXED to userId

      return await databases.createDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.lifeGoalsCollection,
        documentId: ID.unique(),
        data: data,
      );
    } catch (e) {
      debugPrint("Error creating life goal: $e");
      rethrow;
    }
  }

  Future<void> updateLifeGoalProgress(String documentId, int progress) async {
    try {
      await databases.updateDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.lifeGoalsCollection,
        documentId: documentId,
        data: {'progress': progress},
      );
    } catch (e) {
      debugPrint("Error updating life goal progress: $e");
      rethrow;
    }
  }

  Future<void> deleteLifeGoal(String documentId) async {
    try {
      await databases.deleteDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.lifeGoalsCollection,
        documentId: documentId,
      );
    } catch (e) {
      debugPrint("Error deleting life goal: $e");
      rethrow;
    }
  }
}

/// ✅ NEW: Circuit breaker pattern to prevent rapid-fire retry storms
class _ProfileSyncCircuitBreaker {
  int _failureCount = 0;
  DateTime? _failureResetTime;

  static const int _maxConsecutiveFailures = 5;
  static const Duration _circuitBreakerReset = Duration(seconds: 30);

  /// Returns true if we can attempt another retry
  bool canRetry() {
    if (_failureCount >= _maxConsecutiveFailures) {
      final now = DateTime.now();
      if (_failureResetTime != null &&
          now.difference(_failureResetTime!) > _circuitBreakerReset) {
        debugPrint('🔄 Profile sync circuit breaker RESET after cooldown');
        _failureCount = 0;
        _failureResetTime = null;
        return true;
      }
      return false;
    }
    return true;
  }

  void recordFailure() {
    _failureCount++;
    _failureResetTime = DateTime.now();
    debugPrint('❌ Profile sync failure recorded ($_failureCount/$_maxConsecutiveFailures)');
  }

  void recordSuccess() {
    _failureCount = 0;
    _failureResetTime = null;
    debugPrint('✅ Profile sync success, circuit breaker reset');
  }
}