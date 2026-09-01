import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/services/sequential_upload_controller.dart';

Uint8List _bytes(String value) => Uint8List.fromList(value.codeUnits);

Map<String, dynamic> _added(String id) => {
  'status': 'ADDED_TO_WARDROBE',
  'wardrobe_item_id': id,
};

Map<String, dynamic> _duplicate() => {
  'status': 'NEEDS_REVIEW',
  'error_code': 'DUPLICATE_WARDROBE_ITEM',
  'matched_item_id': 'existing-1',
  'duplicate_reason': 'image_vector',
  'duplicate_confidence': 0.93,
};

void main() {
  test(
    'processes items strictly in order and reports terminal progress',
    () async {
      final calls = <String>[];
      final progress = <String>[];
      final controller = SequentialUploadController(
        createOrResumeBatch:
            ({required clientBatchRequestId, required totalItems}) async {
              expect(totalItems, 3);
              return {'batch_id': 'server-batch'};
            },
        processItem:
            ({
              required batchId,
              required clientUploadItemId,
              required imageBytes,
              metadata,
              overrideDuplicate = false,
              reviewedItem,
            }) async {
              calls.add(clientUploadItemId);
              return _added('wardrobe-$clientUploadItemId');
            },
        getBatchStatus: (batchId) async => {'batch_id': batchId},
      );

      final results = await controller.run(
        [
          UploadBatchUnit(clientUploadItemId: 'a', imageBytes: _bytes('a')),
          UploadBatchUnit(clientUploadItemId: 'b', imageBytes: _bytes('b')),
          UploadBatchUnit(clientUploadItemId: 'c', imageBytes: _bytes('c')),
        ],
        clientBatchRequestId: 'client-batch',
        onProgress: (completed, total, result) =>
            progress.add('$completed/$total:${result.clientUploadItemId}'),
      );

      expect(calls, ['a', 'b', 'c']);
      expect(progress, ['1/3:a', '2/3:b', '3/3:c']);
      expect(results.map((result) => result.wardrobeItemId), [
        'wardrobe-a',
        'wardrobe-b',
        'wardrobe-c',
      ]);
    },
  );

  test(
    'continues after duplicate and Add Anyway only retries that item',
    () async {
      final calls = <Map<String, dynamic>>[];
      final counts = <String, int>{};
      final controller = SequentialUploadController(
        createOrResumeBatch:
            ({required clientBatchRequestId, required totalItems}) async => {
              'batch_id': 'batch-1',
            },
        processItem:
            ({
              required batchId,
              required clientUploadItemId,
              required imageBytes,
              metadata,
              overrideDuplicate = false,
              reviewedItem,
            }) async {
              calls.add({
                'id': clientUploadItemId,
                'batchId': batchId,
                'overrideDuplicate': overrideDuplicate,
              });
              final count = counts.update(
                clientUploadItemId,
                (value) => value + 1,
                ifAbsent: () => 1,
              );
              if (clientUploadItemId == 'dup' && count == 1) {
                return _duplicate();
              }
              return _added('wardrobe-$clientUploadItemId');
            },
        getBatchStatus: (batchId) async => null,
      );

      await controller.run([
        UploadBatchUnit(clientUploadItemId: 'dup', imageBytes: _bytes('dup')),
        UploadBatchUnit(
          clientUploadItemId: 'other',
          imageBytes: _bytes('other'),
        ),
      ], clientBatchRequestId: 'client-batch');
      final duplicate = controller.results.firstWhere(
        (result) => result.isDuplicate,
      );
      expect(duplicate.matchedItemId, 'existing-1');

      final added = await controller.addAnyway('dup');
      expect(added.wardrobeItemId, 'wardrobe-dup');
      expect(calls, [
        {'id': 'dup', 'batchId': 'batch-1', 'overrideDuplicate': false},
        {'id': 'other', 'batchId': 'batch-1', 'overrideDuplicate': false},
        {'id': 'dup', 'batchId': 'batch-1', 'overrideDuplicate': true},
      ]);
      expect(controller.results.length, 2);
      expect(controller.results.every((result) => result.isAdded), isTrue);
    },
  );

  test('does not classify unrelated NEEDS_REVIEW as duplicate', () async {
    final controller = SequentialUploadController(
      createOrResumeBatch:
          ({required clientBatchRequestId, required totalItems}) async => {
            'batch_id': clientBatchRequestId,
          },
      processItem:
          ({
            required batchId,
            required clientUploadItemId,
            required imageBytes,
            metadata,
            overrideDuplicate = false,
            reviewedItem,
          }) async => {
            'status': 'NEEDS_REVIEW',
            'error_code': 'NOT_AUTO_APPROVED',
          },
      getBatchStatus: (batchId) async => null,
    );

    final result = (await controller.run([
      UploadBatchUnit(clientUploadItemId: 'review', imageBytes: _bytes('x')),
    ], clientBatchRequestId: 'batch')).single;
    expect(result.outcome, UploadItemOutcome.needsReview);
    expect(result.isDuplicate, isFalse);
  });
}
