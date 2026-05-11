import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:appwrite/enums.dart';
import 'package:myapp/config/env.dart';
import 'package:myapp/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppwriteService extends ChangeNotifier {
  late Client client;
  late Account account;
  late Databases databases;
  late Avatars avatars;

  // Cached user — avoid repeated network calls
  User? _cachedUser;
  Map<String, dynamic>? _cachedUserProfileData;

  Map<String, dynamic>? get cachedUserProfileData => _cachedUserProfileData;

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

  AppwriteService() {
    client = Client()
      ..setEndpoint(Env.appwriteEndpoint)
      ..setProject(Env.appwriteProjectId);

    account = Account(client);
    databases = Databases(client);
    avatars = Avatars(client);
  }

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

  Future<User> registerEmailPassword(
    String email,
    String password,
    String name,
  ) async {
    try {
      final user = await account.create(
        userId: ID.unique(),
        email: email,
        password: password,
        name: name,
      );
      return user;
    } catch (e) {
      debugPrint("Register error: $e");
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

  String _safeUsernameFromUser(dynamic user) {
    final emailPrefix = user.email.toString().split('@').first;
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
      if (createIfMissing) {
        await ensureCurrentUserProfile();
      }

      final document = await databases.getDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: usersCollectionId,
        documentId: user.$id,
      );

      _cachedUserProfileData = Map<String, dynamic>.from(document.data)
        ..[r'$createdAt'] = document.$createdAt
        ..[r'$updatedAt'] = document.$updatedAt;
      return document;
    } catch (e) {
      debugPrint('❌ Failed to load current user profile: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> refreshCurrentUserProfile() async {
    final document = await getCurrentUserProfileDocument(createIfMissing: true);
    if (document == null) return null;
    _cachedUserProfileData = Map<String, dynamic>.from(document.data)
      ..[r'$createdAt'] = document.$createdAt
      ..[r'$updatedAt'] = document.$updatedAt;
    return _cachedUserProfileData;
  }

  bool isOnboardingCompleteFromProfile(Map<String, dynamic>? profile) {
    if (profile == null) return false;
    final flagsComplete = profile['onboarding1'] == true &&
        profile['onboarding2'] == true &&
        profile['onboarding3'] == true;
    if (flagsComplete) return true;

    // Legacy compatibility: older registered users may have a users row from
    // before onboarding flags were persisted. Do not send them back through
    // profile setup if they already have meaningful style/profile data.
    final styles = profile['stylePreferences'];
    final hasStyles = styles is List && styles.isNotEmpty;
    final hasProfileSignals =
        (profile['gender']?.toString().trim().isNotEmpty ?? false) ||
        (profile['bodyShape']?.toString().trim().isNotEmpty ?? false) ||
        profile['skinTone'] != null ||
        hasStyles;
    if (hasProfileSignals) return true;

    // If this is an older existing account row with auth identity only, treat
    // it as registered. Brand-new rows created during sign-up remain first-time
    // for a short window so new users still see onboarding.
    final createdRaw = profile[r'$createdAt']?.toString();
    final createdAt = createdRaw == null ? null : DateTime.tryParse(createdRaw);
    final hasIdentity =
        (profile['email']?.toString().trim().isNotEmpty ?? false) &&
        (profile['name']?.toString().trim().isNotEmpty ?? false);
    if (hasIdentity && createdAt != null) {
      final age = DateTime.now().toUtc().difference(createdAt.toUtc());
      if (age > const Duration(minutes: 10)) return true;
    }
    return false;
  }

  Future<bool> isCurrentUserOnboardingComplete() async {
    final profile = await refreshCurrentUserProfile();
    final serverSaysDone = isOnboardingCompleteFromProfile(profile);

    final prefs = await SharedPreferences.getInstance();
    final cachedDone = prefs.getBool('onboardingComplete') == true;

    // Legacy users whose Appwrite profile predates the onboarding1/2/3 flags
    // may have completed onboarding on this device. Trust the local cache as
    // a fallback so they are not sent through onboarding again.
    final done = serverSaysDone || cachedDone;

    await prefs.setBool('onboardingComplete', done);
    return done;
  }

  Future<void> updateCurrentUserProfileFields(Map<String, dynamic> data) async {
    final user = await getCurrentUser();
    if (user == null) throw Exception('User not authenticated');

    final usersCollectionId = Env.usersCollection.trim();
    if (usersCollectionId.isEmpty) {
      throw Exception('Users collection env is empty');
    }

    await ensureCurrentUserProfile();

    final cleaned = Map<String, dynamic>.from(data)
      ..removeWhere((key, value) => value == null);

    await databases.updateDocument(
      databaseId: Env.appwriteDatabaseId,
      collectionId: usersCollectionId,
      documentId: user.$id,
      data: cleaned,
    );

    await refreshCurrentUserProfile();
    notifyListeners();
  }

  Future<void> ensureCurrentUserProfile() async {
    if (_userProfileSyncInFlight) return;

    final usersCollectionId = Env.usersCollection.trim();
    if (usersCollectionId.isEmpty) {
      debugPrint(
        '⚠️ Users collection env is empty. Skipping user profile sync.',
      );
      return;
    }

    _userProfileSyncInFlight = true;

    try {
      final user = await account.get();

      final displayName = user.name.toString().trim().isNotEmpty
          ? user.name.toString().trim()
          : user.email.toString().split('@').first;

      final createData = <String, dynamic>{
        'name': displayName,
        'username': _safeUsernameFromUser(user),
        'email': user.email,
        // Keep onboarding/profile fields persistent in Appwrite.
        // These are defaults only for first-time users; existing users are never reset.
        'onboarding1': false,
        'onboarding2': false,
        'onboarding3': false,
        'stylePreferences': <String>[],
      };

      try {
        final existing = await databases.getDocument(
          databaseId: Env.appwriteDatabaseId,
          collectionId: usersCollectionId,
          documentId: user.$id,
        );

        // IMPORTANT: Do not overwrite onboarding/profile answers on relogin.
        // Only refresh identity fields that come from Appwrite Auth.
        final updated = await databases.updateDocument(
          databaseId: Env.appwriteDatabaseId,
          collectionId: usersCollectionId,
          documentId: user.$id,
          data: {
            'name': displayName,
            'username': _safeUsernameFromUser(user),
            'email': user.email,
          },
        );

        _cachedUserProfileData = Map<String, dynamic>.from({
          ...existing.data,
          ...updated.data,
        })
          ..[r'$createdAt'] = updated.$createdAt
          ..[r'$updatedAt'] = updated.$updatedAt;

        debugPrint('✅ User profile synced: ${user.$id}');
      } on AppwriteException catch (e) {
        if (e.code == 404) {
          final created = await databases.createDocument(
            databaseId: Env.appwriteDatabaseId,
            collectionId: usersCollectionId,
            documentId: user.$id,
            data: createData,
            permissions: [
              Permission.read(Role.user(user.$id)),
              Permission.update(Role.user(user.$id)),
              Permission.delete(Role.user(user.$id)),
            ],
          );

          _cachedUserProfileData = Map<String, dynamic>.from(created.data)
            ..[r'$createdAt'] = created.$createdAt
            ..[r'$updatedAt'] = created.$updatedAt;
          debugPrint('✅ User profile created: ${user.$id}');
          return;
        }

        debugPrint(
          '❌ User profile sync AppwriteException: code=${e.code}, type=${e.type}, message=${e.message}',
        );
      }
    } catch (e) {
      debugPrint('❌ User profile sync failed: $e');
    } finally {
      _userProfileSyncInFlight = false;
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
              doc.data['image_url'] ??
              doc.data['masked_url'] ??
              doc.data['raw_url'],
          "masked_url": doc.data['masked_url'],
          "raw_url": doc.data['raw_url'],
        };
      }).toList();
    } catch (e) {
      debugPrint("👕 Error fetching wardrobe items: $e");
      return [];
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

      final result = await databases.listDocuments(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.savedBoardsCollection,
        queries: [
          Query.equal('userId', user.$id), // FIXED to userId
          Query.equal('occasion', occasion),
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

      // Current Appwrite saved_boards schema supports only:
      // userId, imageUrl, itemIds, occasion.
      // Keep this direct Appwrite fallback schema-safe.
      return await databases.createDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.savedBoardsCollection,
        documentId: ID.unique(),
        data: {
          'userId': user.$id,
          'occasion': occasion,
          'imageUrl': cleanImageUrl,
          'itemIds': itemIds,
        },
      );
    } catch (e) {
      debugPrint('Error saving board: $e');
      return null;
    }
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

      return await databases.createDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.medLogsCollection,
        documentId: ID.unique(),
        data: data,
      );
    } catch (e) {
      debugPrint("Error creating med log: $e");
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
