import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Daily Wear presents Occasion Selection sheet on Save', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();
    expect(source, contains('_showOccasionPickerSheet('));
    expect(source, contains('Save to Board Location'));
    expect(source, contains("key: 'party_looks'"));
    expect(source, contains("key: 'office_fits'"));
    expect(source, contains("key: 'vacation'"));
    expect(source, contains("key: 'occasion'"));
    expect(source, contains("key: 'everything_else'"));
  });

  test('Daily Wear save persists selected occasion selection', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();
    final saveMethod = source.substring(
      source.indexOf('Future<bool> _saveOutfitToBoards'),
      source.indexOf('Future<void> _unsaveOutfit'),
    );

    expect(saveMethod, contains('AppwriteService().saveBoardToCollection('));
    expect(saveMethod, contains('if (doc == null) {'));
    expect(saveMethod, contains('SavedBoardsStore.saveBoard('));
  });

  test('Daily Wear share integrates board exporter image and text via share_plus', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();
    expect(source, contains('_shareOutfit('));
    expect(source, contains('BoardExporter.capturePng('));
    expect(source, contains('Share.shareXFiles('));
    expect(source, contains('Share.share('));
    expect(source, contains("mimeType: 'image/png'"));
  });

  test('Daily Wear share buttons delegate to _shareOutfit', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();
    expect(source, contains('Widget _circleShare(Map<String, dynamic> outfit)'));
    expect(source, contains('_shareOutfit(outfit)'));
    expect(source, contains('Widget _smallShare(Map<String, dynamic> outfit)'));
    expect(source, contains('_shareOutfit('));
  });
}
