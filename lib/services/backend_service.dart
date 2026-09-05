import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:myapp/config/env.dart';
import 'package:myapp/models/calendar_actions.dart';
import 'package:myapp/models/calendar_event_record.dart';
import 'package:myapp/models/home_today_summary.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/services/ahvi_response_policy.dart';
import 'package:myapp/services/ahvi_style_diagnostics.dart';
import 'package:myapp/services/location_context_service.dart';
import 'package:myapp/util/safe_text.dart';

Map<String, dynamic> _parseJsonMap(String payload) => Map<String, dynamic>.from(
  sanitizeUtf16Deep(jsonDecode(payload) as Map) as Map,
);

String _encodeBytes(Uint8List bytes) => base64Encode(bytes);

String canonicalModuleChatDomain(String domain, {bool plannerRequest = false}) {
  if (plannerRequest) return 'planner';
  final normalized = domain.trim().toLowerCase();
  // Generic planner aliases must land on the backend-canonical 'planner'
  // module (which _normalize_module_name accepts). 'prepare' previously
  // mapped to 'plan' and 'organize' fell through to 'chat' — both downgraded
  // the module and produced generic responses.
  const plannerAliases = {'prepare', 'plan', 'planning'};
  return plannerAliases.contains(normalized) ? 'planner' : normalized;
}

/// Home "Prep & Plan" CTA contract. Always invokes the planner shell with the
/// structured Tomorrow Prep calendar action; adaptive recommendation text is
/// non-routing context so it cannot deflect the request to Style, Diet, or
/// Fitness.
class PrepPlanRequest {
  const PrepPlanRequest(this.module, this.message, this.context);
  final String module;
  final String message;
  final Map<String, dynamic> context;
}

PrepPlanRequest prepPlanCardRequest(String adaptiveHint, {DateTime? now}) {
  final calendarRequest = calendarActionRequest(
    CalendarQuickAction.prepTomorrow,
    occasion: '',
    now: now,
  );
  return PrepPlanRequest('planner', calendarRequest.message, {
    ...calendarRequest.context,
    'context_hint': adaptiveHint,
    'source': 'home_prep_plan_card',
    'requested_action': CalendarQuickAction.prepTomorrow.id,
    'surface': 'home_prepare',
  });
}

Object? _jsonSafe(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is DateTime) {
    return value.toUtc().toIso8601String();
  }
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), _jsonSafe(val)));
  }
  if (value is Iterable) {
    return value.map(_jsonSafe).toList();
  }
  return value.toString();
}

@visibleForTesting
Map<String, dynamic> enrichBackendPayloadWithLocation(
  Map<String, dynamic> payload,
  Map<String, dynamic> locationContext, {
  bool includeContext = false,
  bool includeUserProfile = false,
}) {
  final enriched = Map<String, dynamic>.from(payload)
    ..['location_context'] = Map<String, dynamic>.from(locationContext);
  if (!enriched.containsKey('location')) {
    enriched['location'] = Map<String, dynamic>.from(locationContext);
  }
  enriched['timezone'] = locationContext['timezone'];
  if (includeContext) {
    for (final key in ['context', 'context_data']) {
      if (key == 'context' || enriched.containsKey(key)) {
        enriched[key] =
            Map<String, dynamic>.from(
                enriched[key] as Map? ?? const <String, dynamic>{},
              )
              ..['location'] = Map<String, dynamic>.from(locationContext)
              ..['location_context'] = Map<String, dynamic>.from(
                locationContext,
              )
              ..['timezone'] = locationContext['timezone'];
      }
    }
  }
  if (includeUserProfile) {
    enriched['user_profile'] =
        Map<String, dynamic>.from(
            enriched['user_profile'] as Map? ?? const <String, dynamic>{},
          )
          ..['location'] = Map<String, dynamic>.from(locationContext)
          ..['location_context'] = Map<String, dynamic>.from(locationContext);
  }
  return enriched;
}

class BackendRequestException implements Exception {
  final String message;
  const BackendRequestException(this.message);

  @override
  String toString() => message;
}

const int moduleChatHistoryLimit = 20;

@visibleForTesting
List<Map<String, String>> buildModuleChatHistoryForRequest(
  List<Map<String, String>> chatHistory,
  String query,
) {
  final history = List<Map<String, String>>.from(chatHistory);
  if (history.isEmpty ||
      history.last['role'] != 'user' ||
      history.last['content'] != query) {
    history.add({'role': 'user', 'content': query});
  }
  if (history.length <= moduleChatHistoryLimit) return history;
  return history.sublist(history.length - moduleChatHistoryLimit);
}

bool shouldAppendModuleChatResponseToSemanticHistory(
  Map<String, dynamic> response,
) {
  final meta = response['meta'];
  return meta is! Map || meta['used_local_fallback'] != true;
}

/// Honest, debuggable fallback copy. Replaces the previous
/// "AHVI is still styling/preparing this" placeholders that hid real
/// HTTP / timeout / parser failures.
///
/// [reason] should describe the actual failure: 'timeout', 'unauthorized',
/// 'server_error', 'parse_error', 'empty_response', or 'network'.
String _honestChatFallback(String reason, String moduleContext) {
  switch (reason) {
    case 'unauthorized':
      return 'Your session expired. Please log in again.';
    case 'timeout':
      return "AHVI couldn't respond in time. Please try again.";
    case 'parse_error':
      return "AHVI received an unexpected response. We're looking into it — please try again.";
    case 'server_error':
      return "AHVI's server hit an error. Please try again in a moment.";
    case 'empty_response':
      return "AHVI didn't return a result for this. Try rephrasing or try again.";
    case 'network':
    default:
      return "AHVI had trouble reaching the styling service. Please try again.";
  }
}

/// Structured log emitter for network-class failures so we can read
/// endpoint / status / exception type from `adb logcat` without changing
/// the user-facing string. Call from any catch block that maps to
/// _honestChatFallback('network', ...).
void logNetworkFailure({
  required String endpoint,
  required Object error,
  int? statusCode,
  Duration? timeout,
  String? responseBody,
}) {
  final type = error.runtimeType.toString();
  final body = (responseBody ?? '').replaceAll('\n', ' | ');
  // ignore: avoid_print
  print(
    '👕 AHVI_NET_FAILURE endpoint=$endpoint status=$statusCode '
    'type=$type timeout_ms=${timeout?.inMilliseconds} '
    'err=${truncateSafeText(error.toString().replaceAll('\n', ' | '), 200)} '
    'body=${truncateSafeText(body, 200)}',
  );
}

class BackendService {
  final String baseUrl = Env.backendApiUrl;
  final AppwriteService _appwriteService;
  final LocationContextService _locationContextService;

  @visibleForTesting
  http.Client? debugHttpClient;

  @visibleForTesting
  Future<String> Function()? debugAuthenticatedUserIdProvider;

  @visibleForTesting
  Future<Map<String, String>> Function()? debugAuthHeadersProvider;

