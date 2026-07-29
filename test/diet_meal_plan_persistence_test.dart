// Focused tests for the Diet meal-plan persistence lifecycle.
//
// Pure model + controller — no widget harness. Appwrite is faked with an
// in-memory store so create/edit/delete round-trip through the same payload
// path the real gateway uses.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/models/meal_plan.dart';
import 'package:myapp/diet/diet_plans_controller.dart';

Meal _meal(String name, {String type = 'lunch', int cal = 100}) =>
    Meal(type: type, name: name, desc: '', cal: cal, cls: '');

MealPlan _draft(String name, {List<Meal>? meals}) => MealPlan(
      id: name.hashCode,
      name: name,
      desc: 'desc-$name',
      planType: 'daily',
      meals: meals ?? [_meal('$name-meal')],
    );

/// In-memory Appwrite stand-in. Persists payloads keyed by generated $id and
/// serves them back newest-first, exactly like getMealPlans(orderDesc).
class _FakeBackend {
  final Map<String, Map<String, dynamic>> docs = {};
  final List<String> order = []; // newest-first
  int _seq = 0;

  Future<String?> create(Map<String, dynamic> payload) async {
    final id = 'doc_${++_seq}';
    docs[id] = {r'$id': id, ...payload};
    order.insert(0, id);
    return id;
  }

  Future<void> update(String id, Map<String, dynamic> payload) async {
    if (!docs.containsKey(id)) throw StateError('no such doc: $id');
    docs[id] = {r'$id': id, ...payload};
  }

  Future<void> delete(String id) async {
    docs.remove(id);
    order.remove(id);
  }

  Future<List<MealPlan>> list() async => order
      .map((id) => mealPlanFromDocumentData(docs[id]!))
      .whereType<MealPlan>()
      .toList();

  DietPlansGateway gateway() => DietPlansGateway(
        list: list,
        create: create,
        update: update,
        delete: delete,
      );
}

