// ── Refactored Face Analysis Functions ──────────────────────────────────────
// All functions now use FaceScanConfig instead of hardcoded values

import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'face_scan_config.dart';

class FaceAnalysisService {

  // ── Skin Tone Extraction (data-driven) ──────────────────────────────
  Map<String, dynamic> extractSkinTone(img.Image image, Face face) {
    try {
      final bbox = face.boundingBox;

      final samplePoints = <List<double>>[
        [bbox.center.dx, bbox.top + bbox.height * 0.28], // forehead
        [bbox.left + bbox.width * 0.28, bbox.top + bbox.height * 0.58], // left cheek
        [bbox.right - bbox.width * 0.28, bbox.top + bbox.height * 0.58], // right cheek
      ];

      int rSum = 0, gSum = 0, bSum = 0, samples = 0;

      for (final point in samplePoints) {
        final x = (point[0] * image.width).toInt();
        final y = (point[1] * image.height).toInt();
        if (x < 0 || x >= image.width || y < 0 || y >= image.height) continue;

        final pixel = image.getPixelSafe(x, y);
        rSum += pixel.r.toInt();
        gSum += pixel.g.toInt();
        bSum += pixel.b.toInt();
        samples++;
      }

      if (samples == 0) {
        return {
          'label': FaceScanConfig.skinToneFallback['label'],
          'color': Color(FaceScanConfig.skinToneFallback['colorHex'] as int),
        };
      }

      final avgR = (rSum / samples).round().clamp(0, 255);
      final avgG = (gSum / samples).round().clamp(0, 255);
      final avgB = (bSum / samples).round().clamp(0, 255);
      final skinColor = Color.fromARGB(255, avgR, avgG, avgB);
      final brightness = (avgR + avgG + avgB) / 3;

      // Use configuration helper instead of hardcoded if/else
      final label = FaceScanConfig.getSkinToneLabel(brightness);

      return {'label': label, 'color': skinColor};
    } catch (e) {
      return {
        'label': FaceScanConfig.skinToneFallback['label'],
        'color': Color(FaceScanConfig.skinToneFallback['colorHex'] as int),
      };
    }
  }

  // ── Acne Detection (configurable threshold) ─────────────────────────
  Map<String, dynamic> detectAcne(img.Image image, Face face) {
    try {
      if (!FaceScanConfig.analysisFeatures['acneDetection']!) return FaceScanConfig.acneFallback;

      final bbox = face.boundingBox;
      final width = (bbox.width * image.width).toInt();
      final height = (bbox.height * image.height).toInt();
      final startX = (bbox.left * image.width).toInt().clamp(0, image.width - 1);
      final startY = (bbox.top * image.height).toInt().clamp(0, image.height - 1);

      int irregularPixels = 0;
      int totalPixels = 0;

      final regionWidth = (width * 0.8).toInt();
      final regionHeight = (height * 0.7).toInt();

      for (int x = startX; x < startX + regionWidth && x < image.width; x++) {
        for (int y = startY; y < startY + regionHeight && y < image.height; y++) {
          totalPixels++;
          final pixel = image.getPixelSafe(x, y);
          final r = pixel.r.toInt();
          final g = pixel.g.toInt();
          final b = pixel.b.toInt();

          if (r > g + 30 && r > b + 30) {
            irregularPixels++;
          }
        }
      }

      final acnePercentage = totalPixels > 0 ? (irregularPixels / totalPixels * 100).toInt() : 0;

      // Use configurable threshold from FaceScanConfig
      final detected = acnePercentage > FaceScanConfig.acneDetectionThreshold;
      final severity = acnePercentage.clamp(0, 100);

      return {
        'detected': detected,
        'severity': severity,
      };
    } catch (e) {
      return FaceScanConfig.acneFallback;
    }
  }

  // ── Pigmentation Detection (configurable threshold) ────────────────
  Map<String, dynamic> detectPigmentation(img.Image image, Face face) {
    try {
      if (!FaceScanConfig.analysisFeatures['pigmentationDetection']!) {
        return FaceScanConfig.pigmentationFallback;
      }

      final bbox = face.boundingBox;
      final width = (bbox.width * image.width).toInt();
      final height = (bbox.height * image.height).toInt();
      final startX = (bbox.left * image.width).toInt().clamp(0, image.width - 1);
      final startY = (bbox.top * image.height).toInt().clamp(0, image.height - 1);

      double totalColorVariance = 0;
      int sampleCount = 0;

      for (int x = startX; x < startX + width && x < image.width; x += 5) {
        for (int y = startY; y < startY + height && y < image.height; y += 5) {
          sampleCount++;
          final pixel = image.getPixelSafe(x, y);
          final r = pixel.r.toDouble();
          final g = pixel.g.toDouble();
          final b = pixel.b.toDouble();

          final variance = ((r - g).abs() + (g - b).abs() + (r - b).abs()) / 3;
          totalColorVariance += variance;
        }
      }

      final avgVariance = sampleCount > 0 ? totalColorVariance / sampleCount : 0;
      final intensity = (avgVariance / 100).clamp(0.0, 1.0);

      // Use configurable threshold from FaceScanConfig
      final detected = intensity > FaceScanConfig.pigmentationDetectionThreshold;

      return {
        'detected': detected,
        'intensity': intensity,
      };
    } catch (e) {
      return FaceScanConfig.pigmentationFallback;
    }
  }

