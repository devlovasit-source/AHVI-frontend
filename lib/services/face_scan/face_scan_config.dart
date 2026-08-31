// ── Face Scan Analysis Configuration ────────────────────────────────────────
// All hardcoded thresholds and recommendations moved here for easy maintenance
// and A/B testing without code changes.

class FaceScanConfig {
  // ── Skin Tone Brightness Thresholds ────────────────────────────────────
  // Threshold values for classifying skin tones based on brightness (0-255)
  static const skinToneBrightnessRanges = {
    'Very Fair': 200,
    'Fair': 170,
    'Light Medium': 140,
    'Medium': 110,
    'Medium Deep': 80,
    'Deep': 60,
    'Very Deep': 0,
  };

  // Default fallback when skin tone extraction fails
  static const skinToneFallback = {
    'label': 'Medium',
    'colorHex': 0xFFC68863,
  };

  // ── Acne Detection Configuration ───────────────────────────────────────
  static const acneDetectionThreshold = 5; // percentage
  static const acneFallback = {
    'detected': false,
    'severity': 0,
  };

  // Acne severity thresholds for graduated recommendations
  static const acneSeverityThresholds = {
    'mild': 15,      // 0-15%
    'moderate': 35,  // 15-35%
    'severe': 100,   // 35%+
  };

  // ── Pigmentation Detection Configuration ──────────────────────────────
  static const pigmentationDetectionThreshold = 0.3;
  static const pigmentationFallback = {
    'detected': false,
    'intensity': 0.0,
  };

  // Pigmentation intensity thresholds
  static const pigmentationIntensityThresholds = {
    'mild': 0.4,
    'moderate': 0.65,
    'severe': 1.0,
  };

  // ── Dark Circles Detection ──────────────────────────────────────────
  static const darkCirclesBrightnessThreshold = 100; // pixel brightness
  static const darkCirclesFallback = false;

  // ── Eye Shape & Face Shape Fallbacks ────────────────────────────────
  static const eyeShapeFallback = 'Standard';
  static const faceShapeFallback = 'Oval';

  // ── Skin Quality Configuration ──────────────────────────────────────
  static const skinQualityFallback = 75.0;
  
  // Acne severity impact on skin quality (reduction factor)
  static const acneSeverityImpact = 0.5;
  
  // Pigmentation intensity impact on skin quality (reduction factor)
  static const pigmentationImpact = 0.3;

  // Skin quality score ranges for display
  static const skinQualityRanges = {
    'Excellent': 85.0,
    'Good': 70.0,
    'Fair': 50.0,
    'Needs Attention': 0.0,
  };

