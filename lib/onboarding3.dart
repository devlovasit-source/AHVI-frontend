import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myapp/app_routes.dart';
import 'package:myapp/profile.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
// ✅ NEW: Import the refactored analysis service and config
import 'package:myapp/services/face_scan/face_scan_analysis_refactored.dart';
import 'package:myapp/services/face_scan/face_scan_config.dart';

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.system,
    theme: ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.light.bg2,
      extensions: const [AppColors.light],
    ),
    darkTheme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.dark.bg2,
      extensions: const [AppColors.dark],
    ),
    home: const Screen3(),
  ));
}

// ── Theme-aware color tokens ────────────────────────────────────────────────
// All colors used across this screen live here as a ThemeExtension so every
// widget can pick up the right palette for light/dark mode via
// `context.colors` instead of hardcoded constants.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color bg;
  final Color bg2;
  final Color panel;
  final Color panel2;
  final Color card;
  final Color cardBorder;
  final Color text;
  final Color muted;
  final Color accent1;
  final Color accent2;
  final Color accent3;
  final Color accent4;
  final Color danger;
  final Color warning;
  final Color statusPurple;
  final Color statusPink;
  final Color onAccent;
  final Color recommendationBg;
  final Color recommendationBorder;
  final Color recommendationTitle;
  final Color uploadedBg;
  final Color privacyTint;
  final Color dotInactive;

  const AppColors({
    required this.bg,
    required this.bg2,
    required this.panel,
    required this.panel2,
    required this.card,
    required this.cardBorder,
    required this.text,
    required this.muted,
    required this.accent1,
    required this.accent2,
    required this.accent3,
    required this.accent4,
    required this.danger,
    required this.warning,
    required this.statusPurple,
    required this.statusPink,
    required this.onAccent,
    required this.recommendationBg,
    required this.recommendationBorder,
    required this.recommendationTitle,
    required this.uploadedBg,
    required this.privacyTint,
    required this.dotInactive,
  });

  // ── Light Mode ──────────────────────────────────────────────────────────
  static const light = AppColors(
    bg: Color(0xFFEEF3FF),
    bg2: Color(0xFFFFFFFF),
    panel: Color(0xA8FFFFFF),
    panel2: Color(0x33C5CDED),
    card: Color(0xE0FFFFFF),
    cardBorder: Color(0xFFE5E9F7),
    text: Color(0xFF1A1D26),
    muted: Color(0xFF66708A),
    accent1: Color(0xFF6B91FF),
    accent2: Color(0xFF8D7DFF),
    accent3: Color(0xFF04D7C8),
    accent4: Color(0xFF14CACD),
    danger: Color(0xFFE5484D),
    warning: Color(0xFFF5A524),
    statusPurple: Color(0xFF8B5CF6),
    statusPink: Color(0xFFEC4899),
    onAccent: Color(0xFFFFFFFF),
    recommendationBg: Color(0xFFFFF8E8),
    recommendationBorder: Color(0xFFFFE5B4),
    recommendationTitle: Color(0xFFD97706),
    uploadedBg: Color(0xFFE8F5FF),
    privacyTint: Color(0x1204D7C8),
    dotInactive: Color(0x608D7DFF),
  );

  // ── Dark Mode ───────────────────────────────────────────────────────────
  static const dark = AppColors(
    bg: Color(0xFF0A0E17),
    bg2: Color(0xFF0B0F19),
    panel: Color(0xA8232838),
    panel2: Color(0x3336405C),
    card: Color(0xE0161B28),
    cardBorder: Color(0xFF2A3142),
    text: Color(0xFFF2F4FA),
    muted: Color(0xFF9AA3BD),
    accent1: Color(0xFF7DA3FF),
    accent2: Color(0xFF9C8CFF),
    accent3: Color(0xFF1FE6D6),
    accent4: Color(0xFF2DD9DB),
    danger: Color(0xFFFF6B6E),
    warning: Color(0xFFFFC94D),
    statusPurple: Color(0xFFA78BFA),
    statusPink: Color(0xFFF472B6),
    onAccent: Color(0xFFFFFFFF),
    recommendationBg: Color(0xFF3A2E12),
    recommendationBorder: Color(0xFF5C4720),
    recommendationTitle: Color(0xFFFFC66D),
    uploadedBg: Color(0xFF163333),
    privacyTint: Color(0x1F1FE6D6),
    dotInactive: Color(0x609C8CFF),
  );

  @override
  AppColors copyWith({
    Color? bg,
    Color? bg2,
    Color? panel,
    Color? panel2,
    Color? card,
    Color? cardBorder,
    Color? text,
    Color? muted,
    Color? accent1,
    Color? accent2,
    Color? accent3,
    Color? accent4,
    Color? danger,
    Color? warning,
    Color? statusPurple,
    Color? statusPink,
    Color? onAccent,
    Color? recommendationBg,
    Color? recommendationBorder,
    Color? recommendationTitle,
    Color? uploadedBg,
    Color? privacyTint,
    Color? dotInactive,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      bg2: bg2 ?? this.bg2,
      panel: panel ?? this.panel,
      panel2: panel2 ?? this.panel2,
      card: card ?? this.card,
      cardBorder: cardBorder ?? this.cardBorder,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      accent1: accent1 ?? this.accent1,
      accent2: accent2 ?? this.accent2,
      accent3: accent3 ?? this.accent3,
      accent4: accent4 ?? this.accent4,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      statusPurple: statusPurple ?? this.statusPurple,
      statusPink: statusPink ?? this.statusPink,
      onAccent: onAccent ?? this.onAccent,
      recommendationBg: recommendationBg ?? this.recommendationBg,
      recommendationBorder: recommendationBorder ?? this.recommendationBorder,
      recommendationTitle: recommendationTitle ?? this.recommendationTitle,
      uploadedBg: uploadedBg ?? this.uploadedBg,
      privacyTint: privacyTint ?? this.privacyTint,
      dotInactive: dotInactive ?? this.dotInactive,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      bg2: Color.lerp(bg2, other.bg2, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      panel2: Color.lerp(panel2, other.panel2, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent1: Color.lerp(accent1, other.accent1, t)!,
      accent2: Color.lerp(accent2, other.accent2, t)!,
      accent3: Color.lerp(accent3, other.accent3, t)!,
      accent4: Color.lerp(accent4, other.accent4, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      statusPurple: Color.lerp(statusPurple, other.statusPurple, t)!,
      statusPink: Color.lerp(statusPink, other.statusPink, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      recommendationBg: Color.lerp(recommendationBg, other.recommendationBg, t)!,
      recommendationBorder: Color.lerp(recommendationBorder, other.recommendationBorder, t)!,
      recommendationTitle: Color.lerp(recommendationTitle, other.recommendationTitle, t)!,
      uploadedBg: Color.lerp(uploadedBg, other.uploadedBg, t)!,
      privacyTint: Color.lerp(privacyTint, other.privacyTint, t)!,
      dotInactive: Color.lerp(dotInactive, other.dotInactive, t)!,
    );
  }
}

/// Shortcut so any widget can just call `context.colors.text`, etc.
extension AppColorsX on BuildContext {
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.light;
}

// ── Facial Analysis Data Model ───────────────────────────────────
class FaceAnalysisData {
  final bool faceDetected;
  final String faceShape;
  final String skinTone;
  final Color skinToneColor;
  final double skinQuality;
  final bool acneDetected;
  final int acneSeverity; // 0-100
  final bool pigmentationDetected;
  final double pigmentationIntensity; // 0-1
  final String eyeShape;
  final double eyeSize; // 0-1
  final String lipColor;
  final double lipFullness; // 0-1
  final bool darkerCircles; // Under eye
  final List<String> recommendations;

  FaceAnalysisData({
    required this.faceDetected,
    required this.faceShape,
    required this.skinTone,
    required this.skinToneColor,
    required this.skinQuality,
    required this.acneDetected,
    required this.acneSeverity,
    required this.pigmentationDetected,
    required this.pigmentationIntensity,
    required this.eyeShape,
    required this.eyeSize,
    required this.lipColor,
    required this.lipFullness,
    required this.darkerCircles,
    required this.recommendations,
  });
}

class Screen3 extends StatefulWidget {
  const Screen3({super.key});

  @override
  State<Screen3> createState() => _Screen3State();
}

class _Screen3State extends State<Screen3> {
  bool _personalizationEnabled = false;
  bool _faceUploaded = false;
  bool _bodyUploaded = false;
  int _activeTab = 3;
  final ImagePicker _picker = ImagePicker();

  // Face analysis related
  late FaceDetector _faceDetector;
  FaceAnalysisData? _faceAnalysisData;
  bool _isAnalyzingFace = false;
  File? _selectedFaceImage;

  // ✅ NEW: Add analysis service instance
  late FaceAnalysisService _analysisService;

  @override
  void initState() {
    super.initState();
    _initializeFaceDetector();
    // ✅ NEW: Initialize the analysis service
    _analysisService = FaceAnalysisService();
  }

  void _initializeFaceDetector() {
    final options = FaceDetectorOptions(
      enableLandmarks: true,
      enableClassification: true,
      enableContours: true,
    );
    _faceDetector = FaceDetector(options: options);
  }

  @override
  void dispose() {
    _faceDetector.close();
    super.dispose();
  }

  bool get _isValid {
    if (!_personalizationEnabled) return true;
    return _faceUploaded && _bodyUploaded;
  }

  // ── Advanced Face Analysis Function ────────────────────────────
  Future<void> _analyzeFaceAdvanced(File imageFile) async {
    setState(() => _isAnalyzingFace = true);

    try {
      final inputImage = InputImage.fromFile(imageFile);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        _showValidationError('No face detected. Please capture a clear face photo.');
        setState(() => _isAnalyzingFace = false);
        return;
      }

      // Read image for color analysis
      final imageBytes = await imageFile.readAsBytes();
      final decodedImage = img.decodeImage(imageBytes);

      if (decodedImage == null) {
        _showValidationError('Failed to process image.');
        setState(() => _isAnalyzingFace = false);
        return;
      }

      final face = faces.first;

      // Extract facial features
      final faceShape = _analyzeFaceShape(face);

      // ✅ CHANGED: Use service methods instead of local methods
      final skinToneData = _analysisService.extractSkinTone(decodedImage, face);
      final skinTone = skinToneData['label'] as String;
      final skinToneColor = skinToneData['color'] as Color;

      final skinQuality = _analysisService.calculateSkinQuality(decodedImage, face);
      final acneData = _analysisService.detectAcne(decodedImage, face);
      final pigmentationData = _analysisService.detectPigmentation(decodedImage, face);

      final eyeShapeData = _analyzeEyeShape(face);
      final lipColorData = _analyzeLipColor(decodedImage, face);
      final darkerCircles = _analysisService.detectDarkCircles(decodedImage, face);

      // ✅ CHANGED: Use severity-aware recommendation generation
      final recommendations = _analysisService.generateRecommendations(
        skinTone: skinTone,
        hasAcne: acneData['detected'] as bool,
        acneSeverity: acneData['severity'] as int, // ← Now includes severity
        hasPigmentation: pigmentationData['detected'] as bool,
        pigmentationIntensity: pigmentationData['intensity'] as double, // ← Now includes intensity
        eyeShape: eyeShapeData,
        darkCircles: darkerCircles,
        faceShape: faceShape,
      );

      final analysisData = FaceAnalysisData(
        faceDetected: true,
        faceShape: faceShape,
        skinTone: skinTone,
        skinToneColor: skinToneColor,
        skinQuality: skinQuality,
        acneDetected: acneData['detected'] as bool,
        acneSeverity: acneData['severity'] as int,
        pigmentationDetected: pigmentationData['detected'] as bool,
        pigmentationIntensity: pigmentationData['intensity'] as double,
        eyeShape: eyeShapeData,
        eyeSize: _calculateEyeSize(face),
        lipColor: lipColorData,
        lipFullness: _calculateLipFullness(face),
        darkerCircles: darkerCircles,
        recommendations: recommendations,
      );

      setState(() {
        _faceAnalysisData = analysisData;
        _faceUploaded = true;
        _selectedFaceImage = imageFile;
        _isAnalyzingFace = false;
      });

      debugPrint('Advanced Face Analysis Complete');
    } catch (e) {
      debugPrint('Face analysis error: $e');
      _showValidationError('Failed to analyze face. Try again.');
      setState(() => _isAnalyzingFace = false);
    }
  }

  // ── Eye Shape Analysis ────────────────────────────────────────
  String _analyzeEyeShape(Face face) {
    try {
      if (face.landmarks.isEmpty) return 'Standard';

      // Analyze eye landmarks (landmarks is a Map, use .values)
      final leftEyeLandmark = face.landmarks.values.firstWhere(
            (lm) => lm?.type == FaceLandmarkType.leftEye,
        orElse: () => null,
      );

      // Null check before accessing position
      if (leftEyeLandmark == null) return 'Standard';

      final position = leftEyeLandmark.position;
      // Simple heuristic based on eye position relative to face
      // Use .y instead of .dy for Point<int>
      if (position.y < face.boundingBox.top + face.boundingBox.height * 0.4) {
        return 'Almond';
      } else if (position.y > face.boundingBox.top + face.boundingBox.height * 0.45) {
        return 'Hooded';
      } else {
        return 'Round';
      }
    } catch (e) {
      return 'Standard';
    }
  }

  // ── Face Shape Analysis ─────────────────────────────────────────
  // Uses the ML Kit face oval contour to compare forehead, cheekbone,
  // and jaw widths against overall face length for a heuristic
  // classification (Oval, Round, Square, Heart, Diamond, Oblong).
  String _analyzeFaceShape(Face face) {
    try {
      final faceContour = face.contours[FaceContourType.face];
      final points = faceContour?.points;

      if (points == null || points.length < 8) {
        return _analyzeFaceShapeFromBoundingBox(face);
      }

      double minX = points.first.x.toDouble();
      double maxX = points.first.x.toDouble();
      double minY = points.first.y.toDouble();
      double maxY = points.first.y.toDouble();

      for (final p in points) {
        final x = p.x.toDouble();
        final y = p.y.toDouble();
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }

      final faceLength = maxY - minY;
      final faceWidth = maxX - minX;
      if (faceWidth <= 0 || faceLength <= 0) return 'Oval';

      // Bucket contour points into thirds by vertical position to
      // approximate forehead / cheekbone / jaw band widths.
      final topThird = minY + faceLength * 0.33;
      final bottomThird = minY + faceLength * 0.66;

      double foreheadMinX = double.infinity, foreheadMaxX = -double.infinity;
      double cheekMinX = double.infinity, cheekMaxX = -double.infinity;
      double jawMinX = double.infinity, jawMaxX = -double.infinity;

      for (final p in points) {
        final x = p.x.toDouble();
        final y = p.y.toDouble();
        if (y <= topThird) {
          if (x < foreheadMinX) foreheadMinX = x;
          if (x > foreheadMaxX) foreheadMaxX = x;
        } else if (y <= bottomThird) {
          if (x < cheekMinX) cheekMinX = x;
          if (x > cheekMaxX) cheekMaxX = x;
        } else {
          if (x < jawMinX) jawMinX = x;
          if (x > jawMaxX) jawMaxX = x;
        }
      }

      // If any band had no points, fall back to overall face width.
      final foreheadWidth = (foreheadMaxX > foreheadMinX) ? foreheadMaxX - foreheadMinX : faceWidth;
      final cheekWidth = (cheekMaxX > cheekMinX) ? cheekMaxX - cheekMinX : faceWidth;
      final jawWidth = (jawMaxX > jawMinX) ? jawMaxX - jawMinX : faceWidth;

      final lengthToWidthRatio = faceLength / faceWidth;
      final jawToCheekRatio = jawWidth / cheekWidth;
      final foreheadToJawRatio = foreheadWidth / jawWidth;

      if (lengthToWidthRatio > 1.55) {
        return 'Oblong';
      } else if (foreheadToJawRatio > 1.15 && jawToCheekRatio < 0.85) {
        return 'Heart';
      } else if (cheekWidth > foreheadWidth * 1.08 && cheekWidth > jawWidth * 1.08) {
        return 'Diamond';
      } else if (jawToCheekRatio > 0.92 && foreheadWidth > cheekWidth * 0.92 && lengthToWidthRatio < 1.15) {
        return 'Square';
      } else if (jawToCheekRatio > 0.85 && lengthToWidthRatio < 1.3) {
        return 'Round';
      } else {
        return 'Oval';
      }
    } catch (e) {
      return _analyzeFaceShapeFromBoundingBox(face);
    }
  }

  // Rough fallback when contour points aren't available — uses the
  // overall bounding-box aspect ratio only.
  String _analyzeFaceShapeFromBoundingBox(Face face) {
    try {
      final ratio = face.boundingBox.height / face.boundingBox.width;
      if (ratio > 1.4) return 'Oblong';
      if (ratio < 1.15) return 'Round';
      return 'Oval';
    } catch (e) {
      return 'Oval';
    }
  }

  // ── Eye Size Calculation ──────────────────────────────────────
  // Uses ML Kit's actual left/right eye contour points (not a fixed
  // ratio) so the result genuinely varies per photo.
  double _calculateEyeSize(Face face) {
    try {
      final leftEye = face.contours[FaceContourType.leftEye]?.points;
      final rightEye = face.contours[FaceContourType.rightEye]?.points;
      final faceWidth = face.boundingBox.width;

      if (leftEye == null ||
          rightEye == null ||
          leftEye.isEmpty ||
          rightEye.isEmpty ||
          faceWidth <= 0) {
        return 0.5;
      }

      double contourWidth(List<dynamic> points) {
        double minX = points.first.x.toDouble();
        double maxX = points.first.x.toDouble();
        for (final p in points) {
          final x = p.x.toDouble();
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
        }
        return maxX - minX;
      }

      final avgEyeWidth =
          (contourWidth(leftEye) + contourWidth(rightEye)) / 2;

      // An average eye spans roughly 20% of face width; normalize
      // around that so typical eyes land near 0.5, wider/narrower
      // eyes shift proportionally.
      final ratio = avgEyeWidth / faceWidth;
      return (ratio / 0.20).clamp(0.0, 1.0);
    } catch (e) {
      return 0.5;
    }
  }

  // ── Lip Color Analysis ────────────────────────────────────────
  String _analyzeLipColor(img.Image image, Face face) {
    try {
      final bbox = face.boundingBox;
      final centerX = (bbox.center.dx * image.width).toInt();
      final centerY = (bbox.bottom * image.height * 0.95).toInt();

      if (centerX < 0 || centerX >= image.width || centerY < 0 || centerY >= image.height) {
        return 'Natural';
      }

      final pixel = image.getPixelSafe(centerX, centerY);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();

      if (r > g + 20 && r > b + 20) {
        return 'Deep Red/Pink';
      } else if (r > g && r > b) {
        return 'Warm Tone';
      } else if (b > r && b > g) {
        return 'Cool Tone';
      } else {
        return 'Natural';
      }
    } catch (e) {
      return 'Natural';
    }
  }

  // ── Lip Fullness Calculation ──────────────────────────────────
  // Uses ML Kit's actual upper/lower lip contour points (not a fixed
  // ratio) so the result genuinely varies per photo.
  double _calculateLipFullness(Face face) {
    try {
      final upperTop = face.contours[FaceContourType.upperLipTop]?.points;
      final lowerBottom =
          face.contours[FaceContourType.lowerLipBottom]?.points;
      final faceHeight = face.boundingBox.height;

      if (upperTop == null ||
          lowerBottom == null ||
          upperTop.isEmpty ||
          lowerBottom.isEmpty ||
          faceHeight <= 0) {
        return 0.5;
      }

      double avgY(List<dynamic> points) =>
          points.map((p) => p.y.toDouble()).reduce((a, b) => a + b) /
              points.length;

      // Total visible lip span: top of upper lip to bottom of lower lip.
      final lipHeight = (avgY(lowerBottom) - avgY(upperTop)).abs();

      // Lips typically span roughly 12% of face height; normalize
      // around that so average lips land near 0.5.
      final ratio = lipHeight / faceHeight;
      return (ratio / 0.12).clamp(0.0, 1.0);
    } catch (e) {
      return 0.5;
    }
  }

  void _showValidationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _captureFacePhoto() async {
    // ── Request camera permission before opening camera ──────────
    final status = await Permission.camera.request();

    if (status.isPermanentlyDenied) {
      _showValidationError('Camera permission denied. Please enable it in Settings.');
      await openAppSettings();
      return;
    }

    if (!status.isGranted) {
      _showValidationError('Camera permission is required for face scan.');
      return;
    }

    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
      );

      if (photo != null) {
        debugPrint('Face photo captured: ${photo.path}');
        await _analyzeFaceAdvanced(File(photo.path));
      }
    } catch (e) {
      debugPrint('Error capturing face photo: $e');
      _showValidationError('Failed to capture face photo');
    }
  }

  Future<void> _captureBodyPhoto() async {
    // ── Request camera permission before opening camera ──────────
    final status = await Permission.camera.request();

    if (status.isPermanentlyDenied) {
      _showValidationError('Camera permission denied. Please enable it in Settings.');
      await openAppSettings();
      return;
    }

    if (!status.isGranted) {
      _showValidationError('Camera permission is required for body photo.');
      return;
    }

    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,   // Rear camera for full body
      );

      if (photo != null) {
        debugPrint('Body photo captured: ${photo.path}');
        setState(() => _bodyUploaded = true);
      }
    } catch (e) {
      debugPrint('Error capturing body photo: $e');
      _showValidationError('Failed to capture body photo');
    }
  }

  Future<void> _onSkip() async {
    context.read<ProfileController>().updatePersonalization(
      enabled: false,
      faceUploaded: false,
      bodyUploaded: false,
    );
    debugPrint('AHVI_ONBOARDING3_SAVE onboarding3=true');
    await context.read<AppwriteService>().updateCurrentUserProfileFields({
      'onboarding3': true,
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboardingComplete', true);
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.main, (route) => false);
  }

  Future<void> _onSaveContinue() async {
    if (!_isValid) {
      _showValidationError('Please upload both face and body photos.');
      return;
    }
    context.read<ProfileController>().updatePersonalization(
      enabled: _personalizationEnabled,
      faceUploaded: _faceUploaded,
      bodyUploaded: _bodyUploaded,
    );
    debugPrint('AHVI_ONBOARDING3_SAVE onboarding3=true');
    await context.read<AppwriteService>().updateCurrentUserProfileFields({
      'onboarding3': true,
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboardingComplete', true);
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.main, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final horizontalPadding = size.width < 360 ? 16.0 : (size.width < 400 ? 18.0 : 20.0);
    final bottomPadding = size.height < 700 ? 8.0 : 0.0;
    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: Stack(
        children: [
          const _AtmosphericBackground(),

          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Header(),
                        _TabBar(
                          activeTab: _activeTab,
                          onTabSelected: (i) => setState(() => _activeTab = i),
                        ),
                        const SizedBox(height: 32),
                        _SectionDivider(),
                        const SizedBox(height: 16),
                        _IntroCard(),
                        const SizedBox(height: 16),
                        _ToggleCard(
                          enabled: _personalizationEnabled,
                          onChanged: (v) => setState(() => _personalizationEnabled = v),
                        ),
                        const SizedBox(height: 16),
                        _OptionalBadge(),
                        const SizedBox(height: 14),
                        _UploadSection(
                          enabled: _personalizationEnabled,
                          faceUploaded: _faceUploaded,
                          bodyUploaded: _bodyUploaded,
                          onFaceTap: _captureFacePhoto,
                          onBodyTap: _captureBodyPhoto,
                          isAnalyzing: _isAnalyzingFace,
                        ),

                        // Show detailed face analysis results
                        if (_faceAnalysisData != null) ...[
                          const SizedBox(height: 24),
                          _FaceAnalysisPreview(data: _faceAnalysisData!),
                        ],

                        const SizedBox(height: 24),
                        _PrivacyBlock(),
                        const SizedBox(height: 32),
                        _CtaSection(
                          onBack: () => Navigator.of(context).pop(),
                          onSaveContinue: _onSaveContinue,
                        ),
                        _SkipRow(onSkip: _onSkip),
                        _ProgressDots(),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
                _HomeIndicator(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Face Analysis Preview Widget ───────────────────────────────
class _FaceAnalysisPreview extends StatelessWidget {
  final FaceAnalysisData data;

  const _FaceAnalysisPreview({required this.data});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.cardBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            '✨ Face Analysis Results',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: c.text,
            ),
          ),
          const SizedBox(height: 16),

          // Skin Analysis Section
          _AnalysisSection(
            title: '🎨 Skin Profile',
            items: [
              _AnalysisItem(
                label: 'Skin Tone',
                value: data.skinTone,
                icon: '🌿',
                color: c.accent3,
                swatchColor: data.skinToneColor,
              ),
              _AnalysisItem(
                label: 'Skin Quality',
                value: '${data.skinQuality.toStringAsFixed(0)}%',
                icon: '✨',
                color: c.accent1,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Acne & Pigmentation Section
          _AnalysisSection(
            title: '🔍 Skin Conditions',
            items: [
              _AnalysisItem(
                label: 'Acne Status',
                value: data.acneDetected ? 'Detected (${data.acneSeverity}%)' : 'Clear',
                icon: data.acneDetected ? '⚠️' : '✅',
                color: data.acneDetected ? c.danger : c.accent3,
              ),
              _AnalysisItem(
                label: 'Pigmentation',
                value: data.pigmentationDetected ? 'Present' : 'Even',
                icon: data.pigmentationDetected ? '⚠️' : '✅',
                color: data.pigmentationDetected ? c.warning : c.accent3,
              ),
              if (data.darkerCircles)
                _AnalysisItem(
                  label: 'Dark Circles',
                  value: 'Detected',
                  icon: '👁️',
                  color: c.statusPurple,
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Eye & Lip Section
          _AnalysisSection(
            title: '👁️ Facial Features',
            items: [
              _AnalysisItem(
                label: 'Face Shape',
                value: data.faceShape,
                icon: '🧑',
                color: c.accent1,
              ),
              _AnalysisItem(
                label: 'Eye Shape',
                value: data.eyeShape,
                icon: '👁️',
                color: c.accent2,
              ),
              _AnalysisItem(
                label: 'Eye Size',
                value: _getSizeLabel(data.eyeSize),
                icon: '💫',
                color: c.accent2,
              ),
              _AnalysisItem(
                label: 'Lip Color',
                value: data.lipColor,
                icon: '💋',
                color: c.statusPink,
              ),
              _AnalysisItem(
                label: 'Lip Fullness',
                value: _getSizeLabel(data.lipFullness),
                icon: '✨',
                color: c.statusPink,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Recommendations Section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.recommendationBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.recommendationBorder, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '💡 Personalized Recommendations',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.recommendationTitle,
                  ),
                ),
                const SizedBox(height: 8),
                ...data.recommendations.map((rec) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ', style: TextStyle(color: c.muted)),
                      Expanded(
                        child: Text(
                          rec,
                          style: TextStyle(
                            fontSize: 12,
                            color: c.muted,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getSizeLabel(double size) {
    if (size < 0.3) return 'Small';
    if (size < 0.6) return 'Medium';
    if (size < 0.8) return 'Large';
    return 'Very Large';
  }
}

// ── Analysis Section Widget ────────────────────────────────────
class _AnalysisSection extends StatelessWidget {
  final String title;
  final List<_AnalysisItem> items;

  const _AnalysisSection({
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: c.muted,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(item.icon, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: c.text,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (item.swatchColor != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: item.swatchColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.cardBorder, width: 1),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: item.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  item.value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: item.color,
                  ),
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }
}

class _AnalysisItem {
  final String label;
  final String value;
  final String icon;
  final Color color;
  final Color? swatchColor; // Optional actual color dot (e.g. skin tone)

  _AnalysisItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.swatchColor,
  });
}

// ── Atmospheric Background ─────────────────────────────────────
class _AtmosphericBackground extends StatelessWidget {
  const _AtmosphericBackground();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: c.bg,
          gradient: RadialGradient(
            center: const Alignment(-1.1, -1.0),
            radius: 1.4,
            colors: [c.accent1.withOpacity(0.145), c.accent1.withOpacity(0)],
          ),
        ),
      ),
    );
  }
}

// ── Header ─────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Personalize Your Fit',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: c.text,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Get better recommendations with advanced face analysis',
            style: TextStyle(
              fontSize: 15,
              color: c.muted,
              fontWeight: FontWeight.w400,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab Bar ────────────────────────────────────────────────────
class _TabBar extends StatelessWidget {
  final int activeTab;
  final Function(int) onTabSelected;

  const _TabBar({required this.activeTab, required this.onTabSelected});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Row(
        children: [
          for (int i = 1; i <= 3; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onTabSelected(i),
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: activeTab >= i ? c.accent1 : c.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          if (activeTab < 3) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, c.cardBorder, Colors.transparent],
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.cardBorder, width: 1),
      ),
      child: Text(
        'Upload a clear face photo to unlock personalized skin analysis, makeup recommendations, and facial feature insights.',
        style: TextStyle(
          fontSize: 13,
          color: c.text,
          height: 1.6,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ToggleCard extends StatelessWidget {
  final bool enabled;
  final Function(bool) onChanged;

  const _ToggleCard({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.cardBorder, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Enable Personalization',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: c.text,
            ),
          ),
          Switch(
            value: enabled,
            onChanged: onChanged,
            activeColor: c.accent1,
          ),
        ],
      ),
    );
  }
}

class _OptionalBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.panel2,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        'Optional Step',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: c.accent1,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _UploadSection extends StatelessWidget {
  final bool enabled;
  final bool faceUploaded;
  final bool bodyUploaded;
  final VoidCallback onFaceTap;
  final VoidCallback onBodyTap;
  final bool isAnalyzing;

  const _UploadSection({
    required this.enabled,
    required this.faceUploaded,
    required this.bodyUploaded,
    required this.onFaceTap,
    required this.onBodyTap,
    this.isAnalyzing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _UploadCard(
          title: 'Face Photo',
          description: 'Clear frontal face photo (well-lit)',
          icon: Icons.face_outlined,
          uploaded: faceUploaded,
          enabled: enabled,
          onTap: isAnalyzing ? null : onFaceTap,
          isLoading: isAnalyzing,
        ),
        const SizedBox(height: 12),
        _UploadCard(
          title: 'Body Photo',
          description: 'Full body in fitted clothes',
          icon: Icons.accessibility_outlined,
          uploaded: bodyUploaded,
          enabled: enabled,
          onTap: onBodyTap,
        ),
      ],
    );
  }
}

class _UploadCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final bool uploaded;
  final bool enabled;
  final VoidCallback? onTap;
  final bool isLoading;

  const _UploadCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.uploaded,
    required this.enabled,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: enabled && !isLoading ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: uploaded ? c.uploadedBg : c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: uploaded ? c.accent3 : c.cardBorder,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: uploaded ? c.accent3 : c.accent1,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: isLoading
                      ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(c.onAccent),
                    ),
                  )
                      : Icon(
                    uploaded ? Icons.check : icon,
                    color: c.onAccent,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      uploaded ? '✓ Analysis complete' : description,
                      style: TextStyle(
                        fontSize: 12,
                        color: uploaded ? c.accent3 : c.muted,
                        fontWeight: uploaded ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (enabled && !uploaded)
                Icon(Icons.arrow_forward, color: c.muted, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.privacyTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.cardBorder, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: c.privacyTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Icon(Icons.shield_outlined, color: c.accent3, size: 17),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Privacy is Protected',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: c.accent3,
                    letterSpacing: 0.25,
                  ),
                ),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 12,
                      color: c.muted,
                      fontWeight: FontWeight.w300,
                      height: 1.55,
                    ),
                    children: [
                      const TextSpan(
                        text: 'Photos are analyzed on your device (not uploaded). Data is ',
                      ),
                      TextSpan(
                        text: 'deleted on request',
                        style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const TextSpan(
                        text: '. AHVI never stores or shares personal data.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CtaSection extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onSaveContinue;

  const _CtaSection({required this.onBack, required this.onSaveContinue});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        GestureDetector(
          onTap: onBack,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.cardBorder, width: 1),
            ),
            child: Center(
              child: Icon(Icons.chevron_left, color: c.muted, size: 22),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [c.accent4, c.accent2],
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onSaveContinue,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Save & Continue',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.onAccent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward, color: c.onAccent, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SkipRow extends StatelessWidget {
  final VoidCallback onSkip;

  const _SkipRow({required this.onSkip});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Center(
        child: GestureDetector(
          onTap: onSkip,
          child: Text(
            'Skip for now — set up later in Settings',
            style: TextStyle(
              fontSize: 12.5,
              color: c.muted,
              letterSpacing: 0.2,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: c.dotInactive,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: c.dotInactive,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 22,
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: LinearGradient(colors: [c.accent2, c.accent4]),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 14),
      child: Center(
        child: Container(
          width: 134,
          height: 5,
          decoration: BoxDecoration(
            color: c.cardBorder,
            borderRadius: BorderRadius.circular(100),
          ),
        ),
      ),
    );
  }
}