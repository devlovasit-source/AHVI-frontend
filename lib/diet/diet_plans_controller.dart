import 'package:myapp/models/meal_plan.dart';

// Persistence orchestration for Diet meal plans, isolated from the widget so
// the create/edit/delete lifecycle is testable with a fake gateway. Appwrite
// is the source of truth: local state changes ONLY after the remote write
// succeeds.

typedef MealPlanListFn = Future<List<MealPlan>> Function();
typedef MealPlanCreateFn = Future<String?> Function(Map<String, dynamic> payload);
typedef MealPlanUpdateFn = Future<void> Function(
    String documentId, Map<String, dynamic> payload);
typedef MealPlanDeleteFn = Future<void> Function(String documentId);

class DietPlansGateway {
  final MealPlanListFn list;
  final MealPlanCreateFn create;
  final MealPlanUpdateFn update;
  final MealPlanDeleteFn delete;
  const DietPlansGateway({
    required this.list,
    required this.create,
    required this.update,
    required this.delete,
  });
}

class DietPlansController {
  DietPlansController(this._gw);
  final DietPlansGateway _gw;

  final List<MealPlan> plans = [];
  bool loading = false;
  Object? loadError; // non-null => load failed; distinct from an empty result.

  bool get hasLoadError => loadError != null;

  /// Hydrate from Appwrite. A failure sets [loadError] and leaves [plans]
  /// untouched — a load error must never render as a real empty state.
  Future<void> hydrate() async {
    loading = true;
    loadError = null;
    try {
      final fetched = await _gw.list();
      plans
        ..clear()
        ..addAll(fetched); // gateway preserves newest-first order
    } catch (e) {
      loadError = e;
    } finally {
      loading = false;
    }
  }

  /// Persist a new plan, then keep it locally only on success. Returns the
  /// saved plan (carrying its documentId). Throws on failure — caller must not
  /// leave a fake local card.
  Future<MealPlan> create(MealPlan draft) async {
    final docId = await _gw.create(draft.toAppwritePayload());
    if (docId == null || docId.isEmpty) {
      throw StateError('meal_plan_create_no_document_id');
    }
    final saved = draft.copyWith(documentId: docId);
    plans.insert(0, saved); // newest-first
    return saved;
  }

  /// Update remote first; replace local only after Appwrite confirms. Throws
  /// on failure (original local plan preserved). documentId is authoritative.
  Future<void> edit(MealPlan updated) async {
    final id = updated.documentId;
    if (id == null || id.isEmpty) {
      throw StateError('meal_plan_edit_missing_document_id');
    }
    await _gw.update(id, updated.toAppwritePayload());
    final idx = plans.indexWhere((p) => p.documentId == id);
    if (idx != -1) plans[idx] = updated;
  }

  /// Delete remote first; drop local only after Appwrite confirms. Throws on
  /// failure (card retained).
  Future<void> delete(MealPlan plan) async {
    final id = plan.documentId;
    if (id == null || id.isEmpty) {
      throw StateError('meal_plan_delete_missing_document_id');
    }
    await _gw.delete(id);
    plans.removeWhere((p) => p.documentId == id);
  }
}
