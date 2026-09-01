import 'dart:io';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:myapp/services/backend_service.dart';

class _FakeHttpClient extends http.BaseClient {
  final List<http.Request> requests = [];
  final Map<String, dynamic> responses;

  _FakeHttpClient(this.responses);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final typedRequest = request as http.Request;
    requests.add(typedRequest);
    final key = '${request.method} ${request.url.path}';
    final response = responses[key] ?? const {'status': 'FAILED'};
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(response))),
      response is Map && response['_status_code'] is int
          ? response['_status_code'] as int
          : 200,
      headers: const {'content-type': 'application/json'},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      (call) async => <String, dynamic>{
        'appName': 'ahvi_test',
        'packageName': 'com.ahvi.test',
        'version': '1.0.0',
        'buildNumber': '1',
      },
    );
  });

  late BackendService service;
  late _FakeHttpClient client;

  setUp(() {
    dotenv.loadFromString(
      envString:
          'EXPO_PUBLIC_APPWRITE_ENDPOINT=https://appwrite.test/v1\n'
          'EXPO_PUBLIC_APPWRITE_PROJECT_ID=project\n'
          'EXPO_PUBLIC_BACKEND_API_URL=https://backend.test',
      isOptional: true,
    );
    client = _FakeHttpClient({
      'POST /api/wardrobe/upload-batches': {
        'batch_id': 'batch-123',
        'resumed': false,
      },
      'POST /api/wardrobe/upload-batches/batch-123/items': {
        'status': 'ADDED_TO_WARDROBE',
        'wardrobe_item_id': 'wardrobe-123',
      },
      'GET /api/wardrobe/upload-batches/batch-123': {
        'batch_id': 'batch-123',
        'status': 'COMPLETED',
      },
    });
    service = BackendService();
    service.debugHttpClient = client;
    service.debugAuthenticatedUserIdProvider = () async => 'user-123';
    service.debugAuthHeadersProvider = () async => {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer test-token',
    };
  });

  test(
    'sends create, item, and status requests with the sequential contract',
    () async {
      final created = await service.createOrResumeUploadBatch(
        clientBatchRequestId: 'client-batch-1',
        totalItems: 2,
      );
      final added = await service.processUploadBatchItem(
        batchId: 'batch-123',
        clientUploadItemId: 'client-item-1',
        imageBytes: Uint8List.fromList([1, 2, 3]),
        metadata: {
          'category': 'Tops',
          'occasions': ['Work'],
        },
        reviewedItem: {'name': 'Blue shirt'},
      );
      final status = await service.getUploadBatchStatus('batch-123');

      expect(created?['batch_id'], 'batch-123');
      expect(added?['wardrobe_item_id'], 'wardrobe-123');
      expect(status?['status'], 'COMPLETED');
      expect(client.requests.map((request) => request.method), [
        'POST',
        'POST',
        'GET',
      ]);

      final createBody = jsonDecode(client.requests[0].body) as Map;
      expect(createBody['user_id'], 'user-123');
      expect(createBody['client_batch_request_id'], 'client-batch-1');
      expect(createBody['total_items'], 2);

      final itemBody = jsonDecode(client.requests[1].body) as Map;
      expect(itemBody['user_id'], 'user-123');
      expect(itemBody['client_upload_item_id'], 'client-item-1');
      expect(itemBody['image_base64'], 'AQID');
      expect(itemBody['metadata']['occasions'], ['Work']);
      expect(itemBody['reviewed_item']['name'], 'Blue shirt');
      expect(itemBody['override_duplicate'], false);
      expect(client.requests[2].url.queryParameters['user_id'], 'user-123');
    },
  );
}