  // ── Recommendation Database ─────────────────────────────────────────
  static const recommendationDatabase = {
    'acne': {
      'mild': [
        'Maintain a consistent cleansing routine twice daily',
        'Use non-comedogenic moisturizers',
        'Apply targeted acne spot treatments as needed',
      ],
      'moderate': [
        'Incorporate salicylic acid or benzoyl peroxide into your routine',
        'Consider a gentle exfoliant 2-3 times per week',
        'Avoid touching your face throughout the day',
      ],
      'severe': [
        'Consult a dermatologist for professional treatment options',
        'Consider prescription acne medications like retinoids',
        'Avoid heavy makeup that may clog pores',
      ],
    },
    'pigmentation': {
      'mild': [
        'Use broad-spectrum SPF 30+ daily to prevent worsening',
        'Try gentle brightening serums with niacinamide',
        'Be patient — pigmentation takes time to fade',
      ],
      'moderate': [
        'Incorporate vitamin C serum for brightening effects',
        'Use azelaic acid to reduce pigmentation unevenness',
        'Apply sunscreen religiously to prevent new spots',
      ],
      'severe': [
        'Consider professional treatments like laser therapy',
        'Consult a dermatologist about prescription brightening creams',
        'Chemical peels may help accelerate improvement',
      ],
    },
    'darkCircles': [
      'Use eye creams containing caffeine to reduce puffiness',
      'Get 7-9 hours of quality sleep each night',
      'Apply cold compresses in the morning to reduce swelling',
      'Consider concealers with blue undertones to neutralize darkness',
    ],
    'eyeShape': {
      'Almond': [
        'Your almond eyes are naturally balanced — minimize for focus',
        'Try winged eyeliner to elongate the eye shape',
        'Avoid heavy eyeshadow on the outer corner',
      ],
      'Round': [
        'Use winged eyeliner to create the illusion of lift',
        'Apply lighter shades to the inner corner for width',
        'Avoid eyeshadow that goes too high on the brow bone',
      ],
      'Hooded': [
        'Highlight the inner corner to make eyes appear wider',
        'Apply eyeshadow mainly on the lid above the fold',
        'Use eyeliner on the upper lash line for definition',
      ],
      'Standard': [
        'Your eye shape is versatile — experiment with different styles',
        'Most eye makeup techniques will flatter your eyes',
        'Focus on colors that complement your skin tone',
      ],
    },
    'faceShape': {
      'Oval': [
        'Your balanced face shape suits most styles',
        'Experiment freely with different makeup techniques',
        'Nearly all hairstyles will complement your features',
      ],
      'Round': [
        'Contour cheeks softly with cool-toned bronzers to add definition',
        'Use angled brush strokes to create shadow and dimension',
        'Avoid heavy blush in the apples of your cheeks',
      ],
      'Square': [
        'Soften your strong jawline with rounded blush placement',
        'Apply contour along the jawline to minimize its prominence',
        'Use warm-toned bronzers for a softer appearance',
      ],
      'Heart': [
        'Balance a wider forehead with soft, side-swept styling',
        'Apply darker eyeshadow to make your forehead appear smaller',
        'Use blush in a circular motion on cheeks to widen the face',
      ],
      'Oblong': [
        'Add visual width with horizontal blush placement',
        'Apply contour to the temples to create width',
        'Avoid long, straight hairstyles that elongate the face',
      ],
      'Diamond': [
        'Highlight your cheekbones — your strongest feature',
        'Use contour to soften the pointed chin slightly',
        'Apply blush high on the apples for a lifted effect',
      ],
    },
    'universal': [
      'Stay hydrated by drinking 8+ glasses of water daily',
      'Get 7-9 hours of quality sleep each night',
      'Manage stress through meditation or exercise',
      'Avoid smoking and excessive alcohol consumption',
    ],
  };

  // ── Helper Methods ──────────────────────────────────────────────────
  
  /// Get skin tone label based on brightness value
  static String getSkinToneLabel(double brightness) {
    for (final entry in skinToneBrightnessRanges.entries) {
      if (brightness > entry.value) {
        return entry.key;
      }
    }
    return skinToneBrightnessRanges.keys.last;
  }

  /// Get severity level for acne percentage
  static String getAcneSeverityLevel(int acnePercentage) {
    if (acnePercentage <= acneSeverityThresholds['mild']!) {
      return 'mild';
    } else if (acnePercentage <= acneSeverityThresholds['moderate']!) {
      return 'moderate';
    } else {
      return 'severe';
    }
  }

  /// Get severity level for pigmentation intensity
  static String getPigmentationSeverityLevel(double intensity) {
    if (intensity <= pigmentationIntensityThresholds['mild']!) {
      return 'mild';
    } else if (intensity <= pigmentationIntensityThresholds['moderate']!) {
      return 'moderate';
    } else {
      return 'severe';
    }
  }

  /// Get skin quality rating label
  static String getSkinQualityRating(double score) {
    for (final entry in skinQualityRanges.entries) {
      if (score >= entry.value) {
        return entry.key;
      }
    }
    return 'Needs Attention';
  }

  /// Get recommended number of recommendations to show
  static const maxRecommendationsPerCategory = 3;
  static const minTotalRecommendations = 3;
  static const maxTotalRecommendations = 8;

  /// Enable/disable specific analysis features
  static const analysisFeatures = {
    'acneDetection': true,
    'pigmentationDetection': true,
    'darkCirclesDetection': true,
    'eyeShapeAnalysis': true,
    'faceShapeAnalysis': true,
    'skinQualityCalculation': true,
  };

  /// Version for tracking configuration changes
  static const String configVersion = '1.0.0';
  static const String lastUpdated = '2024-01-15';
}
