import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/services/backend_service.dart';

void main() {
  test('central enrichment propagates canonical context without data loss', () {
    final location = <String, dynamic>{
      'lat': 12.9716,
      'lon': 77.5946,
      'timezone': 'Asia/Kolkata',
      'label': 'Bengaluru, IN',
      'captured_at': '2026-07-29T10:00:00.000Z',
      'source': 'cache',
      'permission': 'granted',
      'accuracy_m': 8.0,
    };

    final result = enrichBackendPayloadWithLocation(
      {
        'message': 'What should I wear?',
        'context': {'surface': 'daily_wear'},
        'context_data': {'request': 'daily_board'},
        'user_profile': {'gender': 'female'},
      },
      location,
      includeContext: true,
      includeUserProfile: true,
    );

    expect(result['location_context'], location);
    expect(result['location'], location);
    expect(result['timezone'], 'Asia/Kolkata');
    expect((result['context'] as Map)['surface'], 'daily_wear');
    expect((result['context'] as Map)['location_context'], location);
    expect((result['context'] as Map)['location'], location);
    expect((result['context_data'] as Map)['request'], 'daily_board');
    expect((result['context_data'] as Map)['location_context'], location);
    expect((result['user_profile'] as Map)['gender'], 'female');
    expect((result['user_profile'] as Map)['location_context'], location);
    expect((result['user_profile'] as Map)['location'], location);
  });
}
