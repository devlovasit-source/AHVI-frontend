import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/services/sequential_upload_controller.dart';

Uint8List _bytes(String tag) => Uint8List.fromList(tag.codeUnits);

Map<String, dynamic> _added(String wardrobeItemId) => {
  'success': true,
  'status': 'ADDED_TO_WARDROBE',
  'wardrobe_item_id': wardrobeItemId,
};

Map<String, dynamic> _duplicate({
  String matchedItemId = 'existing-1',
  String reason = 'pixel_hash',
  double confidence = 0.97,
}) => {
  'success': false,
  'status': 'NEEDS_REVIEW',
  'error_code': 'DUPLICATE_WARDROBE_ITEM',
  'matched_item_id': matchedItemId,
  'duplicate_reason': reason,
  'duplicate_confidence': confidence,
};

Map<String, dynamic> _needsReviewOther() => {
  'success': false,
  'status': 'NEEDS_REVIEW',
  'error_code': 'NOT_AUTO_APPROVED',
};

Map<String, dynamic> _rejected() => {
  'success': false,
  'status': 'REJECTED',
  'reason': 'no_item_detected',
};

Map<String, dynamic> _failed() => {
  'success': false,
  'status': 'FAILED',
  'error_code': 'PERSISTENCE_FAILED',
};

/// Builds a controller whose createOrResumeBatch/getBatchStatus are trivial
/// passthroughs, and whose processItem is driven by [byId] (falls back to
/// [byId]['*'] if a specific item id isn't listed) while recording every
/// call in [calls] for sequencing/scoping assertions.
SequentialUploadController _controller({
  required Map<String, List<Map<String, dynamic>>> byId,
  required List<Map<String, dynamic>> calls,
}) {
  final callCounts = <String, int>{};
  return SequentialUploadController(
    createOrResumeBatch: ({required clientBatchRequestId, required totalItems}) async {
      return {
        'success': true,
        'batch_id': clientBatchRequestId,
        'resumed': false,
      };
    },
    processItem: ({
      required batchId,
      required clientUploadItemId,
      required imageBytes,
      metadata,
      overrideDuplicate = false,
    }) async {
      calls.add({
        'batchId': batchId,
        'clientUploadItemId': clientUploadItemId,
        'overrideDuplicate': overrideDuplicate,
      });
      final responses = byId[clientUploadItemId] ?? byId['*'] ?? const [];
      final idx = (callCounts[clientUploadItemId] ?? 0).clamp(
        0,
        responses.isEmpty ? 0 : responses.length - 1,
      );
      callCounts[clientUploadItemId] = (callCounts[clientUploadItemId] ?? 0) + 1;
      return responses.isEmpty ? null : responses[idx];
    },
    getBatchStatus: (batchId) async {
      return {
        'success': true,
        'batch_id': batchId,
        'status': 'COMPLETED',
        'total_items': 3,
        'added_count': 2,
        'needs_review_count': 1,
        'rejected_count': 0,
        'failed_count': 0,
      };
    },
  );
}

