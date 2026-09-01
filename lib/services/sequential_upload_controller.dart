import 'dart:typed_data';

typedef CreateOrResumeBatchFn =
    Future<Map<String, dynamic>?> Function({
      required String clientBatchRequestId,
      required int totalItems,
    });

typedef ProcessUploadItemFn =
    Future<Map<String, dynamic>?> Function({
      required String batchId,
      required String clientUploadItemId,
      required Uint8List imageBytes,
      Map<String, dynamic>? metadata,
      bool overrideDuplicate,
      Map<String, dynamic>? reviewedItem,
    });

typedef GetBatchStatusFn =
    Future<Map<String, dynamic>?> Function(String batchId);

class UploadBatchUnit {
  final String clientUploadItemId;
  final Uint8List imageBytes;
  final Map<String, dynamic>? metadata;
  final Map<String, dynamic>? reviewedItem;

  const UploadBatchUnit({
    required this.clientUploadItemId,
    required this.imageBytes,
    this.metadata,
    this.reviewedItem,
  });
}

enum UploadItemOutcome { added, duplicate, needsReview, rejected, failed }

class UploadItemResult {
  final String clientUploadItemId;
  final UploadItemOutcome outcome;
  final String? wardrobeItemId;
  final String? matchedItemId;
  final String? duplicateReason;
  final double? duplicateConfidence;
  final String? errorCode;
  final String? reason;
  final Map<String, dynamic> raw;

  const UploadItemResult({
    required this.clientUploadItemId,
    required this.outcome,
    this.wardrobeItemId,
    this.matchedItemId,
    this.duplicateReason,
    this.duplicateConfidence,
    this.errorCode,
    this.reason,
    this.raw = const {},
  });

  bool get isAdded => outcome == UploadItemOutcome.added;
  bool get isDuplicate => outcome == UploadItemOutcome.duplicate;

  factory UploadItemResult.fromRaw(
    String clientUploadItemId,
    Map<String, dynamic>? raw,
  ) {
    final response = raw ?? const <String, dynamic>{};
    final status = (response['status'] ?? '').toString().trim().toUpperCase();
    final errorCode = response['error_code']?.toString();

    final outcome = switch (status) {
      'ADDED_TO_WARDROBE' => UploadItemOutcome.added,
      'NEEDS_REVIEW' when errorCode == 'DUPLICATE_WARDROBE_ITEM' =>
        UploadItemOutcome.duplicate,
      'NEEDS_REVIEW' => UploadItemOutcome.needsReview,
      'REJECTED' => UploadItemOutcome.rejected,
      _ => UploadItemOutcome.failed,
    };
    final confidence = response['duplicate_confidence'];

    return UploadItemResult(
      clientUploadItemId: clientUploadItemId,
      outcome: outcome,
      wardrobeItemId: response['wardrobe_item_id']?.toString(),
      matchedItemId: response['matched_item_id']?.toString(),
      duplicateReason: response['duplicate_reason']?.toString(),
      duplicateConfidence: confidence is num ? confidence.toDouble() : null,
      errorCode: errorCode,
      reason: response['reason']?.toString(),
      raw: response,
    );
  }
}

class SequentialUploadController {
  final CreateOrResumeBatchFn createOrResumeBatch;
  final ProcessUploadItemFn processItem;
  final GetBatchStatusFn getBatchStatus;

  SequentialUploadController({
    required this.createOrResumeBatch,
    required this.processItem,
    required this.getBatchStatus,
  });

  String? _batchId;
  String? get batchId => _batchId;

  final Map<String, UploadBatchUnit> _unitsById = {};
  final Map<String, UploadItemResult> _resultsById = {};

  List<UploadItemResult> get results => _resultsById.values.toList();

  Future<List<UploadItemResult>> run(
    List<UploadBatchUnit> units, {
    required String clientBatchRequestId,
    void Function(int completed, int total, UploadItemResult result)?
    onProgress,
  }) async {
    if (_batchId == null) {
      final batchResponse = await createOrResumeBatch(
        clientBatchRequestId: clientBatchRequestId,
        totalItems: units.length,
      );
      _batchId =
          (batchResponse?['batch_id'] as String?) ?? clientBatchRequestId;
    }

    for (var index = 0; index < units.length; index++) {
      final unit = units[index];
      _unitsById[unit.clientUploadItemId] = unit;
      final raw = await processItem(
        batchId: _batchId!,
        clientUploadItemId: unit.clientUploadItemId,
        imageBytes: unit.imageBytes,
        metadata: unit.metadata,
        overrideDuplicate: false,
        reviewedItem: unit.reviewedItem,
      );
      final result = UploadItemResult.fromRaw(unit.clientUploadItemId, raw);
      _resultsById[unit.clientUploadItemId] = result;
      onProgress?.call(index + 1, units.length, result);
    }
    return results;
  }

  Future<UploadItemResult> addAnyway(
    String clientUploadItemId, {
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? reviewedItem,
  }) async {
    final batchId = _batchId;
    final unit = _unitsById[clientUploadItemId];
    if (batchId == null || unit == null) {
      throw StateError(
        'addAnyway($clientUploadItemId) called before run() processed this item',
      );
    }
    final raw = await processItem(
      batchId: batchId,
      clientUploadItemId: clientUploadItemId,
      imageBytes: unit.imageBytes,
      metadata: metadata ?? unit.metadata,
      overrideDuplicate: true,
      reviewedItem: reviewedItem ?? unit.reviewedItem,
    );
    final result = UploadItemResult.fromRaw(clientUploadItemId, raw);
    _resultsById[clientUploadItemId] = result;
    return result;
  }

  Future<Map<String, dynamic>?> fetchFinalStatus() {
    final batchId = _batchId;
    if (batchId == null) return Future.value(null);
    return getBatchStatus(batchId);
  }
}
