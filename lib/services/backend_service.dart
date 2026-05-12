import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:myapp/config/env.dart';
import 'package:myapp/services/appwrite_service.dart';

Map<String, dynamic> _parseJsonMap(String payload) =>
    Map<String, dynamic>.from(jsonDecode(payload) as Map);

String _encodeBytes(Uint8List bytes) => base64Encode(bytes);

class BackendRequestException implements Exception {
  final String message;
  const BackendRequestException(this.message);

  @override
  String toString() => message;
}

String _demoChatFallback(String query, String moduleContext) {
  final q = query.toLowerCase();
  final isStyle = moduleContext == 'style' || moduleContext == 'wardrobe';
  final isPlanPrep =
      moduleContext == 'plan' ||
      moduleContext == 'prepare' ||
      moduleContext == 'prep' ||
      q.contains('plan') ||
      q.contains('prep') ||
      q.contains('prepare') ||
      q.contains('checklist');
  if (q.contains('joke')) {
    return 'Here is a tiny one: Why did the shirt get promoted? Because it had outstanding style.';
  }
  if (q.contains('how are you') || q == 'hi' || q == 'hello' || q == 'hey') {
    return 'I am here and ready. Ask me for an outfit, a capsule wardrobe, or just talk to me.';
  }
  if (isStyle ||
      q.contains('outfit') ||
      q.contains('wear') ||
      q.contains('style')) {
    return 'AHVI is still styling this. Try again in a moment.';
  }
  if (isPlanPrep) {
    return 'AHVI is still preparing this. Try again in a moment.';
  }
  return 'AHVI is still thinking this through. Try again in a moment.';
}

class BackendService {
  final String baseUrl = Env.backendApiUrl;
  final AppwriteService _appwriteService;

  BackendService({AppwriteService? appwriteService})
    : _appwriteService = appwriteService ?? AppwriteService();

  Future<String> _currentUserId() async {
    final user = await _appwriteService.getCurrentUser();

    if (user != null && user.$id.trim().isNotEmpty) {
      return user.$id.trim();
    }

    // Appwrite session may still be restoring on app start.
    // Use the last authenticated id only as a continuity fallback.
    final cachedUserId = await _appwriteService.getCachedUserId();
    if (cachedUserId != null && cachedUserId.trim().isNotEmpty) {
      return cachedUserId.trim();
    }

    // Never send user_1, empty string, ID.unique(), or any fake user id.
    throw StateError(
      'No authenticated Appwrite user. User must sign in before backend requests.',
    );
  }

  Future<Map<String, String>> _authHeaders() async {
    final jwt = await _appwriteService.account.createJWT();
    final token = jwt.jwt;
    if (token.isEmpty) throw Exception('Could not create Appwrite JWT');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Object _memoryPayload(String currentMemory) {
    final trimmed = currentMemory.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};
    return {'summary': trimmed};
  }

  String _messageText(Map<String, dynamic> data) {
    final message = data['message'];
    if (message is String) return message;
    if (message is Map) return (message['content'] ?? '').toString();
    return data['response']?.toString() ??
        "I'm having trouble thinking right now.";
  }