  BackendService({
    AppwriteService? appwriteService,
    LocationContextService? locationContextService,
  }) : _appwriteService = appwriteService ?? AppwriteService(),
       _locationContextService =
           locationContextService ??
           LocationContextService(
             appwriteService: appwriteService ?? AppwriteService(),
           ) {
    // Invalidate workout session cache whenever auth scope changes (logout,
    // login, registration). AppwriteService.clearUserCache() fires this slot
    // on all those paths, so the cache is never shared across users.
    _appwriteService.addSessionInvalidationListener(clearTodayWorkoutCache);
    _appwriteService.addSessionInvalidationListener(clearWeatherCache);
  }

  Future<Map<String, dynamic>> _locationContext(String userId) async {
    return _locationContextService.getLocationContext(
      userId: userId,
      requestIfDenied: false,
    );
  }

  // Canonical weather cache shared across every BackendService instance (Home
  // and Daily Wear each construct their own `BackendService()`, so this must
  // be static to actually be shared). Home and Daily Wear both call
  // getCurrentWeather() -- whichever resolves first populates this cache so
  // the other reuses the same reading instead of racing its own independent
  // network/location fetch and risking a spurious "unavailable".
  static const Duration _weatherFreshness = Duration(minutes: 10);
  static const Duration _weatherStaleLimit = Duration(hours: 2);
  static final Map<String, ({Map<String, dynamic> weather, DateTime capturedAt})>
  _weatherCache = {};

  @visibleForTesting
  static void clearWeatherCache() => _weatherCache.clear();

  Future<Map<String, dynamic>> getCurrentWeather() async {
    final userId = await _currentUserId();
    final now = DateTime.now();
    final cached = _weatherCache[userId];
    if (cached != null && now.difference(cached.capturedAt) < _weatherFreshness) {
      return cached.weather;
    }

    final result = await _fetchWeatherFromNetwork(userId);
    if (result['status'] == 'available') {
      _weatherCache[userId] = (weather: result, capturedAt: now);
      return result;
    }
    // Fetch failed or came back unavailable -- prefer a recent known-good
    // reading over a spurious "unavailable" rather than fabricating a value.
    if (cached != null && now.difference(cached.capturedAt) < _weatherStaleLimit) {
      return cached.weather;
    }
    return result;
  }