void main() {
  // ── Model / parser ────────────────────────────────────────────────────────

  test('parser hydrates documentId, name and meals from a document', () {
    final plan = mealPlanFromDocumentData({
      r'$id': 'abc123',
      'name': 'Cut Plan',
      'desc': 'lean',
      'planType': 'daily',
      'meals': [
        {'type': 'lunch', 'name': 'Dal Rice', 'cal': 400},
      ],
    });
    expect(plan, isNotNull);
    expect(plan!.documentId, 'abc123');
    expect(plan.name, 'Cut Plan');
    expect(plan.meals.single.name, 'Dal Rice');
    expect(plan.meals.single.cal, 400);
  });

  test('JSON-string meals decode correctly', () {
    final plan = mealPlanFromDocumentData({
      r'$id': 'p1',
      'name': 'P',
      'planType': 'daily',
      'meals': [
        jsonEncode({'type': 'breakfast', 'name': 'Poha', 'cal': '250'}),
      ],
    });
    expect(plan!.meals.single.name, 'Poha');
    expect(plan.meals.single.type, 'breakfast');
    expect(plan.meals.single.cal, 250); // string cal parsed safely
  });

  test('malformed meal entries are ignored safely', () {
    final plan = mealPlanFromDocumentData({
      r'$id': 'p1',
      'name': 'P',
      'planType': 'daily',
      'meals': [
        {'type': 'lunch', 'name': 'Good', 'cal': 300},
        'not-json {',        // undecodable string
        {'no_name': 1},      // dict without name
        '',                   // empty
        123,                  // wrong type
      ],
    });
    expect(plan!.meals.length, 1);
    expect(plan.meals.single.name, 'Good');
  });

  test('toAppwritePayload contains only schema-supported fields', () {
    final payload = _draft('Plan A').toAppwritePayload();
    expect(payload.keys.toSet(),
        {'name', 'desc', 'planType', 'totalCal', 'meals'});
    expect(payload.containsKey('userId'), isFalse);
    expect(payload.containsKey(r'$id'), isFalse);
    expect(payload.containsKey(r'$createdAt'), isFalse);
    expect(payload['meals'], isA<List>());
    // meals serialised as compact JSON strings
    final first = jsonDecode((payload['meals'] as List).first as String);
    expect(first['name'], 'Plan A-meal');
  });

  test('copyWith preserves documentId', () {
    final p = _draft('P').copyWith(documentId: 'doc_9');
    expect(p.documentId, 'doc_9');
    expect(p.copyWith(name: 'Renamed').documentId, 'doc_9');
  });

  // ── Hydration ─────────────────────────────────────────────────────────────

  test('Appwrite rows hydrate after initialization', () async {
    final be = _FakeBackend();
    await be.create(_draft('P1').toAppwritePayload());
    final c = DietPlansController(be.gateway());
    await c.hydrate();
    expect(c.plans.length, 1);
    expect(c.plans.first.name, 'P1');
    expect(c.plans.first.documentId, 'doc_1');
    expect(c.hasLoadError, isFalse);
  });

  test('app restart restores saved plan', () async {
    final be = _FakeBackend();
    final c1 = DietPlansController(be.gateway());
    await c1.create(_draft('Persisted'));
    // Simulate restart: brand-new controller, same backend store.
    final c2 = DietPlansController(be.gateway());
    await c2.hydrate();
    expect(c2.plans.single.name, 'Persisted');
    expect(c2.plans.single.documentId, 'doc_1');
  });

  test('loading failure differs from empty state', () async {
    final failing = DietPlansController(DietPlansGateway(
      list: () async => throw StateError('network down'),
      create: (_) async => null,
      update: (_, __) async {},
      delete: (_) async {},
    ));
    await failing.hydrate();
    expect(failing.hasLoadError, isTrue);
    expect(failing.plans, isEmpty);

    final empty = DietPlansController(_FakeBackend().gateway());
    await empty.hydrate();
    expect(empty.hasLoadError, isFalse);
    expect(empty.plans, isEmpty);
  });

  // ── Create ────────────────────────────────────────────────────────────────

  test('create success retains documentId', () async {
    final be = _FakeBackend();
    final c = DietPlansController(be.gateway());
    final saved = await c.create(_draft('New'));
    expect(saved.documentId, 'doc_1');
    expect(c.plans.single.documentId, 'doc_1');
    expect(be.docs.containsKey('doc_1'), isTrue);
  });

  test('create failure leaves no fake local card', () async {
    final c = DietPlansController(DietPlansGateway(
      list: () async => [],
      create: (_) async => throw StateError('write failed'),
      update: (_, __) async {},
      delete: (_) async {},
    ));
    await expectLater(c.create(_draft('Ghost')), throwsA(isA<StateError>()));
    expect(c.plans, isEmpty);
  });

  // ── Update ────────────────────────────────────────────────────────────────

  test('edit calls update with correct documentId and schema-only payload',
      () async {
    String? gotId;
    Map<String, dynamic>? gotPayload;
    final be = _FakeBackend();
    final c = DietPlansController(DietPlansGateway(
      list: be.list,
      create: be.create,
      update: (id, payload) async {
        gotId = id;
        gotPayload = payload;
        await be.update(id, payload);
      },
      delete: be.delete,
    ));
    final saved = await c.create(_draft('Orig'));
    final updated = saved.copyWith(name: 'Edited', meals: [_meal('New Meal')]);

    await c.edit(updated);

    expect(gotId, saved.documentId);
    expect(gotPayload!.keys.toSet(),
        {'name', 'desc', 'planType', 'totalCal', 'meals'});
    expect(gotPayload!.containsKey('userId'), isFalse);
    expect(gotPayload!['name'], 'Edited');
  });

  test('edit success updates local state', () async {
    final be = _FakeBackend();
    final c = DietPlansController(be.gateway());
    final saved = await c.create(_draft('Before'));
    await c.edit(saved.copyWith(name: 'After'));
    expect(c.plans.single.name, 'After');
  });

  test('edit failure preserves the original local values', () async {
    final be = _FakeBackend();
    final c = DietPlansController(DietPlansGateway(
      list: be.list,
      create: be.create,
      update: (_, __) async => throw StateError('update failed'),
      delete: be.delete,
    ));
    final saved = await c.create(_draft('Original'));
    await expectLater(
        c.edit(saved.copyWith(name: 'Broken')), throwsA(isA<StateError>()));
    expect(c.plans.single.name, 'Original');
  });

  test('local state is not changed before Appwrite confirms the update',
      () async {
    final gate = Completer<void>();
    final be = _FakeBackend();
    final c = DietPlansController(DietPlansGateway(
      list: be.list,
      create: be.create,
      update: (id, payload) async {
        await gate.future; // block until we allow it
        await be.update(id, payload);
      },
      delete: be.delete,
    ));
    final saved = await c.create(_draft('Pending'));
    final fut = c.edit(saved.copyWith(name: 'Confirmed'));
    await Future(() {}); // let edit reach the await
    expect(c.plans.single.name, 'Pending', reason: 'no local change pre-confirm');
    gate.complete();
    await fut;
    expect(c.plans.single.name, 'Confirmed');
  });

  test('edit blocked when documentId missing', () async {
    final c = DietPlansController(_FakeBackend().gateway());
    await expectLater(
        c.edit(_draft('NoId')), throwsA(isA<StateError>()));
  });

  // ── Delete ────────────────────────────────────────────────────────────────

  test('delete success removes remote and local plan', () async {
    final be = _FakeBackend();
    final c = DietPlansController(be.gateway());
    final saved = await c.create(_draft('DropMe'));
    await c.delete(saved);
    expect(c.plans, isEmpty);
    expect(be.docs.containsKey('doc_1'), isFalse);
  });

  test('delete failure retains local plan', () async {
    final be = _FakeBackend();
    final c = DietPlansController(DietPlansGateway(
      list: be.list,
      create: be.create,
      update: be.update,
      delete: (_) async => throw StateError('delete failed'),
    ));
    final saved = await c.create(_draft('Keep'));
    await expectLater(c.delete(saved), throwsA(isA<StateError>()));
    expect(c.plans.single.name, 'Keep');
  });
}
