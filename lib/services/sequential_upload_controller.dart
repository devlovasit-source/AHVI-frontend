// ============================================================
// sequential_upload_controller.dart
//
// Drives the AHVI P0 sequential upload batch: processes selected images ONE
// AT A TIME against the backend's /api/wardrobe/upload-batches endpoints,
// instead of one giant /analyze-batch + /save-selected round trip.
//
// Pure Dart, no Flutter/widget dependencies, no BackendService import - the
// three API operations are injected as plain functions (matching this
// codebase's existing testable-controller pattern, e.g.
// CalendarActionCoordinator) so this is unit-testable without a mocking
// library or a real backend.
// ============================================================

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
    });

typedef GetBatchStatusFn =
    Future<Map<String, dynamic>?> Function(String batchId);

/// One image to process through the sequential batch. `clientUploadItemId`
/// must be STABLE across retries/Add-Anyway - generated once, never derived
/// fresh per button tap.
class UploadBatchUnit {
  final String clientUploadItemId;
  final Uint8List imageBytes;
  final Map<String, dynamic>? metadata;

  const UploadBatchUnit({
    required this.clientUploadItemId,
    required this.imageBytes,
    this.metadata,
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

  /// Maps the backend's per-item response onto the typed outcome. The ONLY
  /// canonical duplicate signal is status=NEEDS_REVIEW + error_code=
  /// DUPLICATE_WARDROBE_ITEM - every other NEEDS_REVIEW reason goes through
  /// the normal (non-duplicate) review path.
  factory UploadItemResult.fromRaw(
    String clientUploadItemId,
    Map<String, dynamic>? raw,
  ) {
    final r = raw ?? const <String, dynamic>{};
    final status = (r['status'] ?? '').toString().trim().toUpperCase();
    final errorCode = r['error_code']?.toString();

    UploadItemOutcome outcome;
    if (status == 'ADDED_TO_WARDROBE') {
      outcome = UploadItemOutcome.added;
    } else if (status == 'NEEDS_REVIEW' &&
        errorCode == 'DUPLICATE_WARDROBE_ITEM') {
      outcome = UploadItemOutcome.duplicate;
    } else if (status == 'NEEDS_REVIEW') {
      outcome = UploadItemOutcome.needsReview;
    } else if (status == 'REJECTED') {
      outcome = UploadItemOutcome.rejected;
    } else {
      outcome = UploadItemOutcome.failed;
    }

    double? confidence;
    final rawConfidence = r['duplicate_confidence'];
    if (rawConfidence is num) confidence = rawConfidence.toDouble();

    return UploadItemResult(
      clientUploadItemId: clientUploadItemId,
      outcome: outcome,
      wardrobeItemId: r['wardrobe_item_id']?.toString(),
      matchedItemId: r['matched_item_id']?.toString(),
      duplicateReason: r['duplicate_reason']?.toString(),
      duplicateConfidence: confidence,
      errorCode: errorCode,
      reason: r['reason']?.toString(),
      raw: r,
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

  /// Current results in the order items were first processed. Add-anyway
  /// updates the SAME entry in place - it never appends a second row for an
  /// item that was already processed once.
  List<UploadItemResult> get results => _resultsById.values.toList();

  /// Sequentially processes [units] ONE AT A TIME - no Future.wait, no
  /// parallel dispatch. [onProgress] fires after every terminal result
  /// (added/duplicate/needs_review/rejected/failed all count as terminal)
  /// with the 1-based completed count so the UI can show "N of total".
  Future<List<UploadItemResult>> run(
    List<UploadBatchUnit> units, {
    required String clientBatchRequestId,
    void Function(int completed, int total, UploadItemResult result)?
    onProgress,
  }) async {
    final batchRes = await createOrResumeBatch(
      clientBatchRequestId: clientBatchRequestId,
      totalItems: units.length,
    );
    _batchId = (batchRes?['batch_id'] as String?) ?? clientBatchRequestId;

    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      _unitsById[unit.clientUploadItemId] = unit;
      final raw = await processItem(
        batchId: _batchId!,
        clientUploadItemId: unit.clientUploadItemId,
        imageBytes: unit.imageBytes,
        metadata: unit.metadata,
        overrideDuplicate: false,
      );
      final result = UploadItemResult.fromRaw(unit.clientUploadItemId, raw);
      _resultsById[unit.clientUploadItemId] = result;
      onProgress?.call(i + 1, units.length, result);
    }
    return results;
  }

  /// Explicit, item-scoped "Add anyway": same batchId, same
  /// client_upload_item_id, override_duplicate=true. Touches ONLY this one
  /// item - every other item's already-recorded result is untouched.
  Future<UploadItemResult> addAnyway(String clientUploadItemId) async {
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
      metadata: unit.metadata,
      overrideDuplicate: true,
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
