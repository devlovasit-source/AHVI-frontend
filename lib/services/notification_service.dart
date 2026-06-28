import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:myapp/config/env.dart';
import 'package:myapp/services/appwrite_service.dart';

class AhviNotificationService {
  AhviNotificationService._();

  static final AhviNotificationService instance = AhviNotificationService._();

  static const String _tokenKey = 'ahvi_fcm_token';
  static const String _unreadKey = 'ahvi_medi_notification_unread_count';
  static const String _latestKey = 'ahvi_medi_notification_latest';
  static const String _reminderChannelId = 'ahvi_reminders';
  static const String _reminderChannelName = 'AHVI Reminders';

  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _firebaseReady = false;
  bool _initAttempted = false;
  bool _handlersInstalled = false;
  bool _localNotificationsReady = false;
  bool _unreadLoaded = false;
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  void Function(Map<String, String> data)? _onMediReminder;

  Future<void> _loadUnreadCount() async {
    if (_unreadLoaded) return;
    _unreadLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      unreadCount.value = prefs.getInt(_unreadKey) ?? 0;
    } catch (e) {
      debugPrint('AHVI notification unread load skipped: $e');
    }
  }

  Future<void> markMediNotificationsRead() async {
    unreadCount.value = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_unreadKey, 0);
    } catch (e) {
      debugPrint('AHVI notification unread reset skipped: $e');
    }
  }

  Future<void> _storeForegroundMediReminder(Map<String, String> data) async {
    await _loadUnreadCount();
    final nextCount = unreadCount.value + 1;
    unreadCount.value = nextCount;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_unreadKey, nextCount);
      await prefs.setString(_latestKey, jsonEncode(data));
    } catch (e) {
      debugPrint('AHVI notification foreground store skipped: $e');
    }
  }

  Future<void> _ensureLocalNotifications() async {
    if (_localNotificationsReady || kIsWeb) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload ?? '';
        if (payload.isEmpty) return;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map) {
            final data = _stringData(Map<String, dynamic>.from(decoded));
            if (_isMediReminder(data)) {
              _onMediReminder?.call(data);
            }
          }
        } catch (e) {
          debugPrint('AHVI notification tap payload ignored: $e');
        }
      },
    );

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        _reminderChannelId,
        _reminderChannelName,
        importance: Importance.high,
        playSound: true,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }
    _localNotificationsReady = true;
  }

  Future<void> _showForegroundMediNotification(
    RemoteMessage message,
    Map<String, String> data,
  ) async {
    await _ensureLocalNotifications();
    if (!_localNotificationsReady || !Platform.isAndroid) return;

    final title =
        message.notification?.title ?? data['title'] ?? 'Medicine reminder';
    final body =
        message.notification?.body ??
        data['body'] ??
        data['message'] ??
        'Time to take your medicine.';
    const androidDetails = AndroidNotificationDetails(
      _reminderChannelId,
      _reminderChannelName,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      channelShowBadge: true,
    );
    const details = NotificationDetails(android: androidDetails);
    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title,
      body: body,
      notificationDetails: details,
      payload: jsonEncode(data),
    );
  }

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
      await _loadUnreadCount();
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

  Future<void> _handleMediReminder(RemoteMessage message, String source) async {
    final data = _stringData(message.data);
    if (!_isMediReminder(data)) return;
    if (source == 'foreground') {
      debugPrint('AHVI_MED_NOTIFICATION_FOREGROUND data=$data');
      await _storeForegroundMediReminder(data);
      await _showForegroundMediNotification(message, data);
      return;
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
        await _handleMediReminder(initial, 'initial');
      }
      _openedSub ??= FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => unawaited(_handleMediReminder(message, 'opened')),
      );
      _foregroundSub ??= FirebaseMessaging.onMessage.listen(
        (message) => unawaited(_handleMediReminder(message, 'foreground')),
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
