import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Daily Wear presents Occasion Selection sheet on Save', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();
    expect(source, contains('_showOccasionSaveSheet('));
    expect(source, contains('Save this look to'));
    expect(source, contains("('party_looks', 'Party Looks'"));
    expect(source, contains("('office_fits', 'Office Fits'"));
    expect(source, contains("('vacation', 'Vacation'"));
    expect(source, contains("('occasion', 'Occasion'"));
    expect(source, contains("('everything_else', 'Everything Else'"));
    expect(source, contains('Add to Favourites'));
  });

  test('Daily Wear save persists selected occasion selection', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();
    final saveMethod = source.substring(
      source.indexOf('Future<bool> _saveOutfitToBoards'),
      source.indexOf('Future<void> _shareDailyWearBoard'),
    );

    expect(saveMethod, contains('final selection = await _showOccasionSaveSheet();'));
    expect(saveMethod, contains('selection: selection'));
    expect(saveMethod, contains('SavedBoardsStore.saveBoard('));
    expect(saveMethod, contains('AppwriteService().saveBoardToCollection('));
    expect(saveMethod, contains('Saved look to \$bucketLabel'));
  });

  test('Daily Wear share integrates ShareableOutfitBoard image and text via share_plus', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();
    expect(source, contains('_shareDailyWearBoard('));
    expect(source, contains('ShareableOutfitBoard('));
    expect(source, contains('SharePlus.instance.share('));
    expect(source, contains('ShareParams('));
    expect(source, contains("mimeType: 'image/png'"));
    expect(source, contains('text: caption'));
    expect(source, contains('subject: resolvedTitle'));
    expect(source, contains('getTemporaryDirectory()'));
  });

  test('Daily Wear share buttons delegate to _shareDailyWearBoard', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();
    expect(source, contains('Widget _circleShare(Map<String, dynamic> outfit)'));
    expect(source, contains('_shareDailyWearBoard(outfit)'));
    expect(source, contains('Widget _smallShare(String outfitId)'));
    expect(source, contains('_shareDailyWearBoard('));
  });
}