  Map<String, dynamic> _normalizeChatResponse(Map<String, dynamic> data) {
    var cleanText = _messageText(data);
    var extractedChips = List<dynamic>.from(data['chips'] as List? ?? []);
    String? extractedBoardData =
        (data['board_ids'] != null && data['board_ids'].toString().isNotEmpty)
        ? data['board_ids'].toString()
        : null;
    String? extractedPackData;
    var hiddenMenuText = '';

    final chipsMatch = RegExp(r'\[CHIPS:\s*(.*?)\]').firstMatch(cleanText);
    if (chipsMatch != null) {
      extractedChips = chipsMatch
          .group(1)!
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      cleanText = cleanText.replaceAll(chipsMatch.group(0)!, '').trim();
    }

    final boardMatch = RegExp(
      r'\[STYLE_BOARD:\s*(.*?)\]',
    ).firstMatch(cleanText);
    if (boardMatch != null) {
      extractedBoardData = boardMatch.group(1);
      cleanText = cleanText.replaceAll(boardMatch.group(0)!, '').trim();
    }

    final packMatch = RegExp(r'\[PACK_LIST:\s*(.*?)\]').firstMatch(cleanText);
    if (packMatch != null) {
      extractedPackData = packMatch.group(1);
      hiddenMenuText = cleanText.replaceAll(packMatch.group(0)!, '').trim();
      cleanText = "I've prepared your custom packing menu.";
    }

    return {
      ...data,
      'message': {'role': 'assistant', 'content': cleanText},
      'message_text': cleanText,
      'chips': extractedChips,
      'board_ids': extractedBoardData,
      'pack_ids': extractedPackData,
      'full_menu_text': hiddenMenuText,
      'has_actions': extractedBoardData != null || extractedPackData != null,
    };
  }

  // Chat and styling engine.
  Future<Map<String, dynamic>> sendChatQuery(
    String query,
    String userId,
    List<Map<String, String>> chatHistory,
    String currentMemory, {
    bool isRetry = false,
    List<Map<String, dynamic>>? fetchedWardrobe,
    String moduleContext = 'chat',
    Map<String, dynamic>? userProfile,
    String? styleAction,
    List<String> excludeStyleSignatures = const [],
    int? requestedBoardCount,
  }) async {
    try {
      final authedUserId = await _currentUserId();
      var wardrobeForRequest = fetchedWardrobe;
      if (wardrobeForRequest == null &&
          (moduleContext == 'style' || moduleContext == 'wardrobe')) {
        try {
          wardrobeForRequest = await _appwriteService.getWardrobeItems();
        } catch (_) {
          wardrobeForRequest = const [];
        }
      }
      final safeWardrobePayload = (wardrobeForRequest ?? []).map((item) {
        final copy = Map<String, dynamic>.from(item);
        return copy;
      }).toList();
      final historyForRequest = List<Map<String, String>>.from(chatHistory);
      if (historyForRequest.isEmpty ||
          historyForRequest.last['role'] != 'user' ||
          historyForRequest.last['content'] != query) {
        historyForRequest.add({'role': 'user', 'content': query});
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/text'),
            headers: await _authHeaders(),
            body: jsonEncode({
              'messages': historyForRequest,
              'language': 'en',
              'current_memory': _memoryPayload(currentMemory),
              'user_profile': {...?userProfile, 'user_id': authedUserId},
              'user_id': authedUserId,
              'module_context': moduleContext,
              // Chat style boards render from live wardrobe item cards.
              // Requesting base64 board renders here makes /api/text much
              // heavier and can leave the UI feeling stuck on slow networks.
              'include_base64': false,
              if (styleAction != null && styleAction.trim().isNotEmpty)
                'style_action': styleAction.trim(),
              if (excludeStyleSignatures.isNotEmpty)
                'exclude_style_signatures': excludeStyleSignatures,
              if (requestedBoardCount != null)
                'requested_board_count': requestedBoardCount,
              if (safeWardrobePayload.isNotEmpty)
                'wardrobe': safeWardrobePayload,
            }),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode == 200) {
        final data = await compute(_parseJsonMap, response.body);

        if (data['requires_wardrobe'] == true && !isRetry) {
          final items = await _appwriteService.getWardrobeItems();
          return sendChatQuery(
            query,
            authedUserId,
            chatHistory,
            currentMemory,
            isRetry: true,
            fetchedWardrobe: items,
            moduleContext: moduleContext,
            userProfile: userProfile,
            styleAction: styleAction,
            excludeStyleSignatures: excludeStyleSignatures,
            requestedBoardCount: requestedBoardCount,
          );
        }

        return _normalizeChatResponse(data);
      }

      throw Exception(
        'Failed to get AI response: ${response.statusCode} ${response.body}',
      );
    } catch (e) {
      debugPrint('Backend Error: $e');
      final fallback = _demoChatFallback(query, moduleContext);
      return {
        'error': 'Backend fallback: $e',
        'message': {'role': 'assistant', 'content': fallback},
        'message_text': fallback,
        'chips': [
          {'label': 'Try again', 'value': query},
        ],
        'type': 'retry',
        'meta': {'used_local_fallback': true},
      };
    }
  }