  // ── Dark Circles Detection (configurable threshold) ────────────────
  bool detectDarkCircles(img.Image image, Face face) {
    try {
      if (!FaceScanConfig.analysisFeatures['darkCirclesDetection']!) {
        return FaceScanConfig.darkCirclesFallback;
      }

      final bbox = face.boundingBox;
      final underEyeY = (bbox.top + bbox.height * 0.5).toInt();
      final sampleX = (bbox.center.dx * image.width).toInt();

      if (sampleX < 0 || sampleX >= image.width || underEyeY < 0 || underEyeY >= image.height) {
        return FaceScanConfig.darkCirclesFallback;
      }

      final pixel = image.getPixelSafe(sampleX, underEyeY);
      final brightness = (pixel.r.toInt() + pixel.g.toInt() + pixel.b.toInt()) / 3;

      // Use configurable threshold from FaceScanConfig
      return brightness < FaceScanConfig.darkCirclesBrightnessThreshold;
    } catch (e) {
      return FaceScanConfig.darkCirclesFallback;
    }
  }

  // ── Skin Quality Calculation (configurable impact factors) ─────────
  double calculateSkinQuality(img.Image image, Face face) {
    try {
      if (!FaceScanConfig.analysisFeatures['skinQualityCalculation']!) {
        return FaceScanConfig.skinQualityFallback;
      }

      final acneData = detectAcne(image, face);
      final pigmentationData = detectPigmentation(image, face);

      double quality = 100.0;

      // Use configurable impact factors instead of hardcoded values
      quality -= (acneData['severity'] as int) * FaceScanConfig.acneSeverityImpact;
      quality -= ((pigmentationData['intensity'] as double) * 100) * FaceScanConfig.pigmentationImpact;

      return quality.clamp(0.0, 100.0);
    } catch (e) {
      return FaceScanConfig.skinQualityFallback;
    }
  }

  // ── IMPROVED RECOMMENDATION GENERATION (Data-Driven) ────────────────
  /// Generates personalized recommendations based on actual analysis data
  /// with graduated severity levels instead of generic suggestions
  List<String> generateRecommendations({
    required String skinTone,
    required bool hasAcne,
    required int acneSeverity,
    required bool hasPigmentation,
    required double pigmentationIntensity,
    required String eyeShape,
    required bool darkCircles,
    required String faceShape,
  }) {
    final recommendations = <String>[];
    final db = FaceScanConfig.recommendationDatabase;

    // Acne recommendations (severity-based)
    if (hasAcne) {
      final severityLevel = FaceScanConfig.getAcneSeverityLevel(acneSeverity);
      final acneMap = db['acne']! as Map<String, dynamic>;
      final acneRecs = acneMap[severityLevel] as List<dynamic>;
      recommendations.addAll(
        acneRecs.cast<String>().take(FaceScanConfig.maxRecommendationsPerCategory),
      );
    }

    // Pigmentation recommendations (severity-based)
    if (hasPigmentation) {
      final severityLevel = FaceScanConfig.getPigmentationSeverityLevel(pigmentationIntensity);
      final pigmentationMap = db['pigmentation']! as Map<String, dynamic>;
      final pigmentationRecs = pigmentationMap[severityLevel] as List<dynamic>;
      recommendations.addAll(
        pigmentationRecs.cast<String>().take(FaceScanConfig.maxRecommendationsPerCategory),
      );
    }

    // Dark circles recommendations
    if (darkCircles) {
      final darkCircleRecs = db['darkCircles'] as List<dynamic>;
      recommendations.addAll(
        darkCircleRecs.cast<String>().take(FaceScanConfig.maxRecommendationsPerCategory),
      );
    }

    // Eye shape specific recommendations
    final eyeShapeMap = db['eyeShape']! as Map<String, dynamic>;
    if (eyeShapeMap[eyeShape] != null) {
      final eyeRecs = eyeShapeMap[eyeShape] as List<dynamic>;
      recommendations.addAll(
        eyeRecs.cast<String>().take(1), // Only 1 eye shape rec to avoid clutter
      );
    }

    // Face shape specific recommendations
    final faceShapeMap = db['faceShape']! as Map<String, dynamic>;
    if (faceShapeMap[faceShape] != null) {
      final faceRecs = faceShapeMap[faceShape] as List<dynamic>;
      recommendations.addAll(
        faceRecs.cast<String>().take(1), // Only 1 face shape rec to avoid clutter
      );
    }

    // Add universal skincare recommendations
    final universal = db['universal'] as List<dynamic>;
    final needed = FaceScanConfig.maxTotalRecommendations - recommendations.length;
    if (needed > 0) {
      recommendations.addAll(
        universal.cast<String>().take(needed),
      );
    }

    // Ensure we have minimum recommendations
    if (recommendations.isEmpty) {
      recommendations.addAll(
        universal.cast<String>().take(FaceScanConfig.minTotalRecommendations),
      );
    }

    // Limit total recommendations
    return recommendations.take(FaceScanConfig.maxTotalRecommendations).toList();
  }

  /// Get user-friendly description of analysis quality
  String getAnalysisSummary({
    required double skinQuality,
    required bool acneDetected,
    required bool pigmentationDetected,
    required bool darkCircles,
  }) {
    final rating = FaceScanConfig.getSkinQualityRating(skinQuality);
    final issues = <String>[];

    if (acneDetected) issues.add('acne');
    if (pigmentationDetected) issues.add('pigmentation');
    if (darkCircles) issues.add('dark circles');

    if (issues.isEmpty) {
      return '$rating skin condition detected.';
    }

    return '$rating skin condition. Detected: ${issues.join(", ")}.';
  }
}