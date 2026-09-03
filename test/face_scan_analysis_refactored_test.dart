import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/services/face_scan/face_scan_analysis_refactored.dart';
import 'package:myapp/services/face_scan/face_scan_config.dart';

void main() {
  group('FaceScanConfig thresholds', () {
    test('acne severity buckets switch at the documented boundaries', () {
      expect(FaceScanConfig.getAcneSeverityLevel(0), 'mild');
      expect(FaceScanConfig.getAcneSeverityLevel(15), 'mild');
      expect(FaceScanConfig.getAcneSeverityLevel(16), 'moderate');
      expect(FaceScanConfig.getAcneSeverityLevel(35), 'moderate');
      expect(FaceScanConfig.getAcneSeverityLevel(36), 'severe');
    });

    test('pigmentation severity buckets switch at the documented boundaries', () {
      expect(FaceScanConfig.getPigmentationSeverityLevel(0.0), 'mild');
      expect(FaceScanConfig.getPigmentationSeverityLevel(0.4), 'mild');
      expect(FaceScanConfig.getPigmentationSeverityLevel(0.41), 'moderate');
      expect(FaceScanConfig.getPigmentationSeverityLevel(0.65), 'moderate');
      expect(FaceScanConfig.getPigmentationSeverityLevel(0.66), 'severe');
    });
  });

  test('recommendations and summary stay non-diagnostic', () {
    final service = FaceAnalysisService();
    final recs = service.generateRecommendations(
      skinTone: 'Medium',
      hasAcne: true,
      acneSeverity: 80,
      hasPigmentation: true,
      pigmentationIntensity: 0.9,
      eyeShape: 'Hooded',
      darkCircles: true,
      faceShape: 'Oval',
    );
    final summary = service.getAnalysisSummary(
      skinQuality: 42,
      acneDetected: true,
      pigmentationDetected: true,
      darkCircles: true,
    );

    expect(recs.length, lessThanOrEqualTo(FaceScanConfig.maxTotalRecommendations));
    expect(
      recs.join(' '),
      isNot(contains(RegExp(r'\b(detected|diagnos|prescription|laser|chemical peels)\b', caseSensitive: false))),
    );
    expect(summary, contains('skin profile review'));
    expect(summary, isNot(contains('detected')));
  });
}