  // Wardrobe vision and background removal.
  Future<String?> removeBackground(String base64Image) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/background/remove-bg'),
            headers: await _authHeaders(),
            body: jsonEncode({'image_base64': base64Image}),
          )
          .timeout(const Duration(seconds: 45));
      if (response.statusCode == 200) {
        final data = await compute(_parseJsonMap, response.body);
        return data['image_base64'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('Background removal error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> analyzeImage(
    Uint8List imageBytes, {
    bool autoSave = false,
    bool saveDuplicates = false,
  }) async {
    try {
      final base64String = await compute(_encodeBytes, imageBytes);
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/wardrobe/capture/analyze'),
            headers: await _authHeaders(),
            body: jsonEncode({
              'user_id': await _currentUserId(),
              'image_base64': base64String,
              'auto_save': autoSave,
              'save_duplicates': saveDuplicates,
            }),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode == 200) {
        final data = await compute(_parseJsonMap, response.body);
        debugPrint(
          'Analyze API ok: items=${(data['items'] as List?)?.length ?? 0}',
        );
        return data;
      }

      debugPrint(
        'Analyze API failed: ${response.statusCode} - ${response.body}',
      );
      throw BackendRequestException(
        'Scan API ${response.statusCode}: ${response.body}',
      );
    } catch (e) {
  final msg = e.toString().toLowerCase();

  final isTimeout =
      msg.contains('timeoutexception') ||
      msg.contains('future not completed') ||
      msg.contains('timed out');

  if (isTimeout) {
    return {
      'status': 'manual_review',
      'needs_review': true,
      'items': [
        {
          'id': 'manual_review',
          'name': 'Uploaded item',
          'category': 'Accessories',
          'subcategory': 'Eyewear',
          'editable': true,
          'needs_review': true,
        }
      ],
      'message': 'Review labels before saving.',
    };
  }

  throw BackendRequestException('Scan request failed: $e');
}
  }

  Future<Map<String, dynamic>?> analyzeImagesBatch(
    List<Uint8List> images, {
    bool autoSave = false,
    bool saveDuplicates = false,
  }) async {
    if (images.isEmpty) return null;
    try {
      final encoded = await Future.wait(
        images.take(6).map((bytes) => compute(_encodeBytes, bytes)),
      );
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/wardrobe/capture/analyze-batch'),
            headers: await _authHeaders(),
            body: jsonEncode({
              'user_id': await _currentUserId(),
              'image_base64s': encoded,
              'auto_save': autoSave,
              'save_duplicates': saveDuplicates,
            }),
          )
          .timeout(const Duration(seconds: 150));

      if (response.statusCode == 200) {
        final data = await compute(_parseJsonMap, response.body);
        debugPrint(
          'Analyze batch API ok: items=${(data['items'] as List?)?.length ?? 0}',
        );
        return data;
      }

      debugPrint(
        'Analyze batch API failed: ${response.statusCode} - ${response.body}',
      );
      throw BackendRequestException(
        'Batch scan API ${response.statusCode}: ${response.body}',
      );
    } catch (e) {
      debugPrint('Garment batch analysis error: $e');
      throw BackendRequestException('Batch scan request failed: $e');
    }
  }

  Future<Map<String, dynamic>?> saveWardrobeLabels(
    List<Map<String, dynamic>> detectedItems,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/wardrobe/capture/save-selected'),
            headers: await _authHeaders(),
            body: jsonEncode({
              'user_id': await _currentUserId(),
              'selected_item_ids': detectedItems
                  .map((item) => item['item_id']?.toString() ?? '')
                  .where((id) => id.isNotEmpty)
                  .toList(),
              'detected_items': detectedItems,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return await compute(_parseJsonMap, response.body);
      }

      debugPrint(
        'Wardrobe label save failed: ${response.statusCode} - ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('Wardrobe label save error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> deleteWardrobeItems(
    List<Map<String, dynamic>> items, {
    bool deleteR2 = true,
  }) async {
    try {
      final ids = items
          .map(
            (item) =>
                item[r'$id'] ??
                item['document_id'] ??
                item['documentId'] ??
                item['id'] ??
                item['item_id'] ??
                item['itemId'] ??
                '',
          )
          .map((id) => id.toString().trim())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (ids.isEmpty) {
        return {
          'success': false,
          'error': 'No wardrobe document id found for delete.',
        };
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/wardrobe/capture/delete-selected'),
            headers: await _authHeaders(),
            body: jsonEncode({
              'user_id': await _currentUserId(),
              'item_ids': ids,
              'items': items,
              'delete_r2': deleteR2,
            }),
          )
          .timeout(const Duration(seconds: 35));

      if (response.statusCode == 200) {
        return await compute(_parseJsonMap, response.body);
      }

      debugPrint(
        'Wardrobe delete failed: ${response.statusCode} ${response.body}',
      );

      return {
        'success': false,
        'status': response.statusCode,
        'error': response.body,
      };
    } catch (e) {
      debugPrint('Wardrobe delete error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Calendar events persisted through AHVI backend/Appwrite.
  Future<List<Map<String, dynamic>>> getCalendarEvents({
    DateTime? startTime,
    DateTime? endTime,
    int limit = 200,
  }) async {
    try {
      final params = <String, String>{
        'limit': limit.toString(),
        if (startTime != null) 'start_time': startTime.toIso8601String(),
        if (endTime != null) 'end_time': endTime.toIso8601String(),
      };

      final uri = Uri.parse(
        '$baseUrl/api/calendar/events',
      ).replace(queryParameters: params);

      final response = await http
          .get(uri, headers: await _authHeaders())
          .timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = await compute(_parseJsonMap, response.body);
        return List<Map<String, dynamic>>.from(
          data['events'] as List? ?? const [],
        );
      }

      debugPrint(
        'Calendar events load failed: ${response.statusCode} ${response.body}',
      );
      return <Map<String, dynamic>>[];
    } catch (e) {
      debugPrint('Calendar events load error: $e');
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> getTodayCalendarEvents({
    DateTime? date,
  }) async {
    try {
      final day = date ?? DateTime.now();
      final yyyy = day.year.toString().padLeft(4, '0');
      final mm = day.month.toString().padLeft(2, '0');
      final dd = day.day.toString().padLeft(2, '0');

      final uri = Uri.parse(
        '$baseUrl/api/calendar/today',
      ).replace(queryParameters: {'date': '$yyyy-$mm-$dd'});

      final response = await http
          .get(uri, headers: await _authHeaders())
          .timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = await compute(_parseJsonMap, response.body);
        return List<Map<String, dynamic>>.from(
          data['events'] as List? ?? const [],
        );
      }

      debugPrint(
        'Today calendar load failed: ${response.statusCode} ${response.body}',
      );
      return <Map<String, dynamic>>[];
    } catch (e) {
      debugPrint('Today calendar load error: $e');
      return <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>?> createCalendarEvent({
    required String title,
    required DateTime startTime,
    DateTime? endTime,
    String description = '',
    String timezone = 'Asia/Kolkata',
    String type = 'plan',
    String source = 'ahvi',
    String status = 'scheduled',
    String dressCode = '',
    String venueName = '',
    String venueAddress = '',
    int reminderMinutes = 30,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/calendar/events'),
            headers: await _authHeaders(),
            body: jsonEncode({
              'title': title,
              'description': description,
              'start_time': startTime.toIso8601String(),
              'end_time': endTime?.toIso8601String(),
              'timezone': timezone,
              'type': type,
              'source': source,
              'status': status,
              'dress_code': dressCode,
              'venue_name': venueName,
              'venue_address': venueAddress,
              'reminder_minutes': reminderMinutes,
              'metadata': metadata ?? <String, dynamic>{},
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = await compute(_parseJsonMap, response.body);
        return Map<String, dynamic>.from(data['event'] as Map? ?? data);
      }

      debugPrint(
        'Calendar event create failed: ${response.statusCode} ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('Calendar event create error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> getTodayWorkout() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/workouts/today'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return await compute(_parseJsonMap, response.body);
      }

      debugPrint(
        'Today workout load failed: ${response.statusCode} ${response.body}',
      );
      return <String, dynamic>{};
    } catch (e) {
      debugPrint('Today workout load error: $e');
      return <String, dynamic>{};
    }
  }

  Future<Map<String, dynamic>> recommendWorkout({
    String goal = 'general_fitness',
    int duration = 20,
    String location = 'home',
    String equipment = 'none',
    String? constraint,
    Map<String, dynamic>? weather,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/workouts/recommend'),
            headers: await _authHeaders(),
            body: jsonEncode({
              'goal': goal,
              'duration': duration,
              'location': location,
              'equipment': equipment,
              if (constraint != null && constraint.trim().isNotEmpty)
                'constraint': constraint,
              if (weather != null) 'weather': weather,
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return await compute(_parseJsonMap, response.body);
      }

      debugPrint(
        'Workout recommendation failed: ${response.statusCode} ${response.body}',
      );
      return <String, dynamic>{};
    } catch (e) {
      debugPrint('Workout recommendation error: $e');
      return <String, dynamic>{};
    }
  }

  Future<bool> completeWorkout(
    String workoutId, {
    String? difficultyFeedback,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/workouts/complete'),
            headers: await _authHeaders(),
            body: jsonEncode({
              'workout_id': workoutId,
              'completed': true,
              if (difficultyFeedback != null)
                'difficulty_feedback': difficultyFeedback,
            }),
          )
          .timeout(const Duration(seconds: 20));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Workout complete error: $e');
      return false;
    }
  }

  Future<bool> skipWorkout(String workoutId, {String? reason}) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/workouts/skip'),
            headers: await _authHeaders(),
            body: jsonEncode({
              'workout_id': workoutId,
              'skipped': true,
              if (reason != null) 'reason': reason,
            }),
          )
          .timeout(const Duration(seconds: 20));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Workout skip error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> updateCalendarEvent(
    String eventId,
    Map<String, dynamic> fields,
  ) async {
    try {
      final response = await http
          .patch(
            Uri.parse('$baseUrl/api/calendar/events/$eventId'),
            headers: await _authHeaders(),
            body: jsonEncode(fields),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = await compute(_parseJsonMap, response.body);
        return Map<String, dynamic>.from(data['event'] as Map? ?? data);
      }

      debugPrint(
        'Calendar event update failed: ${response.statusCode} ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('Calendar event update error: $e');
      return null;
    }
  }

  Future<bool> deleteCalendarEvent(String eventId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/calendar/events/$eventId'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 30));

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Calendar event delete error: $e');
      return false;
    }
  }

  Future<bool> scheduleReminder({
    required String eventId,
    required String message,
    required DateTime sendAt,
    String source = 'app',
    String priority = 'light',
    int offsetMinutes = 0,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/notifications/reminders/schedule'),
        headers: await _authHeaders(),
        body: jsonEncode({
          'eventId': eventId,
          'source': source,
          'reminders': [
            {
              'sendAtISO': sendAt.toUtc().toIso8601String(),
              'message': message,
              'priority': priority,
              'offsetMinutes': offsetMinutes,
            },
          ],
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Reminder schedule error: $e');
      return false;
    }
  }
}