  Future<Map<String, dynamic>> _fetchWeatherFromNetwork(String userId) async {
    final location = await _locationContext(userId);
    final lat = location['lat'];
    final lon = location['lon'];
    if (lat is! num || lon is! num) {
      return const {
        'status': 'unavailable',
        'reason': 'weather_location_missing',
      };
    }
    try {
      final uri = Uri.parse('$baseUrl/api/weather').replace(
        queryParameters: {
          'latitude': lat.toString(),
          'longitude': lon.toString(),
        },
      );
      final response = await http
          .get(uri, headers: await _authHeaders())
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const {
          'status': 'unavailable',
          'reason': 'weather_provider_unavailable',
        };
      }
      return _parseJsonMap(response.body);
    } catch (_) {
      return const {
        'status': 'unavailable',
        'reason': 'weather_provider_unavailable',
      };
    }
  }

  Future<Map<String, dynamic>> shuffleStyleBoard({
    required String boardId,
    required Map<String, dynamic> payload,
  }) async {
    final endpoint =
        '/api/style-boards/${Uri.encodeComponent(boardId)}/shuffle';
    final body = Map<String, dynamic>.from(payload)
      ..['user_id'] = await _currentUserId();
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl$endpoint'),
            headers: await _authHeaders(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      Map<String, dynamic> data;
      try {
        data = _parseJsonMap(response.body);
      } catch (_) {
        throw const BackendRequestException('Malformed style board response');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = data['detail'];
        if (detail is Map) return {'success': false, 'error': detail};
        throw BackendRequestException(
          'Style board request failed (${response.statusCode})',
        );
      }
      return data;
    } on TimeoutException {
      throw const BackendRequestException('Style board request timed out');
    }
  }

  Future<String> _currentUserId() async {
    final debugUserId = debugAuthenticatedUserIdProvider;
    if (debugUserId != null) return debugUserId();
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
    final debugHeaders = debugAuthHeadersProvider;
    if (debugHeaders != null) return debugHeaders();
    final jwt = await _appwriteService.account.createJWT();
    final token = jwt.jwt;
    if (token.isEmpty) throw Exception('Could not create Appwrite JWT');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Records a "wear today" event so AHVI learns what the user actually wears.
  /// Fire-and-forget friendly; returns true on success. Skips silently when
  /// there are no real item ids to record.
  Future<bool> wearToday({
    required List<String> itemIds,
    String boardId = '',
    String occasion = '',
  }) async {
    final ids = itemIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) return false;
    try {
      final userId = await _currentUserId();
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/style/wear-today'),
            headers: await _authHeaders(),
            body: jsonEncode({
              'user_id': userId,
              'board_id': boardId,
              'item_ids': ids,
              'occasion': occasion,
            }),
          )
          .timeout(const Duration(seconds: 20));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getDailyBoard() async {
    final response = await sendModuleChat(
      domain: 'style',
      // Deliberately avoids "wardrobe-first" (a compound "wardrobe" phrase
      // the backend's owned-item-mention resolver can misparse as a named
      // garment -- see services.style_item_contract._extract_my_phrases).
      // The resolver fix is the real defense; this wording is belt-and-
      // braces so a future backend regression fails softer for this call.
      message: "What should I wear today using my wardrobe?",
      context: const {'surface': 'daily_wear', 'request': 'daily_board'},
    );
    final rawData = response['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};
    final cards =
        data['cards'] ??
        data['rendered_boards'] ??
        response['cards'] ??
        response['style_boards'] ??
        const <dynamic>[];
    return {
      ...response,
      'data': {...data, 'cards': cards},
    };
  }

  // --- ACCOUNT & PROFILE ---
  Future<void> deleteAccount(String userId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/user/delete-account'),
      headers: await _authHeaders(),
      body: jsonEncode({"user_id": userId}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete account');
    }
  }

  Future<void> updateProfile(
    String userId, {
    String? name,
    String? gender,
    String? skinTone,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/user/update-profile'),
      headers: await _authHeaders(),
      body: jsonEncode({
        "user_id": userId,
        if (name != null) "name": name,
        if (gender != null) "gender": gender,
        if (skinTone != null) "skin_tone": skinTone,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update profile');
    }
  }

  // --- FAVORITES ---
  Future<void> toggleGarmentFavorite(
    String userId,
    String itemId,
    bool isLiked,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/wardrobe/favorite'),
      headers: await _authHeaders(),
      body: jsonEncode({
        "user_id": userId,
        "item_id": itemId,
        "is_liked": isLiked,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to sync favorite status');
    }
  }

  Object _memoryPayload(
    String currentMemory, [
    Map<String, dynamic>? lastStyleContext,
  ]) {
    final out = <String, dynamic>{};
    final trimmed = currentMemory.trim();
    if (trimmed.isNotEmpty) out['summary'] = trimmed;
    if (lastStyleContext != null && lastStyleContext.isNotEmpty) {
      out['last_style_context'] = lastStyleContext;
    }
    return out;
  }

  String _messageText(Map<String, dynamic> data) {
    final message = data['message'];
    if (message is String) return message;
    if (message is Map) return (message['content'] ?? '').toString();
    final nestedData = data['data'];
    if (nestedData is Map && nestedData['message'] != null) {
      return nestedData['message'].toString();
    }
    return data['response']?.toString() ??
        "I'm having trouble thinking right now.";
  }

  Map<String, dynamic> _normalizeChatResponse(Map<String, dynamic> data) {
    var cleanText = _messageText(data);
    var extractedChips = filterDeprecatedVisibleStyleActions(data['chips']);
    final quickActions = filterDeprecatedVisibleStyleActions(
      data['quick_actions'],
    );
    if (quickActions.isNotEmpty) {
      extractedChips = quickActions;
    }
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
      'quick_actions': quickActions.isNotEmpty ? quickActions : extractedChips,
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
    // Style-session context handoff. When the user taps a chip /
    // button / retry, the FE must attach these so the backend never
    // sees a bare label ("Next best options", "Casual beach walk",
    // "Try again") without the originating prompt.
    String? action,
    String? clarification,
    String? sessionId,
    String? previousPrompt,
    String? resolvedPrompt,
    String? currentLookId,
    Map<String, dynamic>? styleContext,
    Map<String, dynamic>? styleState,
    // Persisted style-pairing session (anchor/route/persona). Echoed into
    // current_memory so backend follow-ups keep the anchor.
    Map<String, dynamic>? lastStyleContext,
    bool showClosestOption = false,
    bool allowClosestOption = false,
    bool closest = false,
    bool useWardrobe = false,
    bool wardrobeFirst = false,
    String? assetPolicy,
    bool allowGenericAssetsInMainBoard = true,
    // P0: client-generated correlation id echoed by backend for
    // late-response rejection. Optional so old callers still work.
    String? requestId,
  }) async {
    final startedAt = DateTime.now();
    final diagnosticCorrelationId = AhviStyleDiagnostics.nextCorrelationId();
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

      final extraContext = <String, dynamic>{
        if (action != null && action.trim().isNotEmpty) 'action': action.trim(),
        if (clarification != null && clarification.trim().isNotEmpty)
          'clarification': clarification.trim(),
        if (sessionId != null && sessionId.trim().isNotEmpty)
          'session_id': sessionId.trim(),
        if (previousPrompt != null && previousPrompt.trim().isNotEmpty)
          'previous_prompt': previousPrompt.trim(),
        if (resolvedPrompt != null && resolvedPrompt.trim().isNotEmpty)
          'resolved_prompt': resolvedPrompt.trim(),
        if (currentLookId != null && currentLookId.trim().isNotEmpty)
          'current_look_id': currentLookId.trim(),
        if (styleContext != null && styleContext.isNotEmpty)
          'style_context': styleContext,
        if (styleState != null && styleState.isNotEmpty)
          'style_state': styleState,
      };

      final requestPayload = enrichBackendPayloadWithLocation(
        {
          'messages': historyForRequest,
          'language': 'en',
          'current_memory': _memoryPayload(currentMemory, lastStyleContext),
          'user_profile': {...?userProfile, 'user_id': authedUserId},
          'user_id': authedUserId,
          if (requestId != null && requestId.isNotEmpty)
            'request_id': requestId,
          ...extraContext,
          'module_context': moduleContext,
          // Chat style boards render from live wardrobe item cards.
          // Requesting base64 board renders here makes /api/text much
          // heavier and can leave the UI feeling stuck on slow networks.
          'include_base64': false,
          if (styleAction != null && styleAction.trim().isNotEmpty)
            'style_action': styleAction.trim(),
          if (showClosestOption) 'show_closest_option': true,
          if (allowClosestOption) 'allow_closest_option': true,
          if (closest) 'closest': true,
          if (useWardrobe) 'use_wardrobe': true,
          if (wardrobeFirst) 'wardrobe_first': true,
          if (assetPolicy != null) 'asset_policy': assetPolicy,
          if (!allowGenericAssetsInMainBoard)
            'allow_generic_assets_in_main_board': false,
          if (excludeStyleSignatures.isNotEmpty)
            'exclude_style_signatures': excludeStyleSignatures,
          if (requestedBoardCount != null)
            'requested_board_count': requestedBoardCount,
          if (safeWardrobePayload.isNotEmpty) 'wardrobe': safeWardrobePayload,
        },
        await _locationContext(authedUserId),
        includeUserProfile: true,
      );
      debugPrint(
        'AHVI_STYLE_REQUEST correlation_id=$diagnosticCorrelationId '
        'endpoint=/api/text module=${moduleContext.trim().toLowerCase()} '
        'action=${(action ?? styleAction ?? 'none').trim().toLowerCase()}',
      );

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/text'),
            headers: await _authHeaders(),
            body: jsonEncode(requestPayload),
          )
          .timeout(const Duration(seconds: 120));

      final elapsedSec =
          DateTime.now().difference(startedAt).inMilliseconds / 1000;

      if (response.statusCode == 200) {
        debugPrint('style_chat.status_code=${response.statusCode}');
        Map<String, dynamic> data;
        try {
          data = await compute(_parseJsonMap, response.body);
        } catch (parseErr) {
          debugPrint(
            'AHVI_BACKEND_PARSE_ERR endpoint=/api/text '
            'error_type=${parseErr.runtimeType} '
            'body_len=${response.body.length}',
          );
          rethrow;
        }
        AhviStyleDiagnostics.logResponse(
          correlationId: diagnosticCorrelationId,
          response: data,
          selectedAlias: 'backend_unselected',
          selectedRawCount: 0,
          parserInputCount: 0,
          parserAcceptedCount: 0,
          policyRejectedCount: 0,
          invalidContractCount: 0,
          dedupDroppedCount: 0,
          finalRenderedCount: 0,
          staleResponseDiscardedCount: 0,
        );

        if (data['ok'] == false || data['success'] == false) {
          final err = data['error'];
          final code = err is Map ? (err['code'] ?? '').toString() : '';
          final msg = err is Map ? (err['message'] ?? '').toString() : '';
          debugPrint(
            'AHVI_BACKEND_STRUCTURED_ERROR endpoint=/api/text code=$code message=$msg',
          );
          return _normalizeChatResponse(data);
        }

        // Visibility for the intermittent "AHVI is still styling this" toast.
        debugPrint(
          'AHVI_BACKEND_OK endpoint=/api/text '
          'type=${data['type']} '
          'success=${data['success']} '
          'has_message=${data['message'] != null || data['message_text'] != null} '
          'cards=${(data['cards'] as List?)?.length ?? 0} '
          'style_boards=${(data['style_boards'] as List?)?.length ?? 0} '
          'visual_directions=${(data['visual_directions'] as List?)?.length ?? ((data['data'] as Map?)?['visual_directions'] as List?)?.length ?? 0} '
          'rendered_boards=${((data['data'] as Map?)?['rendered_boards'] as List?)?.length ?? 0} '
          'chips=${(data['chips'] as List?)?.length ?? 0} '
          'requires_wardrobe=${data['requires_wardrobe']} '
          'body_len=${response.body.length}',
        );
        debugPrint(
          'AHVI_RESPONSE_TIME endpoint=/api/text seconds=${elapsedSec.toStringAsFixed(2)}',
        );

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
            action: action,
            clarification: clarification,
            sessionId: sessionId,
            previousPrompt: previousPrompt,
            resolvedPrompt: resolvedPrompt,
            currentLookId: currentLookId,
            styleContext: styleContext,
            styleState: styleState,
            lastStyleContext: lastStyleContext,
            excludeStyleSignatures: excludeStyleSignatures,
            requestedBoardCount: requestedBoardCount,
            showClosestOption: showClosestOption,
            allowClosestOption: allowClosestOption,
            closest: closest,
            useWardrobe: useWardrobe,
            wardrobeFirst: wardrobeFirst,
            assetPolicy: assetPolicy,
            allowGenericAssetsInMainBoard: allowGenericAssetsInMainBoard,
            requestId: requestId,
          );
        }

        try {
          return _normalizeChatResponse(data);
        } catch (normErr, normSt) {
          debugPrint('AHVI_NORMALIZE_ERR err=$normErr stack=$normSt');
          rethrow;
        }
      }

      debugPrint(
        'AHVI_BACKEND_FAIL endpoint=/api/text status=${response.statusCode}',
      );
      debugPrint('style_chat.status_code=${response.statusCode}');
      try {
        final data = await compute(_parseJsonMap, response.body);
        if (data['error'] != null || data['message'] != null) {
          return _normalizeChatResponse(data);
        }
      } catch (_) {}
      throw Exception('Failed to get AI response: ${response.statusCode}');
    } catch (e, st) {
      final failedAfter =
          DateTime.now().difference(startedAt).inMilliseconds / 1000;
      debugPrint(
        'AHVI_BACKEND_EXCEPTION endpoint=/api/text '
        'error_type=${e.runtimeType}',
      );
      debugPrint(
        'style_chat.exception_type=${e.runtimeType} endpoint=/api/text',
      );
      if (e is TimeoutException ||
          e.toString().toLowerCase().contains('timeout')) {
        debugPrint('style_chat.timeout endpoint=/api/text seconds=120');
      }
      debugPrint('AHVI_BACKEND_EXCEPTION stack_type=${st.runtimeType}');
      debugPrint(
        'AHVI_FAILURE_AFTER endpoint=/api/text seconds=${failedAfter.toStringAsFixed(2)}',
      );

      final errStr = e.toString().toLowerCase();
      String reason;
      if (e is TimeoutException || errStr.contains('timeout')) {
        reason = 'timeout';
      } else if (errStr.contains('401') || errStr.contains('unauthorized')) {
        reason = 'unauthorized';
      } else if (errStr.contains('5') && errStr.contains('failed to get')) {
        reason = 'server_error';
      } else if (errStr.contains('formatexception') ||
          errStr.contains('jsondecodeerror') ||
          errStr.contains('unexpected character') ||
          errStr.contains('parse')) {
        reason = 'parse_error';
      } else {
        reason = 'network';
      }

      final fallback = _honestChatFallback(reason, moduleContext);
      return {
        'error': 'Backend fallback ($reason)',
        'message': {'role': 'assistant', 'content': fallback},
        'message_text': fallback,
        'chips': [
          {'label': 'Try again', 'value': query},
        ],
        'type': reason == 'unauthorized' ? 'session_expired' : 'retry',
        'meta': {
          'used_local_fallback': true,
          'fallback_reason': reason,
          'failed_after_seconds': failedAfter,
        },
      };
    }
  }

  Future<Map<String, dynamic>> sendModuleChatQuery({
    required String module,
    required String query,
    required List<Map<String, String>> chatHistory,
    Map<String, dynamic> contextData = const {},
    Map<String, dynamic>? userProfile,
    Map<String, dynamic>? styleState,
  }) async {
    return sendModuleChat(
      domain: module,
      message: query,
      context: contextData,
      chatHistory: chatHistory,
      userProfile: userProfile,
      styleState: styleState,
    );
  }

  Future<Map<String, dynamic>> sendModuleChat({
    required String domain,
    required String message,
    Map<String, dynamic>? context,
    List<Map<String, String>> chatHistory = const [],
    Map<String, dynamic>? userProfile,
    Map<String, dynamic>? styleState,
    // P0: client-generated correlation id echoed by backend for late-response
    // rejection. Optional so old callers keep working.
    String? requestId,
  }) async {
    final module = canonicalModuleChatDomain(domain);
    final query = message.trim();
    final diagnosticCorrelationId = AhviStyleDiagnostics.nextCorrelationId();
    try {
      final authedUserId = await _currentUserId();
      if (query.isEmpty) {
        return {
          'message': {'role': 'assistant', 'content': ''},
          'message_text': '',
          'chips': const [],
          'type': 'module_response',
        };
      }
      final historyForRequest = buildModuleChatHistoryForRequest(
        chatHistory,
        query,
      );

      final moduleContext = <String, dynamic>{...?context};
      final needsWardrobe =
          (module == 'style' ||
              module == 'daily_wear' ||
              module == 'wardrobe') &&
          !moduleContext.containsKey('wardrobe');
      final wardrobeFuture = needsWardrobe
          ? _appwriteService.getWardrobeItems()
          : null;
      final locationFuture = _locationContext(authedUserId);
      final authHeadersFuture = _authHeaders();

      // Resolve the user's gender so the backend can gender-filter style
      // assets. /api/module-chat reads gender ONLY from the request
      // user_profile; without it target_gender=unknown and only unisex assets
      // pass, so the curated male/female catalog (and cutout boards) come back
      // empty. Prefer the caller-supplied profile, then the cached profile,
      // then a one-shot refresh.
      String resolvedGender =
          (userProfile?['gender'] ?? userProfile?['style_gender'] ?? '')
              .toString()
              .trim();
      if (resolvedGender.isEmpty) {
        resolvedGender =
            (_appwriteService.cachedUserProfileData?['gender'] ?? '')
                .toString()
                .trim();
      }
      if (resolvedGender.isEmpty) {
        try {
          final refreshed = await _appwriteService.refreshCurrentUserProfile();
          resolvedGender = (refreshed?['gender'] ?? '').toString().trim();
        } catch (_) {
          // Non-fatal: fall back to ungendered request.
        }
      }

      if (wardrobeFuture != null) {
        try {
          moduleContext['wardrobe'] = await wardrobeFuture;
        } catch (_) {
          moduleContext['wardrobe'] = const <dynamic>[];
        }
      }

      final moduleStarted = DateTime.now();
      final modulePayload = enrichBackendPayloadWithLocation(
        {
          'domain': module,
          'module': module,
          'message': query,
          'history': historyForRequest,
          'context': moduleContext,
          'context_data': moduleContext,
          if (styleState != null && styleState.isNotEmpty)
            'style_state': styleState,
          if (requestId != null && requestId.isNotEmpty)
            'request_id': requestId,
          'user_profile': {
            ...?userProfile,
            if (resolvedGender.isNotEmpty) 'gender': resolvedGender,
            if (resolvedGender.isNotEmpty) 'style_gender': resolvedGender,
            'user_id': authedUserId,
          },
        },
        await locationFuture,
        includeContext: true,
        includeUserProfile: true,
      );
      debugPrint(
        'AHVI_STYLE_REQUEST correlation_id=$diagnosticCorrelationId '
        'endpoint=/api/module-chat module=$module action=none',
      );
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/module-chat'),
            headers: await authHeadersFuture,
            body: jsonEncode(_jsonSafe(modulePayload)),
          )
          // Backend's chat_completion has a 45s budget. Give the network +
          // serialization 30s of headroom so the frontend never wins the race
          // and shows 'AHVI couldn't respond in time' while the backend is
          // still happily streaming back a perfectly good answer.
          .timeout(const Duration(seconds: 75));

      final moduleElapsed =
          DateTime.now().difference(moduleStarted).inMilliseconds / 1000;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('style_chat.status_code=${response.statusCode}');
        final data = await compute(_parseJsonMap, response.body);
        AhviStyleDiagnostics.logResponse(
          correlationId: diagnosticCorrelationId,
          response: data,
          selectedAlias: 'module_unselected',
          selectedRawCount: 0,
          parserInputCount: 0,
          parserAcceptedCount: 0,
          policyRejectedCount: 0,
          invalidContractCount: 0,
          dedupDroppedCount: 0,
          finalRenderedCount: 0,
          staleResponseDiscardedCount: 0,
          promptCategory: module,
        );
        final text = _messageText(data);
        debugPrint(
          'AHVI_MODULE_CHAT_OK module=$module seconds=${moduleElapsed.toStringAsFixed(2)} '
          'text_len=${text.length} status=${response.statusCode}',
        );
        return _normalizeChatResponse({
          ...data,
          'message': {'role': 'assistant', 'content': text},
          'message_text': text,
          'chips': data['chips'] ?? const [],
          'quick_actions': data['quick_actions'] ?? data['chips'] ?? const [],
        });
      }

      debugPrint(
        'AHVI_BACKEND_FAIL endpoint=/api/module-chat module=$module '
        'status=${response.statusCode} seconds=${moduleElapsed.toStringAsFixed(2)}',
      );
      debugPrint('style_chat.status_code=${response.statusCode}');
      throw Exception('Failed module chat: ${response.statusCode}');
    } catch (e, st) {
      debugPrint(
        'AHVI_BACKEND_EXCEPTION endpoint=/api/module-chat '
        'error_type=${e.runtimeType}',
      );
      debugPrint(
        'style_chat.exception_type=${e.runtimeType} endpoint=/api/module-chat',
      );
      if (e is TimeoutException ||
          e.toString().toLowerCase().contains('timeout')) {
        debugPrint('style_chat.timeout endpoint=/api/module-chat seconds=75');
      }
      debugPrint('AHVI_BACKEND_EXCEPTION stack_type=${st.runtimeType}');

      final errStr = e.toString().toLowerCase();
      String reason;
      if (e is TimeoutException || errStr.contains('timeout')) {
        reason = 'timeout';
      } else if (errStr.contains('401') || errStr.contains('unauthorized')) {
        reason = 'unauthorized';
      } else if (errStr.contains('parse') ||
          errStr.contains('formatexception')) {
        reason = 'parse_error';
      } else {
        reason = 'network';
      }

      final fallback = _honestChatFallback(reason, module);
      return {
        'error': 'Backend module chat failed ($reason)',
        'message': {'role': 'assistant', 'content': fallback},
        'message_text': fallback,
        'chips': [
          {'label': 'Try again', 'value': query},
        ],
        'type': reason == 'unauthorized' ? 'session_expired' : 'retry',
        'meta': {'used_local_fallback': true, 'fallback_reason': reason},
      };
    }
  }

  /// Fire-and-forget board feedback for the unified style card's
  /// Like / Dislike (and Save / Shuffle / Share) actions. POSTs the backend
  /// feedback endpoint; failures are swallowed so the UI never blocks on it.
  /// This is also the training signal for the adaptive stylist brain.
  Future<void> sendBoardFeedback({
    required String action,
    required Map<String, dynamic> board,
  }) async {
    try {
      final userId = await _currentUserId();
      await http
          .post(
            Uri.parse('$baseUrl/api/feedback/board'),
            headers: await _authHeaders(),
            body: jsonEncode({
              'user_id': userId,
              'action': action,
              'board_payload': board,
            }),
          )
          .timeout(const Duration(seconds: 12));
      debugPrint('AHVI_BOARD_FEEDBACK_SENT action=$action');
    } catch (e) {
      debugPrint('AHVI_BOARD_FEEDBACK_FAIL action=$action error=$e');
    }
  }

  /// Bill receipt OCR. Sends a base64 image to the backend's vision
  /// pipeline; returns the extracted fields (store/amount/date/category/
  /// items/currency) so the Bills "AI Autofill" sheet can populate.
  Future<Map<String, dynamic>?> scanBill(Uint8List imageBytes) async {
    try {
      final base64String = await compute(_encodeBytes, imageBytes);
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/bills/scan'),
            headers: await _authHeaders(),
            body: jsonEncode({'image_base64': base64String}),
          )
          .timeout(const Duration(seconds: 90));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = await compute(_parseJsonMap, response.body);
        final extracted = data['extracted'];
        if (extracted is Map) {
          return Map<String, dynamic>.from(extracted);
        }
        return null;
      }
      debugPrint('Bill scan failed: ${response.statusCode} ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Bill scan error: $e');
      return null;
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
          // Vision enrichment runs 70-150s server-side; keep headroom.
          .timeout(const Duration(seconds: 180));

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
      debugPrint('Garment analysis error: $e');
      throw BackendRequestException('Scan request failed: $e');
    }
  }

  Future<Map<String, dynamic>?> findSimilarByImage(
    Uint8List imageBytes, {
    String filename = 'ahvi-lens.jpg',
  }) async {
    try {
      final headers = await _authHeaders();
      headers.remove('Content-Type');
      final request =
          http.MultipartRequest(
              'POST',
              Uri.parse('$baseUrl/api/lens/find-similar'),
            )
            ..headers.addAll(headers)
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                imageBytes,
                filename: filename,
              ),
            );
      final streamed = await request.send().timeout(
        const Duration(seconds: 45),
      );
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200) {
        return await compute(_parseJsonMap, response.body);
      }
      debugPrint(
        'Find similar failed: ${response.statusCode} ${response.body}',
      );
      return {
        'success': false,
        'message': 'Could not find similar products yet.',
        'matches': const [],
      };
    } catch (e) {
      debugPrint('Find similar error: $e');
      return {
        'success': false,
        'message': 'Could not find similar products yet.',
        'matches': const [],
      };
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
          // Batch vision enrichment runs 160-220s server-side; keep headroom.
          .timeout(const Duration(seconds: 240));

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
      final approvedItems = detectedItems
          .where((item) {
            final status =
                (item['validation_status'] ?? item['validationStatus'] ?? 'ok')
                    .toString()
                    .trim()
                    .toLowerCase();
            return status.isEmpty || status == 'ok';
          })
          .toList(growable: false);
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/wardrobe/capture/save-selected'),
            headers: await _authHeaders(),
            body: jsonEncode({
              'user_id': await _currentUserId(),
              'selected_item_ids': approvedItems
                  .map((item) => item['item_id']?.toString() ?? '')
                  .where((id) => id.isNotEmpty)
                  .toList(),
              'detected_items': approvedItems,
            }),
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final parsed = await compute(_parseJsonMap, response.body);
        invalidateWardrobeCacheAfterMutation();
        return parsed;
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

  void invalidateWardrobeCacheAfterMutation() {
    _appwriteService.invalidateWardrobeCache();
  }

  Future<Map<String, dynamic>?> createOrResumeUploadBatch({
    required String clientBatchRequestId,
    required int totalItems,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/wardrobe/upload-batches');
      final headers = await _authHeaders();
      final body = jsonEncode({
        'user_id': await _currentUserId(),
        'client_batch_request_id': clientBatchRequestId,
        'total_items': totalItems,
      });
      final client = debugHttpClient;
      final response = client == null
          ? await http
                .post(uri, headers: headers, body: body)
                .timeout(const Duration(seconds: 20))
          : await client
                .post(uri, headers: headers, body: body)
                .timeout(const Duration(seconds: 20));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return await compute(_parseJsonMap, response.body);
      }
      debugPrint(
        'Create upload batch failed: ${response.statusCode} - ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('Create upload batch error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> processUploadBatchItem({
    required String batchId,
    required String clientUploadItemId,
    required Uint8List imageBytes,
    Map<String, dynamic>? metadata,
    bool overrideDuplicate = false,
    Map<String, dynamic>? reviewedItem,
  }) async {
    try {
      final base64String = await compute(_encodeBytes, imageBytes);
      final uri = Uri.parse(
        '$baseUrl/api/wardrobe/upload-batches/${Uri.encodeComponent(batchId)}/items',
      );
      final headers = await _authHeaders();
      final body = jsonEncode({
        'user_id': await _currentUserId(),
        'client_upload_item_id': clientUploadItemId,
        'image_base64': base64String,
        if (metadata != null) 'metadata': metadata,
        'override_duplicate': overrideDuplicate,
        if (reviewedItem != null) 'reviewed_item': reviewedItem,
      });
      final client = debugHttpClient;
      final response = client == null
          ? await http
                .post(uri, headers: headers, body: body)
                .timeout(const Duration(seconds: 180))
          : await client
                .post(uri, headers: headers, body: body)
                .timeout(const Duration(seconds: 180));
      final parsed = await compute(_parseJsonMap, response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (parsed['status'] == 'ADDED_TO_WARDROBE') {
          invalidateWardrobeCacheAfterMutation();
        }
        return parsed;
      }
      debugPrint(
        'Upload batch item failed: ${response.statusCode} - ${response.body}',
      );
      return {
        'success': false,
        'status': 'FAILED',
        'error_code': 'REQUEST_FAILED',
        'reason': parsed['detail']?.toString() ?? 'request_failed',
      };
    } catch (e) {
      debugPrint('Upload batch item error: $e');
      return {
        'success': false,
        'status': 'FAILED',
        'error_code': 'REQUEST_FAILED',
        'reason': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>?> getUploadBatchStatus(String batchId) async {
    try {
      final userId = await _currentUserId();
      final uri = Uri.parse(
        '$baseUrl/api/wardrobe/upload-batches/${Uri.encodeComponent(batchId)}',
      ).replace(queryParameters: {'user_id': userId});
      final headers = await _authHeaders();
      final client = debugHttpClient;
      final response = client == null
          ? await http
                .get(uri, headers: headers)
                .timeout(const Duration(seconds: 20))
          : await client
                .get(uri, headers: headers)
                .timeout(const Duration(seconds: 20));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return await compute(_parseJsonMap, response.body);
      }
      debugPrint(
        'Get upload batch status failed: ${response.statusCode} - ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('Get upload batch status error: $e');
      return null;
    }
  }

  /// Power the item-detail CTAs (Style This / Build Outfit).
  ///
  /// mode = 'style_this'   -> response.style_directions: 3 directions
  /// mode = 'build_outfit' -> response.outfit: 1 outfit + missing_items
  ///
  /// Returns null only on transport failure; the backend itself never 500s
  /// (it returns success:false + a friendly message), so callers should also
  /// handle a non-null map with success == false.
  Future<Map<String, dynamic>?> styleWardrobeItem({
    required String itemId,
    required String scenario,
    Map<String, dynamic>? anchorItem,
    String? occasion,
  }) async {
    try {
      final userId = await _currentUserId();
      final payload = enrichBackendPayloadWithLocation(
        {
          'user_id': userId,
          'mode': scenario,
          'scenario': scenario,
          'anchor_item_id': itemId,
          'anchor_garment_id': itemId,
          'selected_item_id': itemId,
          if (occasion != null && occasion.isNotEmpty) 'occasion': occasion,
          if (anchorItem != null)
            'anchor_item': {
              ...anchorItem,
              'anchor_item_id': itemId,
              'selected_item_id': itemId,
            },
        },
        await _locationContext(userId),
        includeContext: true,
        includeUserProfile: true,
      );
      final response = await http
          .post(
            Uri.parse(
              '$baseUrl/api/stylist/items/${Uri.encodeComponent(itemId)}/style',
            ),
            headers: await _authHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        return await compute(_parseJsonMap, response.body);
      }
      debugPrint('AHVI_STYLE_THIS_BACKEND_FAIL status=${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('AHVI_STYLE_THIS_BACKEND_FAIL error_type=${e.runtimeType}');
      return null;
    }
  }

  Future<Map<String, dynamic>?> updateWardrobeLabels({
    required String itemId,
    String? name,
    String? category,
    String? subcategory,
    String? color,
    String? material,
    List<String>? tags,
  }) async {
    try {
      final payload = <String, dynamic>{
        'user_id': await _currentUserId(),
        'item_id': itemId,
        // Tell backend exactly where this item lives so it doesn't
        // depend on Cloud Run env vars matching our Env.* values.
        // Eliminates the 'Update failed: Not Found' env-mismatch bug.
        'database_id': Env.appwriteDatabaseId,
        'collection_id': Env.outfitsCollection,
      };
      if (name != null) payload['name'] = name;
      if (category != null) payload['category'] = category;
      if (subcategory != null) payload['subcategory'] = subcategory;
      if (color != null) payload['color'] = color;
      if (material != null) payload['material'] = material;
      if (tags != null) payload['tags'] = tags;

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/wardrobe/update-labels'),
            headers: await _authHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = await compute(_parseJsonMap, response.body);
        debugPrint(
          'AHVI_LABEL_UPDATE_OK status=${response.statusCode} body=${response.body}',
        );
        return body;
      }

      // Surface backend reason to the caller instead of swallowing it.
      String detail = response.body;
      try {
        final parsed = await compute(_parseJsonMap, response.body);
        detail =
            (parsed['detail'] ??
                    parsed['error'] ??
                    parsed['message'] ??
                    response.body)
                .toString();
      } catch (_) {
        // body wasn't JSON; keep raw
      }
      debugPrint(
        'AHVI_BACKEND_FAIL endpoint=/api/wardrobe/update-labels '
        'status=${response.statusCode} body=${response.body}',
      );
      return {
        'success': false,
        'status': response.statusCode,
        'detail': detail,
      };
    } catch (e, st) {
      debugPrint(
        'AHVI_BACKEND_EXCEPTION endpoint=/api/wardrobe/update-labels error=$e',
      );
      debugPrint('AHVI_BACKEND_EXCEPTION stack=$st');
      return {'success': false, 'detail': e.toString()};
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

      final deleted = <Map<String, dynamic>>[];
      final errors = <Map<String, dynamic>>[];

      for (final id in ids) {
        final response = await http
            .delete(
              Uri.parse('$baseUrl/api/wardrobe/${Uri.encodeComponent(id)}'),
              headers: await _authHeaders(),
            )
            .timeout(const Duration(seconds: 35));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final body = await compute(_parseJsonMap, response.body);
          if (body['success'] == true) {
            deleted.add(body);
            continue;
          }
          errors.add({'id': id, 'status': response.statusCode, 'error': body});
          continue;
        }

        debugPrint(
          'Wardrobe delete failed: ${response.statusCode} ${response.body}',
        );
        errors.add({
          'id': id,
          'status': response.statusCode,
          'error': response.body,
        });
      }

      return {
        'success': errors.isEmpty,
        'deleted_count': deleted.length,
        'error_count': errors.length,
        'deleted': deleted,
        'errors': errors,
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
    CalendarListSurface surface = CalendarListSurface.calendar,
  }) async {
    final result = await getCalendarEventsResult(
      startTime: startTime,
      endTime: endTime,
      limit: limit,
      surface: surface,
    );
    return result.events;
  }

  Future<CalendarEventsLoadResult> getCalendarEventsResult({
    DateTime? startTime,
    DateTime? endTime,
    int limit = 200,
    CalendarListSurface surface = CalendarListSurface.calendar,
  }) async {
    debugPrint(
      calendarListStartDiagnostic(
        surface: surface,
        from: startTime,
        to: endTime,
      ),
    );
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
        if (data['events'] is! List) {
          debugPrint('Calendar events load parse failed: events is not a list');
          return const CalendarEventsLoadResult.failure();
        }
        final batch = CalendarEventBatch.parse(
          data['events'],
          onSkipped: (eventId, field) => debugPrint(
            'AHVI_CALENDAR_PARSE_SKIPPED event_id=$eventId field=$field',
          ),
        );
        debugPrint(calendarListOkDiagnostic(surface: surface, batch: batch));
        return CalendarEventsLoadResult(events: batch.events, succeeded: true);
      }

      debugPrint(
        'Calendar events load failed: ${response.statusCode} ${response.body}',
      );
      return const CalendarEventsLoadResult.failure();
    } catch (e) {
      debugPrint('Calendar events load error: $e');
      return const CalendarEventsLoadResult.failure();
    }
  }

  Future<List<Map<String, dynamic>>> getTodayCalendarEvents({
    DateTime? date,
    CalendarListSurface surface = CalendarListSurface.homeToday,
  }) async {
    final day = date ?? DateTime.now();
    final from = DateTime(day.year, day.month, day.day);
    final to = from.add(const Duration(days: 1));
    debugPrint(
      calendarListStartDiagnostic(surface: surface, from: from, to: to),
    );
    try {
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
        final batch = CalendarEventBatch.parse(
          data['events'],
          onSkipped: (eventId, field) => debugPrint(
            'AHVI_CALENDAR_PARSE_SKIPPED event_id=$eventId field=$field',
          ),
        );
        debugPrint(calendarListOkDiagnostic(surface: surface, batch: batch));
        return batch.events;
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

  Future<CalendarPlanCounts> getCalendarPlanCounts() async {
    try {
      final uri = Uri.parse(
        '$baseUrl/api/calendar/events',
      ).replace(queryParameters: const {'limit': '300'});
      final response = await http
          .get(uri, headers: await _authHeaders())
          .timeout(const Duration(seconds: 30));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = await compute(_parseJsonMap, response.body);
        return CalendarPlanCounts.fromJson(data);
      }
    } catch (e) {
      debugPrint('Calendar plan counts load error: $e');
    }
    return const CalendarPlanCounts.empty();
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
    debugPrint('AHVI_CALENDAR_CREATE_START');
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
        final event = calendarJsonMap(data['event']) ?? data;
        final record = CalendarEventRecord.tryParse(
          event,
          onSkipped: (eventId, field) => debugPrint(
            'AHVI_CALENDAR_PARSE_SKIPPED event_id=$eventId field=$field',
          ),
        );
        if (record == null) return null;
        debugPrint('AHVI_CALENDAR_CREATE_OK event_id=${record.id}');
        return event;
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

  // --- Today-workout session coordination --------------------------------
  // Both home.dart and fitness_page.dart request today's workout. To stop a
  // request storm (and repeated calls on rebuild) a single completed result is
  // cached for the app session, and concurrent callers share ONE in-flight
  // request. A failed / non-2xx request is never cached, so an explicit user
  // retry can try again — but nothing retries automatically.
  //
  // Cache is scoped by '$userId:$localDate'. A null key is used when the user
  // cannot be resolved (unauthenticated / test paths) and provides the same
  // unscoped behaviour as the pre-isolation implementation.
  String? _todayWorkoutCacheKey;
  Map<String, dynamic>? _todayWorkoutCache;
  String? _todayWorkoutInflightKey;
  Future<Map<String, dynamic>>? _todayWorkoutInFlight;

  /// Clears all today-workout session state: cache, timestamp, and any
  /// in-flight request. Called on logout, user switch, and explicit retry.
  /// Wired to AppwriteService.onSessionCacheInvalidated in the constructor
  /// so auth-scope changes always clear it without a circular dependency.
  void clearTodayWorkoutCache() {
    _todayWorkoutCache = null;
    _todayWorkoutCacheKey = null;
    _todayWorkoutInFlight = null;
    _todayWorkoutInflightKey = null;
  }

  String _localDate() =>
      debugLocalDateProvider?.call() ??
      DateTime.now().toLocal().toIso8601String().substring(0, 10);

  /// Test seam: override the local date string ('yyyy-MM-dd') used for cache
  /// keying so tests can simulate a day boundary without sleeping.
  @visibleForTesting
  String Function()? debugLocalDateProvider;

  /// Test seam: override the user ID resolver used for cache keying so tests
  /// can exercise user-isolation logic without a real Appwrite session.
  @visibleForTesting
  Future<String> Function()? debugCurrentUserIdProvider;

  /// Test seam: when set, replaces the real network fetch so the coordination
  /// logic (cache / single-flight / no-auto-retry) can be exercised in unit
  /// tests without real HTTP or Appwrite.
  @visibleForTesting
  Future<Map<String, dynamic>> Function()? debugTodayWorkoutFetcher;

  Future<Map<String, dynamic>> getTodayWorkout({
    bool forceRefresh = false,
  }) async {
    // Resolve the cache key for this call: '$userId:$localDate'.
    //
    // Production fast-path: reads the in-memory cached user ID synchronously
    // so the coordination logic (cache check, in-flight join) is still
    // reachable without an await — preserving the existing behaviour that
    // concurrent callers can share an in-flight within the same event-loop
    // frame.
    //
    // Test seam (debugCurrentUserIdProvider): async path used only when
    // user-isolation scenarios need to switch identities between calls.
    //
    // Falls back to null key (legacy unkeyed) when no user is available.
    String? key;
    if (debugCurrentUserIdProvider != null) {
      try {
        key = '${await debugCurrentUserIdProvider!()}:${_localDate()}';
      } catch (_) {}
    } else {
      final syncId = _appwriteService.currentUserId;
      if (syncId != null && syncId.isNotEmpty) {
        key = '$syncId:${_localDate()}';
      }
    }

    if (forceRefresh) {
      _todayWorkoutCache = null;
      _todayWorkoutCacheKey = null;
      _todayWorkoutInFlight = null;
      _todayWorkoutInflightKey = null;
    }

    // Cache hit: same user+date (null==null for unkeyed paths).
    if (_todayWorkoutCache != null && _todayWorkoutCacheKey == key) {
      debugPrint('AHVI_WORKOUT_TODAY_SKIPPED reason=cached');
      return _todayWorkoutCache!;
    }

    // In-flight deduplication: only join a request for the same scope.
    final existing = _todayWorkoutInFlight;
    if (existing != null && _todayWorkoutInflightKey == key) {
      debugPrint('AHVI_WORKOUT_TODAY_SKIPPED reason=already_loading');
      return existing;
    }

    final fetcher = debugTodayWorkoutFetcher ?? _fetchTodayWorkout;
    final future = fetcher();
    _todayWorkoutInFlight = future;
    _todayWorkoutInflightKey = key;

    return future
        .then((result) {
          // Cache only non-empty results, and only if still the active scope.
          // Stale in-flight completions (after logout / user switch) are
          // rejected by the key mismatch so they never pollute the new scope.
          if (result.isNotEmpty && _todayWorkoutInflightKey == key) {
            _todayWorkoutCache = result;
            _todayWorkoutCacheKey = key;
          }
          return result;
        })
        .whenComplete(() {
          if (_todayWorkoutInflightKey == key) {
            _todayWorkoutInFlight = null;
            _todayWorkoutInflightKey = null;
          }
        });
  }

  Future<Map<String, dynamic>> _fetchTodayWorkout() async {
    // Normalize any trailing slashes on the base URL exactly once, then append
    // the exact route so we never emit `//api/workouts/today`.
    final root = baseUrl.replaceAll(RegExp(r'/+$'), '');
    var url = '$root/api/workouts/today';
    debugPrint('AHVI_WORKOUT_TODAY_REQUEST endpoint=$url');
    try {
      final userId = await _currentUserId();
      final location = await _locationContext(userId);
      url = Uri.parse(url)
          .replace(queryParameters: {'location_context': jsonEncode(location)})
          .toString();
      final headers = await _authHeaders();
      final hasAuth =
          (headers['Authorization'] ?? headers['authorization'] ?? '')
              .trim()
              .isNotEmpty;
      debugPrint('AHVI_WORKOUT_TODAY_AUTH authorization=$hasAuth');
      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 20));
      debugPrint(
        'AHVI_WORKOUT_TODAY_STATUS status=${response.statusCode} '
        'content_type=${response.headers['content-type'] ?? ''}',
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return await compute(_parseJsonMap, response.body);
      }
      // Non-2xx: controlled empty state, not cached, no automatic retry.
      return <String, dynamic>{};
    } catch (e) {
      debugPrint('AHVI_WORKOUT_TODAY_STATUS status=error content_type=');
      return <String, dynamic>{};
    }
  }

  /// Test seam: when set, replaces the real /api/home/today-summary fetch.
  @visibleForTesting
  Future<HomeTodaySummary> Function()? debugHomeSummaryFetcher;

  Future<HomeTodaySummary> getHomeTodaySummary({String? timezone}) async {
    debugPrint('home.summary.requested');
    final root = baseUrl.replaceAll(RegExp(r'/+$'), '');
    try {
      await _currentUserId();
      final query = <String, String>{
        if (timezone != null && timezone.trim().isNotEmpty)
          'timezone': timezone.trim(),
      };
      final baseUri = Uri.parse('$root/api/home/today-summary');
      final uri = query.isEmpty
          ? baseUri
          : baseUri.replace(queryParameters: query);
      final headers = await _authHeaders();
      final client = debugHttpClient;
      final response = await (client != null
              ? client.get(uri, headers: headers)
              : http.get(uri, headers: headers))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final raw = await compute(_parseJsonMap, response.body);
        final summary = HomeTodaySummary.fromMap(raw);
        final cards = [
          summary.wear,
          summary.move,
          summary.eat,
          summary.care,
          summary.medicine,
        ];
        final allAvailable = cards.every((c) => c.available);
        if (!allAvailable) debugPrint('home.summary.partial');
        debugPrint('home.summary.loaded date=${summary.date}');
        return summary;
      }
      debugPrint('home.summary.failed status=${response.statusCode}');
      throw BackendRequestException(
        'home_today_summary: HTTP ${response.statusCode}',
      );
    } catch (e) {
      if (e is! BackendRequestException) {
        debugPrint('home.summary.failed err=${e.runtimeType}');
      }
      rethrow;
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
      final userId = await _currentUserId();
      final payload = enrichBackendPayloadWithLocation(
        {
          'goal': goal,
          'duration': duration,
          'location': location,
          'equipment': equipment,
          if (constraint != null && constraint.trim().isNotEmpty)
            'constraint': constraint,
        },
        await _locationContext(userId),
        includeContext: true,
        includeUserProfile: true,
      );
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/workouts/recommend'),
            headers: await _authHeaders(),
            body: jsonEncode(payload),
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
    String medId = '',
    String medName = '',
    String dose = '',
    String notificationKey = '',
  }) async {
    try {
      final sendAtISO = sendAt.toUtc().toIso8601String();
      final reminder = <String, dynamic>{
        'sendAtISO': sendAtISO,
        'scheduledFor': sendAtISO,
        'message': message,
        'body': message,
        'title': source == 'medi' ? 'Medicine reminder' : 'AHVI reminder',
        'priority': priority,
        'offsetMinutes': offsetMinutes,
      };

      if (medId.trim().isNotEmpty) {
        reminder['medId'] = medId.trim();
        reminder['notificationKey'] = notificationKey.trim().isNotEmpty
            ? notificationKey.trim()
            : 'med:${medId.trim()}:$sendAtISO';
      }

      if (medName.trim().isNotEmpty) {
        reminder['medName'] = medName.trim();
      }

      if (dose.trim().isNotEmpty) {
        reminder['dose'] = dose.trim();
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/notifications/reminders/schedule'),
        headers: await _authHeaders(),
        body: jsonEncode({
          'eventId': eventId,
          'source': source,
          'medId': medId,
          'medName': medName,
          'dose': dose,
          'reminders': [reminder],
        }),
      );

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Reminder schedule error: $e');
      return false;
    }
  }
}