void main() {
  group('SequentialUploadController', () {
    test('1/2. processes N images sequentially with 1/N..N/N progress', () async {
      final calls = <Map<String, dynamic>>[];
      final controller = _controller(
        byId: {
          'a': [_added('w-a')],
          'b': [_added('w-b')],
          'c': [_added('w-c')],
        },
        calls: calls,
      );
      final progress = <String>[];

      final results = await controller.run(
        [
          UploadBatchUnit(clientUploadItemId: 'a', imageBytes: _bytes('a')),
          UploadBatchUnit(clientUploadItemId: 'b', imageBytes: _bytes('b')),
          UploadBatchUnit(clientUploadItemId: 'c', imageBytes: _bytes('c')),
        ],
        clientBatchRequestId: 'batch-1',
        onProgress: (completed, total, result) =>
            progress.add('$completed/$total'),
      );

      expect(progress, ['1/3', '2/3', '3/3']);
      expect(results.map((r) => r.clientUploadItemId), ['a', 'b', 'c']);
      expect(results.every((r) => r.isAdded), isTrue);
      // Strictly sequential: item b's call must not have been made before
      // item a's call was recorded (order-of-calls is the same as order of
      // completion - no Future.wait interleaving).
      expect(calls.map((c) => c['clientUploadItemId']), ['a', 'b', 'c']);
    });

    test('3. valid + failed + valid continues (one failure does not stop the batch)', () async {
      final calls = <Map<String, dynamic>>[];
      final controller = _controller(
        byId: {
          'a': [_added('w-a')],
          'b': [_failed()],
          'c': [_added('w-c')],
        },
        calls: calls,
      );

      final results = await controller.run(
        [
          UploadBatchUnit(clientUploadItemId: 'a', imageBytes: _bytes('a')),
          UploadBatchUnit(clientUploadItemId: 'b', imageBytes: _bytes('b')),
          UploadBatchUnit(clientUploadItemId: 'c', imageBytes: _bytes('c')),
        ],
        clientBatchRequestId: 'batch-2',
      );

      expect(results[0].outcome, UploadItemOutcome.added);
      expect(results[1].outcome, UploadItemOutcome.failed);
      expect(results[2].outcome, UploadItemOutcome.added);
      expect(calls.length, 3, reason: 'item c must still run after item b failed');
    });

    test('4. valid + duplicate + valid continues', () async {
      final controller = _controller(
        byId: {
          'a': [_added('w-a')],
          'b': [_duplicate()],
          'c': [_added('w-c')],
        },
        calls: [],
      );

      final results = await controller.run(
        [
          UploadBatchUnit(clientUploadItemId: 'a', imageBytes: _bytes('a')),
          UploadBatchUnit(clientUploadItemId: 'b', imageBytes: _bytes('b')),
          UploadBatchUnit(clientUploadItemId: 'c', imageBytes: _bytes('c')),
        ],
        clientBatchRequestId: 'batch-3',
      );

      expect(results[0].outcome, UploadItemOutcome.added);
      expect(results[1].outcome, UploadItemOutcome.duplicate);
      expect(results[2].outcome, UploadItemOutcome.added, reason: 'item c must still run after item b was flagged a duplicate');
    });

    test('6. duplicate result maps to the duplicate outcome with matched_item_id/reason/confidence', () async {
      final controller = _controller(
        byId: {
          'dup': [_duplicate(matchedItemId: 'wardrobe-xyz', reason: 'image_vector', confidence: 0.91)],
        },
        calls: [],
      );

      final results = await controller.run(
        [UploadBatchUnit(clientUploadItemId: 'dup', imageBytes: _bytes('dup'))],
        clientBatchRequestId: 'batch-4',
      );

      final r = results.single;
      expect(r.isDuplicate, isTrue);
      expect(r.matchedItemId, 'wardrobe-xyz');
      expect(r.duplicateReason, 'image_vector');
      expect(r.duplicateConfidence, 0.91);
    });

    test('7/8. Add anyway retries the SAME client_upload_item_id, scoped only to that item', () async {
      final calls = <Map<String, dynamic>>[];
      final controller = _controller(
        byId: {
          'dup': [_duplicate(), _added('w-dup')],
          'other': [_added('w-other')],
        },
        calls: calls,
      );

      await controller.run(
        [
          UploadBatchUnit(clientUploadItemId: 'dup', imageBytes: _bytes('dup')),
          UploadBatchUnit(clientUploadItemId: 'other', imageBytes: _bytes('other')),
        ],
        clientBatchRequestId: 'batch-5',
      );
      calls.clear();

      final addAnywayResult = await controller.addAnyway('dup');

      expect(calls.length, 1, reason: 'add anyway must only call processItem for the chosen item');
      expect(calls.single['clientUploadItemId'], 'dup');
      expect(calls.single['overrideDuplicate'], isTrue);
      expect(addAnywayResult.isAdded, isTrue);

      // The other item's already-recorded result must be untouched.
      final otherResult = controller.results.firstWhere((r) => r.clientUploadItemId == 'other');
      expect(otherResult.isAdded, isTrue);
    });

    test('9. Add anyway resulting in ADDED replaces the duplicate row, not a second entry', () async {
      final controller = _controller(
        byId: {
          'dup': [_duplicate(), _added('w-dup')],
        },
        calls: [],
      );

      await controller.run(
        [UploadBatchUnit(clientUploadItemId: 'dup', imageBytes: _bytes('dup'))],
        clientBatchRequestId: 'batch-6',
      );
      expect(controller.results.length, 1);
      expect(controller.results.single.isDuplicate, isTrue);

      await controller.addAnyway('dup');

      expect(controller.results.length, 1, reason: 'must not append a second row for the same item');
      expect(controller.results.single.isAdded, isTrue);
      expect(controller.results.single.wardrobeItemId, 'w-dup');
    });

    test('11. plain NEEDS_REVIEW (non-duplicate) is never classified as a duplicate', () async {
      final controller = _controller(
        byId: {
          'x': [_needsReviewOther()],
        },
        calls: [],
      );

      final results = await controller.run(
        [UploadBatchUnit(clientUploadItemId: 'x', imageBytes: _bytes('x'))],
        clientBatchRequestId: 'batch-7',
      );

      expect(results.single.outcome, UploadItemOutcome.needsReview);
      expect(results.single.isDuplicate, isFalse);
    });

    test('12. single-image flow (N=1) completes normally', () async {
      final controller = _controller(
        byId: {
          'solo': [_added('w-solo')],
        },
        calls: [],
      );

      final results = await controller.run(
        [UploadBatchUnit(clientUploadItemId: 'solo', imageBytes: _bytes('solo'))],
        clientBatchRequestId: 'batch-8',
      );

      expect(results.single.isAdded, isTrue);
      expect(results.single.wardrobeItemId, 'w-solo');
    });

    test('rejected outcome is distinguished from failed/needs_review', () async {
      final controller = _controller(
        byId: {
          'r': [_rejected()],
        },
        calls: [],
      );

      final results = await controller.run(
        [UploadBatchUnit(clientUploadItemId: 'r', imageBytes: _bytes('r'))],
        clientBatchRequestId: 'batch-9',
      );

      expect(results.single.outcome, UploadItemOutcome.rejected);
    });

    test('14. final batch counts are fetched via GET batch-status using the resolved batch id', () async {
      final controller = _controller(byId: {'a': [_added('w-a')]}, calls: []);
      await controller.run(
        [UploadBatchUnit(clientUploadItemId: 'a', imageBytes: _bytes('a'))],
        clientBatchRequestId: 'batch-10',
      );

      final status = await controller.fetchFinalStatus();
      expect(status, isNotNull);
      expect(status!['batch_id'], controller.batchId);
      expect(status['added_count'] + status['needs_review_count'] + status['rejected_count'] + status['failed_count'], status['total_items']);
    });

    test('addAnyway before run() for that item throws instead of silently no-op-ing', () async {
      final controller = _controller(byId: const {}, calls: []);
      expect(() => controller.addAnyway('never-run'), throwsStateError);
    });
  });
}
