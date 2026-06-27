import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:myapp/config/env.dart';
import 'package:myapp/services/appwrite_service.dart';

class AhviNotificationService {
  AhviNotificationService._();

  static final AhviNotificationService instance = AhviNotificationService._();

  static const String _tokenKey = 'ahvi_fcm_token';
  bool _firebaseReady = false;
  bool _initAttempted = false;
  bool _handlersInstalled = false;
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  void Function(Map<String, String> data)? _onMediReminder;

  void configureMediReminderHandler(
    void Function(Map<String, String> data) onMediReminder,
  ) {
    _onMediReminder = onMediReminder;
  }

  Future<bool> _ensureFirebase() async {
    if (_firebaseReady) return true;
    if (_initAttempted && !_firebaseReady) return false;
    _initAttempted = true;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _firebaseReady = true;
      return true;
    } catch (e) {
      debugPrint('AHVI notifications disabled: Firebase not configured ($e)');
      return false;
    }
  }

  String get _platform {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  Future<Map<String, String>> _authHeaders(AppwriteService appwrite) async {
    final jwt = await appwrite.account.createJWT();
    final token = jwt.jwt;
    if (token.isEmpty) throw Exception('Could not create Appwrite JWT');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<void> registerForCurrentUser(AppwriteService appwrite) async {
    final ready = await _ensureFirebase();
    if (!ready) return;

    try {
      await _installMessageHandlers();
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;

      await _registerToken(appwrite, token);
      _refreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen((fresh) {
        unawaited(_registerToken(appwrite, fresh));
      });
    } catch (e) {
      debugPrint('AHVI notification registration skipped: $e');
    }
  }

  bool _isMediReminder(Map<String, dynamic> data) {
    final action = (data['action'] ?? '').toString();
    final screen = (data['screen'] ?? '').toString();
    return action == 'med_reminder' || screen == 'medi';
  }

  Map<String, String> _stringData(Map<String, dynamic> data) {
    return data.map((key, value) => MapEntry(key.toString(), value.toString()));
  }

  void _handleMediReminder(RemoteMessage message, String source) {
    final data = _stringData(message.data);
    if (!_isMediReminder(data)) return;
    if (source == 'foreground') {
      debugPrint('AHVI_MED_NOTIFICATION_FOREGROUND data=$data');
    } else {
      debugPrint('AHVI_MED_NOTIFICATION_OPENED source=$source data=$data');
    }
    _onMediReminder?.call(data);
  }

  Future<void> _installMessageHandlers() async {
    final ready = await _ensureFirebase();
    if (!ready || _handlersInstalled) return;
    _handlersInstalled = true;

    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        _handleMediReminder(initial, 'initial');
      }
      _openedSub ??= FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _handleMediReminder(message, 'opened'),
      );
      _foregroundSub ??= FirebaseMessaging.onMessage.listen(
        (message) => _handleMediReminder(message, 'foreground'),
      );
    } catch (e) {
      debugPrint('AHVI notification handlers skipped: $e');
    }
  }

  Future<void> unregisterForCurrentUser(AppwriteService appwrite) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      if (token == null || token.isEmpty) return;

      final response = await http.post(
        Uri.parse('${Env.backendApiUrl}/api/notifications/devices/unregister'),
        headers: await _authHeaders(appwrite),
        body: jsonEncode({'token': token}),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await prefs.remove(_tokenKey);
      }
    } catch (e) {
      debugPrint('AHVI notification unregister skipped: $e');
    }
  }

  Future<void> _registerToken(AppwriteService appwrite, String token) async {
    if (Env.backendApiUrl.trim().isEmpty) return;

    final user = await appwrite.getCurrentUser();
    final userId = user?.$id ?? '';
    if (userId.isEmpty) return;

    final response = await http.post(
      Uri.parse('${Env.backendApiUrl}/api/notifications/devices/register'),
      headers: await _authHeaders(appwrite),
      body: jsonEncode({
        'platform': _platform,
        'token': token,
        'user_id': userId,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Notification token registration failed: ${response.statusCode}',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }
}
