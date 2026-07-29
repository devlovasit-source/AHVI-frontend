// profile.dart
// Single source of truth for profile types, controller, screen, and all UI.
// Imported by: main.dart, home.dart, onboarding1.dart, onboarding2.dart, onboarding3.dart

import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:myapp/theme/theme_controller.dart';
import 'package:myapp/theme/profile_theme.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/app_routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// THEME CONFIG
// ─────────────────────────────────────────────────────────────────────────────

enum AppTheme { coolBlue, sunsetPop, futureCandy }

class ThemeColors {
  final Color accent1;
  final Color accent2;
  final Color accent3;

  const ThemeColors({
    required this.accent1,
    required this.accent2,
    required this.accent3,
  });
}

final Map<AppTheme, ThemeColors> themeMap = {
  // matches accent_palette.dart — coolBlue
  AppTheme.coolBlue: ThemeColors(
    accent1: Color(0xFF6B91FF),
    accent2: Color(0xFF8D7DFF),
    accent3: Color(0xFF04D7C8),
  ),
  // matches accent_palette.dart — sunsetPop
  AppTheme.sunsetPop: ThemeColors(
    accent1: Color(0xFFFF9E66),
    accent2: Color(0xFFFFD86E),
    accent3: Color(0xFFFF8EC7),
  ),
  // matches accent_palette.dart — futureCandy
  AppTheme.futureCandy: ThemeColors(
    accent1: Color(0xFFFF8EC7),
    accent2: Color(0xFF8D7DFF),
    accent3: Color(0xFF04D7C8),
  ),
};

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE STATE MODEL
// ─────────────────────────────────────────────────────────────────────────────

class ProfileState {
  String name;
  String username;
  String email;
  String phone;
  String dob;
  String gender;
  int skinTone;
  String faceShape;
  String bodyShape;
  Set<String> styles;
  Set<String> shopPrefs;
  bool isDark;
  AppTheme theme;
  String lang;
  String? avatarPath;
  String locationLabel;

  ProfileState({
    this.name = 'New User',
    this.username = '@username',
    this.email = '',
    this.phone = '',
    this.dob = '',
    this.gender = 'Female',
    this.skinTone = 3,
    this.faceShape = 'Oval',
    this.bodyShape = 'Rectangle',
    Set<String>? styles,
    Set<String>? shopPrefs,
    this.isDark = false,
    this.theme = AppTheme.coolBlue,
    this.lang = 'English',
    this.avatarPath,
    this.locationLabel = 'Not set',
  }) : styles = styles ?? {'Casual', 'Minimalist'},
        shopPrefs = shopPrefs ?? {};

  ProfileState copyWith({
    String? name,
    String? username,
    String? email,
    String? phone,
    String? dob,
    String? gender,
    int? skinTone,
    String? faceShape,
    String? bodyShape,
    Set<String>? styles,
    Set<String>? shopPrefs,
    bool? isDark,
    AppTheme? theme,
    String? lang,
    String? avatarPath,
    bool clearAvatar = false,
    String? locationLabel,
  }) {
    return ProfileState(
      name: name ?? this.name,
      username: username ?? this.username,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      dob: dob ?? this.dob,
      gender: gender ?? this.gender,
      skinTone: skinTone ?? this.skinTone,
      faceShape: faceShape ?? this.faceShape,
      bodyShape: bodyShape ?? this.bodyShape,
      styles: styles ?? Set.from(this.styles),
      shopPrefs: shopPrefs ?? Set.from(this.shopPrefs),
      isDark: isDark ?? this.isDark,
      theme: theme ?? this.theme,
      lang: lang ?? this.lang,
      avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
      locationLabel: locationLabel ?? this.locationLabel,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FACE ANALYSIS DATA MODEL  (mirrors onboarding3.dart's advanced face scan)
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────

const List<String> kLanguages = [
  'English', // en.json ✅
  'Hindi', // hi.json ✅
  'Telugu', // te.json ✅
  'Tamil', // ta.json ✅
  'Kannada', // kn.json ✅
  'Malayalam', // ml.json ✅
  'Bengali', // bn.json ✅
  'Marathi', // mr.json ✅
];

// ─────────────────────────────────────────────────────────────────────────────
// LOCALIZATION  — AppStrings
// Usage: final t = AppStrings.of(state.lang);  then use t.editProfile, etc.
// ─────────────────────────────────────────────────────────────────────────────

class AppStrings {
  final String myProfile;
  final String editProfile;
  final String preferences;
  final String language;
  final String location;
  final String appearance;
  final String mode;
  final String darkMode;
  final String lightMode;
  final String colourTheme;
  final String account;
  final String logOut;
  final String deleteAccount;
  final String selectLanguage;
  final String cancel;
  final String basics;
  final String style;
  final String tryOn;
  final String fullName;
  final String yourName;
  final String username;
  final String email;
  final String phone;
  final String dateOfBirth;
  final String gender;
  final String skinTone;
  final String shopPreferences;
  final String faceShape;
  final String bodyShape;
  final String chooseStyles;
  final String tapToSelect;
  final String personalizedFitPreview;
  final String personalizedFitBody;
  final String enableTryOn;
  final String uploadFacePhoto;
  final String uploadBodyPhoto;
  final String uploaded;
  final String uploadPhoto;
  final String discardChanges;
  final String discardChangesBody;
  final String discard;
  final String keepEditing;
  final String logOutTitle;
  final String logOutBody;
  final String logOutConfirm;
  final String enableLocation;
  final String enableLocationBody;
  final String enableLocationConfirm;
  final String notNow;
  final String deleteAccountTitle;
  final String deleteAccountBody;
  final String deleteAccountConfirm;
  final String profileUpdated;
  final String photoUpdated;
  final String loggedOut;
  final String accountDeleted;
  final String locationEnabled;
  final String themeSetTo;
  final String lightModeOn;
  final String darkModeOn;
  final String languageSetTo;

  const AppStrings({
    required this.myProfile,
    required this.editProfile,
    required this.preferences,
    required this.language,
    required this.location,
    required this.appearance,
    required this.mode,
    required this.darkMode,
    required this.lightMode,
    required this.colourTheme,
    required this.account,
    required this.logOut,
    required this.deleteAccount,
    required this.selectLanguage,
    required this.cancel,
    required this.basics,
    required this.style,
    required this.tryOn,
    required this.fullName,
    required this.yourName,
    required this.username,
    required this.email,
    required this.phone,
    required this.dateOfBirth,
    required this.gender,
    required this.skinTone,
    required this.shopPreferences,
    required this.faceShape,
    required this.bodyShape,
    required this.chooseStyles,
    required this.tapToSelect,
    required this.personalizedFitPreview,
    required this.personalizedFitBody,
    required this.enableTryOn,
    required this.uploadFacePhoto,
    required this.uploadBodyPhoto,
    required this.uploaded,
    required this.uploadPhoto,
    required this.discardChanges,
    required this.discardChangesBody,
    required this.discard,
    required this.keepEditing,
    required this.logOutTitle,
    required this.logOutBody,
    required this.logOutConfirm,
    required this.enableLocation,
    required this.enableLocationBody,
    required this.enableLocationConfirm,
    required this.notNow,
    required this.deleteAccountTitle,
    required this.deleteAccountBody,
    required this.deleteAccountConfirm,
    required this.profileUpdated,
    required this.photoUpdated,
    required this.loggedOut,
    required this.accountDeleted,
    required this.locationEnabled,
    required this.themeSetTo,
    required this.lightModeOn,
    required this.darkModeOn,
    required this.languageSetTo,
  });

  static AppStrings of(String lang) {
    return _translations[lang] ?? _translations['English']!;
  }

  static const Map<String, AppStrings> _translations = {
    'English': AppStrings(
      myProfile: 'My Profile',
      editProfile: 'Edit Profile',
      preferences: 'PREFERENCES',
      language: 'Language',
      location: 'Location',
      appearance: 'APPEARANCE',
      mode: 'MODE',
      darkMode: 'Dark Mode',
      lightMode: 'Light Mode',
      colourTheme: 'COLOUR THEME',
      account: 'ACCOUNT',
      logOut: 'Log Out',
      deleteAccount: 'Delete Account',
      selectLanguage: 'Select Language',
      cancel: 'Cancel',
      basics: 'Basics',
      style: 'Style',
      tryOn: 'Try On',
      fullName: 'Full Name',
      yourName: 'Your name',
      username: 'Username',
      email: 'Email',
      phone: 'Phone',
      dateOfBirth: 'Date of Birth',
      gender: 'Gender',
      skinTone: 'Skin Tone',
      shopPreferences: 'Shop Preferences',
      faceShape: 'Face Shape',
      bodyShape: 'Body Shape',
      chooseStyles: 'Choose styles that match your vibe ✨',
      tapToSelect: 'Tap to select multiple',
      personalizedFitPreview: 'Personalized Fit Preview',
      personalizedFitBody:
      'Upload a face and body photo to enable AI-powered try-on and personalised style recommendations.',
      enableTryOn: 'Enable Try-On',
      uploadFacePhoto: 'Face Photo',
      uploadBodyPhoto: 'Body Photo',
      uploaded: 'Uploaded ✓',
      uploadPhoto: 'Upload Photo',
      discardChanges: 'Discard Changes?',
      discardChangesBody:
      "You have unsaved changes. If you leave now, they'll be lost.",
      discard: 'Discard',
      keepEditing: 'Keep Editing',
      logOutTitle: 'Log Out?',
      logOutBody:
      "Are you sure you want to log out? You'll need to sign in again to access your profile.",
      logOutConfirm: 'Log Out',
      enableLocation: 'Enable Location',
      enableLocationBody:
      'Allow the app to access your location to show nearby stores, personalised recommendations, and local trends.',
      enableLocationConfirm: 'Enable Location',
      notNow: 'Not Now',
      deleteAccountTitle: 'Delete Account?',
      deleteAccountBody:
      'This will permanently delete your account and all associated data. This action cannot be undone.',
      deleteAccountConfirm: 'Delete Account',
      profileUpdated: '✓ Profile updated',
      photoUpdated: '✓ Photo updated',
      loggedOut: '👋 Logged out',
      accountDeleted: '🗑️ Account deleted',
      locationEnabled: '📍 Location enabled',
      themeSetTo: '✓ Theme set to',
      lightModeOn: '☀️ Light mode on',
      darkModeOn: '🌙 Dark mode on',
      languageSetTo: '✓ Language set to',
    ),
    'Hindi': AppStrings(
      myProfile: 'मेरी प्रोफ़ाइल',
      editProfile: 'प्रोफ़ाइल संपादित करें',
      preferences: 'प्राथमिकताएँ',
      language: 'भाषा',
      location: 'स्थान',
      appearance: 'दिखावट',
      mode: 'मोड',
      darkMode: 'डार्क मोड',
      lightMode: 'लाइट मोड',
      colourTheme: 'रंग थीम',
      account: 'अकाउंट',
      logOut: 'लॉग आउट',
      deleteAccount: 'अकाउंट हटाएं',
      selectLanguage: 'भाषा चुनें',
      cancel: 'रद्द करें',
      basics: 'बेसिक्स',
      style: 'स्टाइल',
      tryOn: 'ट्राय ऑन',
      fullName: 'पूरा नाम',
      yourName: 'आपका नाम',
      username: 'यूज़रनेम',
      email: 'ईमेल',
      phone: 'फ़ोन',
      dateOfBirth: 'जन्म तिथि',
      gender: 'लिंग',
      skinTone: 'त्वचा का रंग',
      shopPreferences: 'शॉप प्राथमिकताएँ',
      faceShape: 'चेहरे का आकार',
      bodyShape: 'शरीर का आकार',
      chooseStyles: 'अपनी पसंद की स्टाइल चुनें ✨',
      tapToSelect: 'कई चुनने के लिए टैप करें',
      personalizedFitPreview: 'व्यक्तिगत फ़िट पूर्वावलोकन',
      personalizedFitBody:
      'AI ट्राय-ऑन और व्यक्तिगत शैली सुझावों के लिए फ़ोटो अपलोड करें।',
      enableTryOn: 'ट्राय-ऑन चालू करें',
      uploadFacePhoto: 'चेहरे की फ़ोटो',
      uploadBodyPhoto: 'शरीर की फ़ोटो',
      uploaded: 'अपलोड हो गया ✓',
      uploadPhoto: 'फ़ोटो अपलोड करें',
      discardChanges: 'बदलाव हटाएं?',
      discardChangesBody: 'आपके अनसेव्ड बदलाव हैं। अभी छोड़ने पर वे खो जाएंगे।',
      discard: 'हटाएं',
      keepEditing: 'संपादन जारी रखें',
      logOutTitle: 'लॉग आउट करें?',
      logOutBody:
      'क्या आप वाकई लॉग आउट करना चाहते हैं? वापस आने के लिए फिर से साइन इन करना होगा।',
      logOutConfirm: 'लॉग आउट',
      enableLocation: 'स्थान सक्षम करें',
      enableLocationBody:
      'पास की दुकानें, व्यक्तिगत सुझाव और स्थानीय ट्रेंड देखने के लिए स्थान की अनुमति दें।',
      enableLocationConfirm: 'स्थान सक्षम करें',
      notNow: 'अभी नहीं',
      deleteAccountTitle: 'अकाउंट हटाएं?',
      deleteAccountBody:
      'इससे आपका अकाउंट और सभी डेटा स्थायी रूप से हट जाएगा। यह क्रिया पूर्ववत नहीं की जा सकती।',
      deleteAccountConfirm: 'अकाउंट हटाएं',
      profileUpdated: '✓ प्रोफ़ाइल अपडेट हुई',
      photoUpdated: '✓ फ़ोटो अपडेट हुई',
      loggedOut: '👋 लॉग आउट हो गए',
      accountDeleted: '🗑️ अकाउंट हटा दिया',
      locationEnabled: '📍 स्थान सक्षम हुआ',
      themeSetTo: '✓ थीम सेट हुई',
      lightModeOn: '☀️ लाइट मोड चालू',
      darkModeOn: '🌙 डार्क मोड चालू',
      languageSetTo: '✓ भाषा सेट हुई',
    ),
    'Tamil': AppStrings(
      myProfile: 'என் சுயவிவரம்',
      editProfile: 'சுயவிவரம் திருத்து',
      preferences: 'விருப்பங்கள்',
      language: 'மொழி',
      location: 'இடம்',
      appearance: 'தோற்றம்',
      mode: 'முறை',
      darkMode: 'இருள் முறை',
      lightMode: 'ஒளி முறை',
      colourTheme: 'நிற தீம்',
      account: 'கணக்கு',
      logOut: 'வெளியேறு',
      deleteAccount: 'கணக்கை நீக்கு',
      selectLanguage: 'மொழி தேர்ந்தெடு',
      cancel: 'ரத்துசெய்',
      basics: 'அடிப்படை',
      style: 'பாணி',
      tryOn: 'அணிந்து பார்',
      fullName: 'முழு பெயர்',
      yourName: 'உங்கள் பெயர்',
      username: 'பயனர்பெயர்',
      email: 'மின்னஞ்சல்',
      phone: 'தொலைபேசி',
      dateOfBirth: 'பிறந்த தேதி',
      gender: 'பாலினம்',
      skinTone: 'தோல் நிறம்',
      shopPreferences: 'கடை விருப்பங்கள்',
      faceShape: 'முக வடிவம்',
      bodyShape: 'உடல் வடிவம்',
      chooseStyles: 'உங்கள் விருப்பமான பாணிகளை தேர்ந்தெடுக்கவும் ✨',
      tapToSelect: 'பலவற்றை தேர்ந்தெடுக்க தட்டவும்',
      personalizedFitPreview: 'தனிப்பயனாக்கப்பட்ட பொருத்தம்',
      personalizedFitBody:
      'AI ட்ரை-ஆன் மற்றும் பரிந்துரைகளுக்கு புகைப்படங்களை பதிவேற்றவும்.',
      enableTryOn: 'ட்ரை-ஆன் இயக்கு',
      uploadFacePhoto: 'முக புகைப்படம்',
      uploadBodyPhoto: 'உடல் புகைப்படம்',
      uploaded: 'பதிவேற்றப்பட்டது ✓',
      uploadPhoto: 'புகைப்படம் பதிவேற்று',
      discardChanges: 'மாற்றங்களை நீக்கவா?',
      discardChangesBody:
      'சேமிக்கப்படாத மாற்றங்கள் உள்ளன. இப்போது வெளியேறினால் அவை இழக்கப்படும்.',
      discard: 'நீக்கு',
      keepEditing: 'திருத்தம் தொடரு',
      logOutTitle: 'வெளியேறவா?',
      logOutBody: 'வெளியேற விரும்புகிறீர்களா? மீண்டும் உள்நுழைய வேண்டும்.',
      logOutConfirm: 'வெளியேறு',
      enableLocation: 'இடம் இயக்கு',
      enableLocationBody:
      'அருகிலுள்ள கடைகள் மற்றும் பரிந்துரைகளுக்கு இட அனுமதி வழங்கவும்.',
      enableLocationConfirm: 'இடம் இயக்கு',
      notNow: 'இப்போது வேண்டாம்',
      deleteAccountTitle: 'கணக்கை நீக்கவா?',
      deleteAccountBody:
      'இது உங்கள் கணக்கை நிரந்தரமாக நீக்கும். இந்த செயலை மீட்க முடியாது.',
      deleteAccountConfirm: 'கணக்கை நீக்கு',
      profileUpdated: '✓ சுயவிவரம் புதுப்பிக்கப்பட்டது',
      photoUpdated: '✓ புகைப்படம் புதுப்பிக்கப்பட்டது',
      loggedOut: '👋 வெளியேறினீர்கள்',
      accountDeleted: '🗑️ கணக்கு நீக்கப்பட்டது',
      locationEnabled: '📍 இடம் இயக்கப்பட்டது',
      themeSetTo: '✓ தீம் அமைக்கப்பட்டது',
      lightModeOn: '☀️ ஒளி முறை இயக்கம்',
      darkModeOn: '🌙 இருள் முறை இயக்கம்',
      languageSetTo: '✓ மொழி அமைக்கப்பட்டது',
    ),
    'Telugu': AppStrings(
      myProfile: 'నా ప్రొఫైల్',
      editProfile: 'ప్రొఫైల్ సవరించు',
      preferences: 'ప్రాధాన్యతలు',
      language: 'భాష',
      location: 'స్థానం',
      appearance: 'రూపురేఖలు',
      mode: 'మోడ్',
      darkMode: 'డార్క్ మోడ్',
      lightMode: 'లైట్ మోడ్',
      colourTheme: 'రంగు థీమ్',
      account: 'ఖాతా',
      logOut: 'లాగ్ అవుట్',
      deleteAccount: 'ఖాతా తొలగించు',
      selectLanguage: 'భాష ఎంచుకోండి',
      cancel: 'రద్దు చేయి',
      basics: 'బేసిక్స్',
      style: 'స్టైల్',
      tryOn: 'ట్రై ఆన్',
      fullName: 'పూర్తి పేరు',
      yourName: 'మీ పేరు',
      username: 'యూజర్‌నేమ్',
      email: 'ఇమెయిల్',
      phone: 'ఫోన్',
      dateOfBirth: 'పుట్టిన తేది',
      gender: 'లింగం',
      skinTone: 'చర్మం రంగు',
      shopPreferences: 'షాప్ ప్రాధాన్యతలు',
      faceShape: 'ముఖ ఆకారం',
      bodyShape: 'శరీర ఆకారం',
      chooseStyles: 'మీ అభిరుచికి సరిపడే స్టైల్స్ ఎంచుకోండి ✨',
      tapToSelect: 'అనేకం ఎంచుకోవడానికి నొక్కండి',
      personalizedFitPreview: 'వ్యక్తిగత ఫిట్ ప్రివ్యూ',
      personalizedFitBody: 'AI ట్రై-ఆన్ మరియు సూచనలకు ఫోటోలు అప్‌లోడ్ చేయండి.',
      enableTryOn: 'ట్రై-ఆన్ ఆన్ చేయి',
      uploadFacePhoto: 'ముఖ ఫోటో',
      uploadBodyPhoto: 'శరీర ఫోటో',
      uploaded: 'అప్‌లోడ్ అయింది ✓',
      uploadPhoto: 'ఫోటో అప్‌లోడ్ చేయి',
      discardChanges: 'మార్పులు తొలగించాలా?',
      discardChangesBody:
      'సేవ్ చేయని మార్పులు ఉన్నాయి. ఇప్పుడు వెళ్ళిపోతే అవి పోతాయి.',
      discard: 'తొలగించు',
      keepEditing: 'సవరణ కొనసాగించు',
      logOutTitle: 'లాగ్ అవుట్ చేయాలా?',
      logOutBody:
      'మీరు లాగ్ అవుట్ చేయాలనుకుంటున్నారా? తిరిగి యాక్సెస్ కోసం సైన్ ఇన్ అవ్వాలి.',
      logOutConfirm: 'లాగ్ అవుట్',
      enableLocation: 'లొకేషన్ ఆన్ చేయి',
      enableLocationBody:
      'దగ్గరలోని దుకాణాలు మరియు సూచనలకు లొకేషన్ అనుమతించండి.',
      enableLocationConfirm: 'లొకేషన్ ఆన్ చేయి',
      notNow: 'ఇప్పుడు వద్దు',
      deleteAccountTitle: 'ఖాతా తొలగించాలా?',
      deleteAccountBody:
      'ఇది మీ ఖాతా మరియు డేటాను శాశ్వతంగా తొలగిస్తుంది. ఇది రద్దు చేయలేరు.',
      deleteAccountConfirm: 'ఖాతా తొలగించు',
      profileUpdated: '✓ ప్రొఫైల్ అప్‌డేట్ అయింది',
      photoUpdated: '✓ ఫోటో అప్‌డేట్ అయింది',
      loggedOut: '👋 లాగ్ అవుట్ అయింది',
      accountDeleted: '🗑️ ఖాతా తొలగించబడింది',
      locationEnabled: '📍 లొకేషన్ ఆన్ అయింది',
      themeSetTo: '✓ థీమ్ సెట్ అయింది',
      lightModeOn: '☀️ లైట్ మోడ్ ఆన్',
      darkModeOn: '🌙 డార్క్ మోడ్ ఆన్',
      languageSetTo: '✓ భాష సెట్ అయింది',
    ),
    'Kannada': AppStrings(
      myProfile: 'ನನ್ನ ಪ್ರೊಫೈಲ್',
      editProfile: 'ಪ್ರೊಫೈಲ್ ಸಂಪಾದಿಸಿ',
      preferences: 'ಆದ್ಯತೆಗಳು',
      language: 'ಭಾಷೆ',
      location: 'ಸ್ಥಳ',
      appearance: 'ನೋಟ',
      mode: 'ಮೋಡ್',
      darkMode: 'ಡಾರ್ಕ್ ಮೋಡ್',
      lightMode: 'ಲೈಟ್ ಮೋಡ್',
      colourTheme: 'ಬಣ್ಣ ಥೀಮ್',
      account: 'ಖಾತೆ',
      logOut: 'ಲಾಗ್ ಔಟ್',
      deleteAccount: 'ಖಾತೆ ಅಳಿಸಿ',
      selectLanguage: 'ಭಾಷೆ ಆಯ್ಕೆ ಮಾಡಿ',
      cancel: 'ರದ್ದು ಮಾಡಿ',
      basics: 'ಮೂಲಭೂತ',
      style: 'ಶೈಲಿ',
      tryOn: 'ಪ್ರಯತ್ನಿಸಿ',
      fullName: 'ಪೂರ್ಣ ಹೆಸರು',
      yourName: 'ನಿಮ್ಮ ಹೆಸರು',
      username: 'ಬಳಕೆದಾರ ಹೆಸರು',
      email: 'ಇಮೇಲ್',
      phone: 'ಫೋನ್',
      dateOfBirth: 'ಹುಟ್ಟಿದ ದಿನ',
      gender: 'ಲಿಂಗ',
      skinTone: 'ಚರ್ಮದ ಬಣ್ಣ',
      shopPreferences: 'ಅಂಗಡಿ ಆದ್ಯತೆಗಳು',
      faceShape: 'ಮುಖದ ಆಕಾರ',
      bodyShape: 'ದೇಹದ ಆಕಾರ',
      chooseStyles: 'ನಿಮ್ಮ ಅಭಿರುಚಿಗೆ ತಕ್ಕ ಶೈಲಿಗಳನ್ನು ಆಯ್ಕೆ ಮಾಡಿ ✨',
      tapToSelect: 'ಹಲವು ಆಯ್ಕೆ ಮಾಡಲು ಟ್ಯಾಪ್ ಮಾಡಿ',
      personalizedFitPreview: 'ವ್ಯಕ್ತಿಗತ ಫಿಟ್ ಪ್ರಿವ್ಯೂ',
      personalizedFitBody:
      'AI ಟ್ರೈ-ಆನ್ ಮತ್ತು ಸಲಹೆಗಳಿಗೆ ಫೋಟೋಗಳನ್ನು ಅಪ್‌ಲೋಡ್ ಮಾಡಿ.',
      enableTryOn: 'ಟ್ರೈ-ಆನ್ ಚಾಲನೆ ಮಾಡಿ',
      uploadFacePhoto: 'ಮುಖದ ಫೋಟೋ',
      uploadBodyPhoto: 'ದೇಹದ ಫೋಟೋ',
      uploaded: 'ಅಪ್‌ಲೋಡ್ ಆಯಿತು ✓',
      uploadPhoto: 'ಫೋಟೋ ಅಪ್‌ಲೋಡ್ ಮಾಡಿ',
      discardChanges: 'ಬದಲಾವಣೆಗಳನ್ನು ತ್ಯಜಿಸಬೇಕೇ?',
      discardChangesBody: 'ಉಳಿಸದ ಬದಲಾವಣೆಗಳಿವೆ. ಈಗ ಹೊರಹೋದರೆ ಅವು ಕಳೆದುಹೋಗುತ್ತವೆ.',
      discard: 'ತ್ಯಜಿಸಿ',
      keepEditing: 'ಸಂಪಾದಿಸುವುದನ್ನು ಮುಂದುವರಿಸಿ',
      logOutTitle: 'ಲಾಗ್ ಔಟ್ ಮಾಡಬೇಕೇ?',
      logOutBody: 'ನೀವು ಲಾಗ್ ಔಟ್ ಮಾಡಲು ಖಚಿತವಾಗಿ ಬಯಸುತ್ತೀರಾ?',
      logOutConfirm: 'ಲಾಗ್ ಔಟ್',
      enableLocation: 'ಸ್ಥಳ ಸಕ್ರಿಯಗೊಳಿಸಿ',
      enableLocationBody: 'ಹತ್ತಿರದ ಅಂಗಡಿಗಳು ಮತ್ತು ಸಲಹೆಗಳಿಗೆ ಸ್ಥಳ ಅನುಮತಿ ನೀಡಿ.',
      enableLocationConfirm: 'ಸ್ಥಳ ಸಕ್ರಿಯಗೊಳಿಸಿ',
      notNow: 'ಈಗ ಬೇಡ',
      deleteAccountTitle: 'ಖಾತೆ ಅಳಿಸಬೇಕೇ?',
      deleteAccountBody:
      'ಇದು ನಿಮ್ಮ ಖಾತೆ ಮತ್ತು ಡೇಟಾವನ್ನು ಶಾಶ್ವತವಾಗಿ ಅಳಿಸುತ್ತದೆ.',
      deleteAccountConfirm: 'ಖಾತೆ ಅಳಿಸಿ',
      profileUpdated: '✓ ಪ್ರೊಫೈಲ್ ಅಪ್‌ಡೇಟ್ ಆಯಿತು',
      photoUpdated: '✓ ಫೋಟೋ ಅಪ್‌ಡೇಟ್ ಆಯಿತು',
      loggedOut: '👋 ಲಾಗ್ ಔಟ್ ಆಯಿತು',
      accountDeleted: '🗑️ ಖಾತೆ ಅಳಿಸಲಾಯಿತು',
      locationEnabled: '📍 ಸ್ಥಳ ಸಕ್ರಿಯವಾಯಿತು',
      themeSetTo: '✓ ಥೀಮ್ ಸೆಟ್ ಆಯಿತು',
      lightModeOn: '☀️ ಲೈಟ್ ಮೋಡ್ ಆನ್',
      darkModeOn: '🌙 ಡಾರ್ಕ್ ಮೋಡ್ ಆನ್',
      languageSetTo: '✓ ಭಾಷೆ ಸೆಟ್ ಆಯಿತು',
    ),
    'Malayalam': AppStrings(
      myProfile: 'എന്റെ പ്രൊഫൈൽ',
      editProfile: 'പ്രൊഫൈൽ തിരുത്തുക',
      preferences: 'മുൻഗണനകൾ',
      language: 'ഭാഷ',
      location: 'സ്ഥലം',
      appearance: 'രൂപഭാവം',
      mode: 'മോഡ്',
      darkMode: 'ഡാർക്ക് മോഡ്',
      lightMode: 'ലൈറ്റ് മോഡ്',
      colourTheme: 'നിറ തീം',
      account: 'അക്കൗണ്ട്',
      logOut: 'ലോഗ് ഔട്ട്',
      deleteAccount: 'അക്കൗണ്ട് ഇല്ലാതാക്കുക',
      selectLanguage: 'ഭാഷ തിരഞ്ഞെടുക്കുക',
      cancel: 'റദ്ദാക്കുക',
      basics: 'അടിസ്ഥാനം',
      style: 'ശൈലി',
      tryOn: 'ട്രൈ ഓൺ',
      fullName: 'മുഴുവൻ പേര്',
      yourName: 'നിങ്ങളുടെ പേര്',
      username: 'ഉപയോക്തൃനാമം',
      email: 'ഇമെയിൽ',
      phone: 'ഫോൺ',
      dateOfBirth: 'ജനനത്തീയതി',
      gender: 'ലിംഗം',
      skinTone: 'ചർമ്മ നിറം',
      shopPreferences: 'ഷോപ്പ് മുൻഗണനകൾ',
      faceShape: 'മുഖാകൃതി',
      bodyShape: 'ശരീരാകൃതി',
      chooseStyles: 'നിങ്ങളുടെ ഇഷ്ടത്തിന് ചേർന്ന ശൈലികൾ തിരഞ്ഞെടുക്കുക ✨',
      tapToSelect: 'ഒന്നിലധികം തിരഞ്ഞെടുക്കാൻ ടാപ്പ് ചെയ്യുക',
      personalizedFitPreview: 'വ്യക്തിഗത ഫിറ്റ് പ്രിവ്യൂ',
      personalizedFitBody:
      'AI ട്രൈ-ഓൺ, നിർദ്ദേശങ്ങൾ എന്നിവയ്ക്ക് ഫോട്ടോ അപ്‌ലോഡ് ചെയ്യുക.',
      enableTryOn: 'ട്രൈ-ഓൺ ഓണാക്കുക',
      uploadFacePhoto: 'മുഖ ഫോട്ടോ',
      uploadBodyPhoto: 'ശരീര ഫോട്ടോ',
      uploaded: 'അപ്‌ലോഡ് ചെയ്തു ✓',
      uploadPhoto: 'ഫോട്ടോ അപ്‌ലോഡ് ചെയ്യുക',
      discardChanges: 'മാറ്റങ്ങൾ ഉപേക്ഷിക്കണോ?',
      discardChangesBody:
      'സേവ് ചെയ്യാത്ത മാറ്റങ്ങൾ ഉണ്ട്. ഇപ്പോൾ പോകുകയാണെങ്കിൽ അവ നഷ്ടപ്പെടും.',
      discard: 'ഉപേക്ഷിക്കുക',
      keepEditing: 'തിരുത്തൽ തുടരുക',
      logOutTitle: 'ലോഗ് ഔട്ട് ചെയ്യണോ?',
      logOutBody:
      'ലോഗ് ഔട്ട് ചെയ്യണമെന്ന് ഉറപ്പാണോ? വീണ്ടും പ്രവേശിക്കാൻ സൈൻ ഇൻ ചെയ്യണം.',
      logOutConfirm: 'ലോഗ് ഔട്ട്',
      enableLocation: 'ലൊക്കേഷൻ ഓണാക്കുക',
      enableLocationBody:
      'അടുത്തുള്ള കടകൾ, നിർദ്ദേശങ്ങൾ എന്നിവയ്ക്ക് ലൊക്കേഷൻ അനുവദിക്കുക.',
      enableLocationConfirm: 'ലൊക്കേഷൻ ഓണാക്കുക',
      notNow: 'ഇപ്പോൾ വേണ്ട',
      deleteAccountTitle: 'അക്കൗണ്ട് ഇല്ലാതാക്കണോ?',
      deleteAccountBody:
      'ഇത് നിങ്ങളുടെ അക്കൗണ്ടും ഡേറ്റയും സ്ഥിരമായി ഇല്ലാതാക്കും.',
      deleteAccountConfirm: 'അക്കൗണ്ട് ഇല്ലാതാക്കുക',
      profileUpdated: '✓ പ്രൊഫൈൽ അപ്‌ഡേറ്റ് ചെയ്തു',
      photoUpdated: '✓ ഫോട്ടോ അപ്‌ഡേറ്റ് ചെയ്തു',
      loggedOut: '👋 ലോഗ് ഔട്ട് ചെയ്തു',
      accountDeleted: '🗑️ അക്കൗണ്ട് ഇല്ലാതാക്കി',
      locationEnabled: '📍 ലൊക്കേഷൻ ഓണായി',
      themeSetTo: '✓ തീം സെറ്റ് ചെയ്തു',
      lightModeOn: '☀️ ലൈറ്റ് മോഡ് ഓൺ',
      darkModeOn: '🌙 ഡാർക്ക് മോഡ് ഓൺ',
      languageSetTo: '✓ ഭാഷ സെറ്റ് ചെയ്തു',
    ),
    'Bengali': AppStrings(
      myProfile: 'আমার প্রোফাইল',
      editProfile: 'প্রোফাইল সম্পাদনা করুন',
      preferences: 'পছন্দ',
      language: 'ভাষা',
      location: 'অবস্থান',
      appearance: 'চেহারা',
      mode: 'মোড',
      darkMode: 'ডার্ক মোড',
      lightMode: 'লাইট মোড',
      colourTheme: 'রঙ থিম',
      account: 'অ্যাকাউন্ট',
      logOut: 'লগ আউট',
      deleteAccount: 'অ্যাকাউন্ট মুছুন',
      selectLanguage: 'ভাষা বেছে নিন',
      cancel: 'বাতিল',
      basics: 'বেসিক',
      style: 'স্টাইল',
      tryOn: 'ট্রাই অন',
      fullName: 'পুরো নাম',
      yourName: 'আপনার নাম',
      username: 'ইউজারনেম',
      email: 'ইমেইল',
      phone: 'ফোন',
      dateOfBirth: 'জন্ম তারিখ',
      gender: 'লিঙ্গ',
      skinTone: 'ত্বকের রঙ',
      shopPreferences: 'শপ পছন্দ',
      faceShape: 'মুখের আকৃতি',
      bodyShape: 'শরীরের আকৃতি',
      chooseStyles: 'আপনার পছন্দের স্টাইল বেছে নিন ✨',
      tapToSelect: 'একাধিক বাছাই করতে ট্যাপ করুন',
      personalizedFitPreview: 'ব্যক্তিগত ফিট প্রিভিউ',
      personalizedFitBody: 'AI ট্রাই-অন এবং পরামর্শের জন্য ছবি আপলোড করুন।',
      enableTryOn: 'ট্রাই-অন চালু করুন',
      uploadFacePhoto: 'মুখের ছবি',
      uploadBodyPhoto: 'শরীরের ছবি',
      uploaded: 'আপলোড হয়েছে ✓',
      uploadPhoto: 'ছবি আপলোড করুন',
      discardChanges: 'পরিবর্তন বাতিল করবেন?',
      discardChangesBody:
      'সংরক্ষিত হয়নি এমন পরিবর্তন আছে। এখন চলে গেলে সেগুলো হারিয়ে যাবে।',
      discard: 'বাতিল করুন',
      keepEditing: 'সম্পাদনা চালিয়ে যান',
      logOutTitle: 'লগ আউট করবেন?',
      logOutBody:
      'আপনি কি লগ আউট করতে নিশ্চিত? পুনরায় অ্যাক্সেসের জন্য সাইন ইন করতে হবে।',
      logOutConfirm: 'লগ আউট',
      enableLocation: 'লোকেশন চালু করুন',
      enableLocationBody: 'কাছের দোকান এবং সুপারিশের জন্য লোকেশন অনুমতি দিন।',
      enableLocationConfirm: 'লোকেশন চালু করুন',
      notNow: 'এখন নয়',
      deleteAccountTitle: 'অ্যাকাউন্ট মুছবেন?',
      deleteAccountBody:
      'এটি আপনার অ্যাকাউন্ট ও ডেটা স্থায়ীভাবে মুছে দেবে। এই কাজ পূর্বাবস্থায় ফেরানো যাবে না।',
      deleteAccountConfirm: 'অ্যাকাউন্ট মুছুন',
      profileUpdated: '✓ প্রোফাইল আপডেট হয়েছে',
      photoUpdated: '✓ ছবি আপডেট হয়েছে',
      loggedOut: '👋 লগ আউট হয়েছে',
      accountDeleted: '🗑️ অ্যাকাউন্ট মুছা হয়েছে',
      locationEnabled: '📍 লোকেশন চালু হয়েছে',
      themeSetTo: '✓ থিম সেট হয়েছে',
      lightModeOn: '☀️ লাইট মোড চালু',
      darkModeOn: '🌙 ডার্ক মোড চালু',
      languageSetTo: '✓ ভাষা সেট হয়েছে',
    ),
    'Marathi': AppStrings(
      myProfile: 'माझी प्रोफाइल',
      editProfile: 'प्रोफाइल संपादित करा',
      preferences: 'प्राधान्ये',
      language: 'भाषा',
      location: 'स्थान',
      appearance: 'देखावा',
      mode: 'मोड',
      darkMode: 'डार्क मोड',
      lightMode: 'लाइट मोड',
      colourTheme: 'रंग थीम',
      account: 'खाते',
      logOut: 'लॉग आउट',
      deleteAccount: 'खाते हटवा',
      selectLanguage: 'भाषा निवडा',
      cancel: 'रद्द करा',
      basics: 'बेसिक्स',
      style: 'स्टाइल',
      tryOn: 'ट्राय ऑन',
      fullName: 'पूर्ण नाव',
      yourName: 'तुमचे नाव',
      username: 'यूझरनेम',
      email: 'ईमेल',
      phone: 'फोन',
      dateOfBirth: 'जन्मतारीख',
      gender: 'लिंग',
      skinTone: 'त्वचेचा रंग',
      shopPreferences: 'खरेदी प्राधान्ये',
      faceShape: 'चेहऱ्याचा आकार',
      bodyShape: 'शरीराचा आकार',
      chooseStyles: 'तुमच्या आवडीच्या स्टाइल्स निवडा ✨',
      tapToSelect: 'अनेक निवडण्यासाठी टॅप करा',
      personalizedFitPreview: 'वैयक्तिक फिट पूर्वावलोकन',
      personalizedFitBody: 'AI ट्राय-ऑन आणि सूचनांसाठी फोटो अपलोड करा.',
      enableTryOn: 'ट्राय-ऑन चालू करा',
      uploadFacePhoto: 'चेहऱ्याचा फोटो',
      uploadBodyPhoto: 'शरीराचा फोटो',
      uploaded: 'अपलोड झाले ✓',
      uploadPhoto: 'फोटो अपलोड करा',
      discardChanges: 'बदल टाकून द्यायचे?',
      discardChangesBody: 'न जतन केलेले बदल आहेत. आता गेल्यास ते हरवतील.',
      discard: 'टाकून द्या',
      keepEditing: 'संपादन सुरू ठेवा',
      logOutTitle: 'लॉग आउट करायचे?',
      logOutBody:
      'तुम्हाला खात्री आहे का? परत प्रवेशासाठी पुन्हा साइन इन करावे लागेल.',
      logOutConfirm: 'लॉग आउट',
      enableLocation: 'स्थान सक्षम करा',
      enableLocationBody: 'जवळच्या दुकाने आणि शिफारसींसाठी स्थान परवानगी द्या.',
      enableLocationConfirm: 'स्थान सक्षम करा',
      notNow: 'आत्ता नाही',
      deleteAccountTitle: 'खाते हटवायचे?',
      deleteAccountBody:
      'हे तुमचे खाते आणि सर्व डेटा कायमचे हटवेल. हे पूर्ववत करता येणार नाही.',
      deleteAccountConfirm: 'खाते हटवा',
      profileUpdated: '✓ प्रोफाइल अपडेट झाली',
      photoUpdated: '✓ फोटो अपडेट झाला',
      loggedOut: '👋 लॉग आउट झालो',
      accountDeleted: '🗑️ खाते हटवले',
      locationEnabled: '📍 स्थान सक्षम झाले',
      themeSetTo: '✓ थीम सेट झाली',
      lightModeOn: '☀️ लाइट मोड चालू',
      darkModeOn: '🌙 डार्क मोड चालू',
      languageSetTo: '✓ भाषा सेट झाली',
    ),
    'French': AppStrings(
      myProfile: 'Mon Profil',
      editProfile: 'Modifier le Profil',
      preferences: 'PRÉFÉRENCES',
      language: 'Langue',
      location: 'Localisation',
      appearance: 'APPARENCE',
      mode: 'MODE',
      darkMode: 'Mode Sombre',
      lightMode: 'Mode Clair',
      colourTheme: 'THÈME COULEUR',
      account: 'COMPTE',
      logOut: 'Se Déconnecter',
      deleteAccount: 'Supprimer le Compte',
      selectLanguage: 'Choisir la Langue',
      cancel: 'Annuler',
      basics: 'Bases',
      style: 'Style',
      tryOn: 'Essayer',
      fullName: 'Nom Complet',
      yourName: 'Votre nom',
      username: "Nom d'utilisateur",
      email: 'Email',
      phone: 'Téléphone',
      dateOfBirth: 'Date de Naissance',
      gender: 'Genre',
      skinTone: 'Teinte de Peau',
      shopPreferences: 'Préférences Boutique',
      faceShape: 'Forme du Visage',
      bodyShape: 'Forme Corporelle',
      chooseStyles: 'Choisissez les styles qui vous correspondent ✨',
      tapToSelect: 'Appuyez pour sélectionner plusieurs',
      personalizedFitPreview: 'Aperçu Personnalisé',
      personalizedFitBody:
      "Téléchargez une photo de visage et de corps pour l'essayage IA et les recommandations.",
      enableTryOn: "Activer l'Essayage",
      uploadFacePhoto: 'Photo du Visage',
      uploadBodyPhoto: 'Photo du Corps',
      uploaded: 'Téléchargé ✓',
      uploadPhoto: 'Télécharger une Photo',
      discardChanges: 'Annuler les Modifications?',
      discardChangesBody:
      'Vous avez des modifications non enregistrées. Si vous partez maintenant, elles seront perdues.',
      discard: 'Annuler',
      keepEditing: 'Continuer à Modifier',
      logOutTitle: 'Se Déconnecter?',
      logOutBody:
      'Êtes-vous sûr de vouloir vous déconnecter? Vous devrez vous reconnecter pour accéder à votre profil.',
      logOutConfirm: 'Se Déconnecter',
      enableLocation: 'Activer la Localisation',
      enableLocationBody:
      'Autorisez l\'application à accéder à votre position pour afficher les magasins à proximité.',
      enableLocationConfirm: 'Activer la Localisation',
      notNow: 'Pas Maintenant',
      deleteAccountTitle: 'Supprimer le Compte?',
      deleteAccountBody:
      'Cela supprimera définitivement votre compte et toutes les données associées.',
      deleteAccountConfirm: 'Supprimer le Compte',
      profileUpdated: '✓ Profil mis à jour',
      photoUpdated: '✓ Photo mise à jour',
      loggedOut: '👋 Déconnecté',
      accountDeleted: '🗑️ Compte supprimé',
      locationEnabled: '📍 Localisation activée',
      themeSetTo: '✓ Thème défini sur',
      lightModeOn: '☀️ Mode clair activé',
      darkModeOn: '🌙 Mode sombre activé',
      languageSetTo: '✓ Langue définie sur',
    ),
    'Spanish': AppStrings(
      myProfile: 'Mi Perfil',
      editProfile: 'Editar Perfil',
      preferences: 'PREFERENCIAS',
      language: 'Idioma',
      location: 'Ubicación',
      appearance: 'APARIENCIA',
      mode: 'MODO',
      darkMode: 'Modo Oscuro',
      lightMode: 'Modo Claro',
      colourTheme: 'TEMA DE COLOR',
      account: 'CUENTA',
      logOut: 'Cerrar Sesión',
      deleteAccount: 'Eliminar Cuenta',
      selectLanguage: 'Seleccionar Idioma',
      cancel: 'Cancelar',
      basics: 'Básicos',
      style: 'Estilo',
      tryOn: 'Probar',
      fullName: 'Nombre Completo',
      yourName: 'Tu nombre',
      username: 'Nombre de Usuario',
      email: 'Correo',
      phone: 'Teléfono',
      dateOfBirth: 'Fecha de Nacimiento',
      gender: 'Género',
      skinTone: 'Tono de Piel',
      shopPreferences: 'Preferencias de Tienda',
      faceShape: 'Forma del Rostro',
      bodyShape: 'Forma Corporal',
      chooseStyles: 'Elige los estilos que van contigo ✨',
      tapToSelect: 'Toca para seleccionar varios',
      personalizedFitPreview: 'Vista Previa Personalizada',
      personalizedFitBody:
      'Sube una foto de cara y cuerpo para el probador IA y recomendaciones.',
      enableTryOn: 'Activar Probador',
      uploadFacePhoto: 'Foto de Cara',
      uploadBodyPhoto: 'Foto de Cuerpo',
      uploaded: 'Subido ✓',
      uploadPhoto: 'Subir Foto',
      discardChanges: '¿Descartar Cambios?',
      discardChangesBody:
      'Tienes cambios sin guardar. Si te vas ahora, se perderán.',
      discard: 'Descartar',
      keepEditing: 'Seguir Editando',
      logOutTitle: '¿Cerrar Sesión?',
      logOutBody:
      '¿Estás seguro de que quieres cerrar sesión? Deberás iniciar sesión de nuevo para acceder a tu perfil.',
      logOutConfirm: 'Cerrar Sesión',
      enableLocation: 'Activar Ubicación',
      enableLocationBody:
      'Permite que la app acceda a tu ubicación para mostrar tiendas cercanas y recomendaciones.',
      enableLocationConfirm: 'Activar Ubicación',
      notNow: 'Ahora No',
      deleteAccountTitle: '¿Eliminar Cuenta?',
      deleteAccountBody:
      'Esto eliminará permanentemente tu cuenta y todos los datos asociados.',
      deleteAccountConfirm: 'Eliminar Cuenta',
      profileUpdated: '✓ Perfil actualizado',
      photoUpdated: '✓ Foto actualizada',
      loggedOut: '👋 Sesión cerrada',
      accountDeleted: '🗑️ Cuenta eliminada',
      locationEnabled: '📍 Ubicación activada',
      themeSetTo: '✓ Tema establecido en',
      lightModeOn: '☀️ Modo claro activado',
      darkModeOn: '🌙 Modo oscuro activado',
      languageSetTo: '✓ Idioma establecido en',
    ),
    'German': AppStrings(
      myProfile: 'Mein Profil',
      editProfile: 'Profil Bearbeiten',
      preferences: 'EINSTELLUNGEN',
      language: 'Sprache',
      location: 'Standort',
      appearance: 'AUSSEHEN',
      mode: 'MODUS',
      darkMode: 'Dunkelmodus',
      lightMode: 'Hellmodus',
      colourTheme: 'FARBTHEMA',
      account: 'KONTO',
      logOut: 'Abmelden',
      deleteAccount: 'Konto Löschen',
      selectLanguage: 'Sprache Auswählen',
      cancel: 'Abbrechen',
      basics: 'Grundlagen',
      style: 'Stil',
      tryOn: 'Anprobieren',
      fullName: 'Vollständiger Name',
      yourName: 'Ihr Name',
      username: 'Benutzername',
      email: 'E-Mail',
      phone: 'Telefon',
      dateOfBirth: 'Geburtsdatum',
      gender: 'Geschlecht',
      skinTone: 'Hautton',
      shopPreferences: 'Shop-Präferenzen',
      faceShape: 'Gesichtsform',
      bodyShape: 'Körperform',
      chooseStyles: 'Wählen Sie Stile, die zu Ihnen passen ✨',
      tapToSelect: 'Tippen, um mehrere auszuwählen',
      personalizedFitPreview: 'Personalisierte Vorschau',
      personalizedFitBody:
      'Laden Sie ein Gesichts- und Körperfoto für KI-Anprobe und Empfehlungen hoch.',
      enableTryOn: 'Anprobe aktivieren',
      uploadFacePhoto: 'Gesichtsfoto',
      uploadBodyPhoto: 'Körperfoto',
      uploaded: 'Hochgeladen ✓',
      uploadPhoto: 'Foto hochladen',
      discardChanges: 'Änderungen verwerfen?',
      discardChangesBody:
      'Sie haben ungespeicherte Änderungen. Wenn Sie jetzt gehen, gehen sie verloren.',
      discard: 'Verwerfen',
      keepEditing: 'Weiter Bearbeiten',
      logOutTitle: 'Abmelden?',
      logOutBody:
      'Möchten Sie sich wirklich abmelden? Sie müssen sich erneut anmelden, um auf Ihr Profil zuzugreifen.',
      logOutConfirm: 'Abmelden',
      enableLocation: 'Standort Aktivieren',
      enableLocationBody:
      'Erlauben Sie der App den Zugriff auf Ihren Standort für nahegelegene Geschäfte und Empfehlungen.',
      enableLocationConfirm: 'Standort Aktivieren',
      notNow: 'Nicht Jetzt',
      deleteAccountTitle: 'Konto Löschen?',
      deleteAccountBody:
      'Dadurch wird Ihr Konto und alle zugehörigen Daten dauerhaft gelöscht.',
      deleteAccountConfirm: 'Konto Löschen',
      profileUpdated: '✓ Profil aktualisiert',
      photoUpdated: '✓ Foto aktualisiert',
      loggedOut: '👋 Abgemeldet',
      accountDeleted: '🗑️ Konto gelöscht',
      locationEnabled: '📍 Standort aktiviert',
      themeSetTo: '✓ Thema gesetzt auf',
      lightModeOn: '☀️ Hellmodus aktiviert',
      darkModeOn: '🌙 Dunkelmodus aktiviert',
      languageSetTo: '✓ Sprache gesetzt auf',
    ),
    'Arabic': AppStrings(
      myProfile: 'ملفي الشخصي',
      editProfile: 'تعديل الملف الشخصي',
      preferences: 'التفضيلات',
      language: 'اللغة',
      location: 'الموقع',
      appearance: 'المظهر',
      mode: 'الوضع',
      darkMode: 'الوضع المظلم',
      lightMode: 'الوضع الفاتح',
      colourTheme: 'نظام الألوان',
      account: 'الحساب',
      logOut: 'تسجيل الخروج',
      deleteAccount: 'حذف الحساب',
      selectLanguage: 'اختر اللغة',
      cancel: 'إلغاء',
      basics: 'الأساسيات',
      style: 'الأسلوب',
      tryOn: 'تجربة',
      fullName: 'الاسم الكامل',
      yourName: 'اسمك',
      username: 'اسم المستخدم',
      email: 'البريد الإلكتروني',
      phone: 'الهاتف',
      dateOfBirth: 'تاريخ الميلاد',
      gender: 'الجنس',
      skinTone: 'لون البشرة',
      shopPreferences: 'تفضيلات التسوق',
      faceShape: 'شكل الوجه',
      bodyShape: 'شكل الجسم',
      chooseStyles: 'اختر الأساليب التي تناسبك ✨',
      tapToSelect: 'اضغط لاختيار أكثر من واحد',
      personalizedFitPreview: 'معاينة مخصصة',
      personalizedFitBody:
      'ارفع صورة وجه وجسم لتجربة ملابس بالذكاء الاصطناعي والتوصيات.',
      enableTryOn: 'تفعيل التجربة',
      uploadFacePhoto: 'صورة الوجه',
      uploadBodyPhoto: 'صورة الجسم',
      uploaded: 'تم الرفع ✓',
      uploadPhoto: 'ارفع صورة',
      discardChanges: 'تجاهل التغييرات؟',
      discardChangesBody: 'لديك تغييرات غير محفوظة. إذا غادرت الآن ستفقدها.',
      discard: 'تجاهل',
      keepEditing: 'متابعة التعديل',
      logOutTitle: 'تسجيل الخروج؟',
      logOutBody:
      'هل أنت متأكد من تسجيل الخروج؟ ستحتاج إلى تسجيل الدخول مرة أخرى.',
      logOutConfirm: 'تسجيل الخروج',
      enableLocation: 'تفعيل الموقع',
      enableLocationBody:
      'اسمح للتطبيق بالوصول إلى موقعك لعرض المتاجر القريبة والتوصيات.',
      enableLocationConfirm: 'تفعيل الموقع',
      notNow: 'ليس الآن',
      deleteAccountTitle: 'حذف الحساب؟',
      deleteAccountBody:
      'سيؤدي هذا إلى حذف حسابك وجميع بياناتك نهائياً. لا يمكن التراجع عن هذا الإجراء.',
      deleteAccountConfirm: 'حذف الحساب',
      profileUpdated: '✓ تم تحديث الملف الشخصي',
      photoUpdated: '✓ تم تحديث الصورة',
      loggedOut: '👋 تم تسجيل الخروج',
      accountDeleted: '🗑️ تم حذف الحساب',
      locationEnabled: '📍 تم تفعيل الموقع',
      themeSetTo: '✓ تم ضبط الثيم على',
      lightModeOn: '☀️ الوضع الفاتح',
      darkModeOn: '🌙 الوضع المظلم',
      languageSetTo: '✓ تم ضبط اللغة على',
    ),
    'Japanese': AppStrings(
      myProfile: 'マイプロフィール',
      editProfile: 'プロフィール編集',
      preferences: '設定',
      language: '言語',
      location: '位置情報',
      appearance: '外観',
      mode: 'モード',
      darkMode: 'ダークモード',
      lightMode: 'ライトモード',
      colourTheme: 'カラーテーマ',
      account: 'アカウント',
      logOut: 'ログアウト',
      deleteAccount: 'アカウント削除',
      selectLanguage: '言語を選択',
      cancel: 'キャンセル',
      basics: '基本',
      style: 'スタイル',
      tryOn: '試着',
      fullName: 'フルネーム',
      yourName: 'あなたの名前',
      username: 'ユーザー名',
      email: 'メール',
      phone: '電話',
      dateOfBirth: '生年月日',
      gender: '性別',
      skinTone: '肌のトーン',
      shopPreferences: 'ショップ設定',
      faceShape: '顔の形',
      bodyShape: '体型',
      chooseStyles: 'あなたに合うスタイルを選んでください ✨',
      tapToSelect: 'タップして複数選択',
      personalizedFitPreview: 'パーソナライズフィットプレビュー',
      personalizedFitBody: 'AI試着とおすすめのために顔と体の写真をアップロードしてください。',
      enableTryOn: '試着を有効にする',
      uploadFacePhoto: '顔写真',
      uploadBodyPhoto: '体写真',
      uploaded: 'アップロード済み ✓',
      uploadPhoto: '写真をアップロード',
      discardChanges: '変更を破棄しますか？',
      discardChangesBody: '未保存の変更があります。今離れると変更が失われます。',
      discard: '破棄',
      keepEditing: '編集を続ける',
      logOutTitle: 'ログアウトしますか？',
      logOutBody: 'ログアウトしてもよいですか？再度アクセスするにはサインインが必要です。',
      logOutConfirm: 'ログアウト',
      enableLocation: '位置情報を有効にする',
      enableLocationBody: '近くの店舗やおすすめを表示するために位置情報へのアクセスを許可してください。',
      enableLocationConfirm: '位置情報を有効にする',
      notNow: '後で',
      deleteAccountTitle: 'アカウントを削除しますか？',
      deleteAccountBody: 'アカウントと関連データが完全に削除されます。この操作は取り消せません。',
      deleteAccountConfirm: 'アカウントを削除',
      profileUpdated: '✓ プロフィールを更新しました',
      photoUpdated: '✓ 写真を更新しました',
      loggedOut: '👋 ログアウトしました',
      accountDeleted: '🗑️ アカウントを削除しました',
      locationEnabled: '📍 位置情報を有効にしました',
      themeSetTo: '✓ テーマを設定しました:',
      lightModeOn: '☀️ ライトモード ON',
      darkModeOn: '🌙 ダークモード ON',
      languageSetTo: '✓ 言語を設定しました:',
    ),
  };
}

const List<Color> kSkinTones = [
  Color(0xFFFDDBB4),
  Color(0xFFF5C6A0),
  Color(0xFFE8A87C),
  Color(0xFFC68642),
  Color(0xFF8D5524),
  Color(0xFF4A2912),
  Color(0xFF2C1A0E),
  Color(0xFF1A0D07),
];

const List<Map<String, String>> kStyleCards = [
  {'label': 'Clean Minimal', 'img': 'assets/styles/clean_minimal.png'},
  {'label': 'Soft Elegant', 'img': 'assets/styles/soft_elegant.png'},
  {'label': 'Street Cool', 'img': 'assets/styles/street_cool.png'},
  {'label': 'Boho Artisanal', 'img': 'assets/styles/boho_artisinal.png'},
  {'label': 'Party Glam', 'img': 'assets/styles/party_galm.png'},
  {'label': 'Formal Chic', 'img': 'assets/styles/formal_chic.png'},
];

const List<Map<String, String>> kShopPrefs = [
  {'label': 'Women', 'gender': 'women', 'img': 'assets/shop/women.jpg'},
  {'label': 'Men', 'gender': 'men', 'img': 'assets/shop/men.jpg'},
  {
    'label': 'Accessories',
    'gender': 'both',
    'img': 'assets/shop/accessories.jpg',
  },
  {'label': 'Ethnic', 'gender': 'both', 'img': 'assets/shop/ethnic.jpg'},
];

const List<Map<String, String>> kFaceShapes = [
  {'name': 'Oval', 'img': 'assets/face_shapes/oval.jpeg'},
  {'name': 'Round', 'img': 'assets/face_shapes/round.jpeg'},
  {'name': 'Square', 'img': 'assets/face_shapes/square.jpeg'},
  {'name': 'Heart', 'img': 'assets/face_shapes/heart.jpeg'},
  {'name': 'Diamond', 'img': 'assets/face_shapes/diamond.jpeg'},
  {'name': 'Oblong', 'img': 'assets/face_shapes/oblong.jpeg'},
];

const Map<String, List<Map<String, String>>> kBodyShapes = {
  'women': [
    {'name': 'Hourglass', 'img': 'assets/body_shapes/women_hourglass.jpeg'},
    {'name': 'Apple', 'img': 'assets/body_shapes/women_apple.jpeg'},
    {'name': 'Rectangle', 'img': 'assets/body_shapes/women_rectangle.jpeg'},
    {'name': 'Inverted', 'img': 'assets/body_shapes/women_inverted.jpeg'},
    {'name': 'Pear', 'img': 'assets/body_shapes/women_pear.jpeg'},
  ],
  'men': [
    {'name': 'Traingle', 'img': 'assets/body_shapes/men_traingle.jpeg'},
    {'name': 'Rectangle', 'img': 'assets/body_shapes/men_rectangle.jpeg'},
    {'name': 'Oval', 'img': 'assets/body_shapes/men_oval.jpeg'},
    {'name': 'Inverted', 'img': 'assets/body_shapes/men_inverted.jpeg'},
    {'name': 'Trapezoid', 'img': 'assets/body_shapes/men_trapezoid.jpeg'},
  ],
};

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE CONTROLLER  (ChangeNotifier — used via Provider in main.dart)
// ─────────────────────────────────────────────────────────────────────────────

class ProfileController extends ChangeNotifier {
  ProfileState _state = ProfileState();

  ProfileState get state => _state;

  void update(ProfileState newState) {
    _state = newState;
    notifyListeners();
  }

  void setLanguage(String newLang) {
    // ⚠️ CRITICAL: Prevent infinite update loop
    if (_state.lang == newLang) return;

    _state = _state.copyWith(lang: newLang);
    notifyListeners();
  }

  /// Called by onboarding1.dart
  void updateBasics({
    String? name,
    String? username,
    String? email,
    String? phone,
    String? dob,
    String? gender,
    int? skinTone,
    String? faceShape,
    String? bodyShape,
    Set<String>? shopPrefs,
    String? lang,
    String? avatarPath,
  }) {
    _state = _state.copyWith(
      name: name,
      username: username,
      email: email,
      phone: phone,
      dob: dob,
      gender: gender,
      skinTone: skinTone,
      faceShape: faceShape,
      bodyShape: bodyShape,
      shopPrefs: shopPrefs,
      lang: lang,
      avatarPath: avatarPath,
    );
    notifyListeners();
  }

  /// Called by onboarding2.dart
  void updateStyles(Set<String> styles) {
    _state = _state.copyWith(styles: styles);
    notifyListeners();
  }

  /// Called by onboarding3.dart
  void updatePersonalization({
    required bool enabled,
    required bool faceUploaded,
    required bool bodyUploaded,
  }) {
    // Personalization flags are stored locally in the onboarding screen;
    // notify listeners so any dependent widget can rebuild if needed.
    notifyListeners();
  }

  /// Full-state update used internally by ProfileScreen
  void updateState(ProfileState newState) {
    _state = newState;
    notifyListeners();
  }

  /// Clears all profile data on logout — resets to factory defaults
  void reset() {
    _state = ProfileState();
    notifyListeners();
  }

  /// Call this right after a successful Google / Apple / Email login.
  /// Pulls the display name and email from the Appwrite account object
  /// so the profile never shows the "New User" placeholder.
  void loadFromAccount({required String? name, required String? email}) {
    final resolvedName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : _state.name;
    final resolvedEmail = (email != null && email.trim().isNotEmpty)
        ? email.trim()
        : _state.email;

    // Derive a username from the display name if still at the placeholder
    final resolvedUsername =
    _state.username == '@username' && resolvedName != 'New User'
        ? '@${resolvedName.toLowerCase().replaceAll(' ', '_')}'
        : _state.username;

    _state = _state.copyWith(
      name: resolvedName,
      email: resolvedEmail,
      username: resolvedUsername,
    );
    notifyListeners();
  }

  /// Rehydrates the rest of the profile (gender, dob, phone, skinTone,
  /// faceShape, bodyShape, styles, shopPrefs) from the Appwrite "users"
  /// document. Call this on cold start right after fetching the profile
  /// doc — otherwise ProfileState()'s hardcoded defaults (e.g. gender
  /// defaulting to 'Female') silently override whatever the user actually
  /// picked during onboarding.
  void hydrateFromProfileDoc(Map<String, dynamic>? doc) {
    if (doc == null) return;

    String? asNonEmptyString(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    // onboarding1.dart saves gender lowercased ('male'/'female'/'others'),
    // but the UI (edit-profile pills, ['Male','Female','Others']) compares
    // against Title-Case. Normalize so the saved value actually matches.
    String? titleCase(dynamic v) {
      final s = asNonEmptyString(v);
      if (s == null) return null;
      return s[0].toUpperCase() + s.substring(1).toLowerCase();
    }

    int? asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    Set<String>? asStringSet(dynamic v) {
      if (v is List) {
        final set = v.map((e) => e.toString()).toSet();
        return set.isEmpty ? null : set;
      }
      return null;
    }

    _state = _state.copyWith(
      name: asNonEmptyString(doc['name']),
      phone: asNonEmptyString(doc['phone']),
      dob: asNonEmptyString(doc['dob']),
      gender: titleCase(doc['gender']),
      skinTone: asInt(doc['skinTone']),
      faceShape: asNonEmptyString(doc['faceShape']),
      bodyShape: asNonEmptyString(doc['bodyShape']),
      styles: asStringSet(doc['stylePreferences']),
      shopPrefs: asStringSet(doc['shopPrefs']),
    );
    notifyListeners();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE SCREEN  (widget referenced by home.dart nav bar)
// ─────────────────────────────────────────────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final profileCtrl = context.watch<ProfileController>();
    final s = profileCtrl.state;
    final colors = themeMap[s.theme]!;
    return ProfilePage(
      state: s,
      colors: colors,
      onStateChange: (newState) {
        // dark mode లేదా accent theme మారినప్పుడు ThemeController కి sync చేయి
        _syncTheme(context, newState, s);
        profileCtrl.updateState(newState);
      },
    );
  }

  void _syncTheme(
      BuildContext context,
      ProfileState newState,
      ProfileState oldState,
      ) {
    try {
      final themeCtrl = Provider.of<ThemeController>(context, listen: false);

      // Dark/Light mode sync
      if (newState.isDark != oldState.isDark) {
        themeCtrl.setThemeMode(
          newState.isDark ? ThemeMode.dark : ThemeMode.light,
        );
      }

      // Accent theme sync — AppTheme → ProfileTheme convert చేసి set చేయి
      if (newState.theme != oldState.theme) {
        final profileTheme = ProfileTheme.values.firstWhere(
              (t) => t.name == newState.theme.name,
          orElse: () => ProfileTheme.coolBlue,
        );
        themeCtrl.setTheme(profileTheme);
      }
    } catch (_) {
      // ThemeController not available — ProfileState alone drives UI
    }
  }
}

class ProfilePage extends StatefulWidget {
  final ProfileState state;
  final ThemeColors colors;
  final ValueChanged<ProfileState> onStateChange;

  const ProfilePage({
    super.key,
    required this.state,
    required this.colors,
    required this.onStateChange,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  bool _showEdit = false;

  ProfileState get s => context.read<ProfileController>().state;
  ThemeColors get c => themeMap[s.theme]!;

  Color get _bg => s.isDark ? const Color(0xFF0D0E14) : const Color(0xFFF4F4F8);
  Color get _bg2 =>
      s.isDark ? const Color(0xFF13141C) : const Color(0xFFECECF4);
  Color get _panel =>
      s.isDark ? const Color(0xFF1A1C26) : const Color(0xFFE6E7F0);
  Color get _card => s.isDark ? const Color(0xFF181922) : Colors.white;
  Color get _cardBorder => s.isDark
      ? Colors.white.withOpacity(0.07)
      : Colors.black.withOpacity(0.07);
  Color get _textPrimary =>
      s.isDark ? const Color(0xFFF0F0F8) : const Color(0xFF18192A);
  Color get _textMuted => s.isDark
      ? const Color(0xFFB4B6D2).withOpacity(0.65)
      : const Color(0xFF50526E).withOpacity(0.65);
  Color get _danger =>
      s.isDark ? const Color(0xFFF06080) : const Color(0xFFD94060);

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: TextStyle(
            color: _textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: _bg2,
        shape: const StadiumBorder(),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 2200),
      ),
    );
  }

  void _update(ProfileState newState) {
    widget.onStateChange(newState);
    setState(
          () {},
    ); // force rebuild so language/theme changes reflect immediately
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: s.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _bg,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _showEdit
              ? _EditView(
            key: const ValueKey('edit'),
            state: s,
            colors: c,
            bg: _bg,
            bg2: _bg2,
            panel: _panel,
            card: _card,
            cardBorder: _cardBorder,
            textPrimary: _textPrimary,
            textMuted: _textMuted,
            onSave: (newState) {
              _update(newState);
              setState(() => _showEdit = false);
              _showToast(AppStrings.of(newState.lang).profileUpdated);
            },
            onDiscard: () => setState(() => _showEdit = false),
            onToast: _showToast,
          )
              : _ProfileView(
            key: const ValueKey('profile'),
            state: s,
            colors: c,
            bg: _bg,
            bg2: _bg2,
            panel: _panel,
            card: _card,
            cardBorder: _cardBorder,
            textPrimary: _textPrimary,
            textMuted: _textMuted,
            danger: _danger,
            onEditTap: () => setState(() => _showEdit = true),
            onStateChange: _update,
            onToast: _showToast,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileView extends StatelessWidget {
  final ProfileState state;
  final ThemeColors colors;
  final Color bg, bg2, panel, card, cardBorder, textPrimary, textMuted, danger;
  final VoidCallback onEditTap;
  final ValueChanged<ProfileState> onStateChange;
  final ValueChanged<String> onToast;

  const _ProfileView({
    super.key,
    required this.state,
    required this.colors,
    required this.bg,
    required this.bg2,
    required this.panel,
    required this.card,
    required this.cardBorder,
    required this.textPrimary,
    required this.textMuted,
    required this.danger,
    required this.onEditTap,
    required this.onStateChange,
    required this.onToast,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(state.lang);
    return SafeArea(
      child: Column(
        children: [
          // Top bar
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
            child: Row(
              children: [
                _HeaderBtn(
                  icon: '‹',
                  bg: panel,
                  border: cardBorder,
                  textMuted: textMuted,
                  onTap: () => Navigator.maybePop(context),
                ),
                const Spacer(),
                Text(
                  t.myProfile,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 36),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Column(
                        children: [
                          _AvatarWidget(
                            state: state,
                            colors: colors,
                            bg: bg,
                            bg2: bg2,
                            size: 92,
                            onPickImage: null,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            state.name,
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.7,
                            ),
                          ),
                          const SizedBox(height: 20),
                          GestureDetector(
                            onTap: onEditTap,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 30,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [colors.accent1, colors.accent2],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(100),
                                boxShadow: [
                                  BoxShadow(
                                    color: colors.accent1.withOpacity(0.3),
                                    blurRadius: 28,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '✎',
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    t.editProfile,
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Preferences Section
                  _SectionLabel(label: t.preferences, textMuted: textMuted),
                  _SectionGroup(
                    children: [
                      _ListItem(
                        icon: '🌐',
                        iconAccent: true,
                        label: t.language,
                        meta: state.lang,
                        colors: colors,
                        card: card,
                        cardBorder: cardBorder,
                        textPrimary: textPrimary,
                        textMuted: textMuted,
                        onTap: () => _showLanguageModal(context, t),
                      ),
                      _ListItem(
                        icon: '📍',
                        iconAccent: true,
                        label: t.location,
                        meta: state.locationLabel,
                        colors: colors,
                        card: card,
                        cardBorder: cardBorder,
                        textPrimary: textPrimary,
                        textMuted: textMuted,
                        onTap: () => _showLocationModal(context, t),
                      ),
                    ],
                  ),

                  // Appearance Section
                  _SectionLabel(label: t.appearance, textMuted: textMuted),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: card,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.mode,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: textMuted,
                              letterSpacing: 1.3,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Consumer<ThemeController>(
                            builder: (context, themeCtrl, _) {
                              return SegmentedButton<ThemeMode>(
                                style: ButtonStyle(
                                  backgroundColor:
                                  WidgetStateProperty.resolveWith((states) {
                                    if (states.contains(
                                      WidgetState.selected,
                                    ))
                                      return colors.accent1.withOpacity(
                                        0.18,
                                      );
                                    return Colors.transparent;
                                  }),
                                  foregroundColor:
                                  WidgetStateProperty.resolveWith((states) {
                                    if (states.contains(
                                      WidgetState.selected,
                                    ))
                                      return colors.accent1;
                                    return textMuted;
                                  }),
                                  side: WidgetStatePropertyAll(
                                    BorderSide(color: cardBorder),
                                  ),
                                ),
                                segments: const [
                                  ButtonSegment(
                                    value: ThemeMode.light,
                                    label: Text(
                                      'Light',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    icon: Icon(Icons.light_mode, size: 15),
                                  ),
                                  ButtonSegment(
                                    value: ThemeMode.dark,
                                    label: Text(
                                      'Dark',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    icon: Icon(Icons.dark_mode, size: 15),
                                  ),
                                ],
                                selected: {themeCtrl.themeMode},
                                onSelectionChanged: (value) {
                                  final mode = value.first;
                                  themeCtrl.setThemeMode(mode);
                                  if (mode == ThemeMode.dark) {
                                    onStateChange(state.copyWith(isDark: true));
                                    onToast('🌙 Dark mode on');
                                  } else if (mode == ThemeMode.light) {
                                    onStateChange(
                                      state.copyWith(isDark: false),
                                    );
                                    onToast('☀️ Light mode on');
                                  }
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          Text(
                            t.colourTheme,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: textMuted,
                              letterSpacing: 1.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _ThemeRow(
                            state: state,
                            colors: colors,
                            panel: panel,
                            textPrimary: textPrimary,
                            textMuted: textMuted,
                            onSelect: (th) {
                              onStateChange(state.copyWith(theme: th));
                              final names = {
                                AppTheme.coolBlue: 'Cool Blue',
                                AppTheme.sunsetPop: 'Sunset Pop',
                                AppTheme.futureCandy: 'Future Candy',
                              };
                              onToast('${t.themeSetTo} ${names[th]}');
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Account Section
                  _SectionLabel(label: t.account, textMuted: textMuted),
                  _SectionGroup(
                    children: [
                      _ListItem(
                        icon: '🚪',
                        iconDanger: true,
                        label: t.logOut,
                        labelDanger: true,
                        colors: colors,
                        card: card,
                        cardBorder: cardBorder,
                        textPrimary: textPrimary,
                        textMuted: textMuted,
                        danger: danger,
                        onTap: () => _showLogoutModal(context, t),
                      ),
                      _ListItem(
                        icon: '🗑️',
                        iconDanger: true,
                        label: t.deleteAccount,
                        labelDanger: true,
                        colors: colors,
                        card: card,
                        cardBorder: cardBorder,
                        textPrimary: textPrimary,
                        textMuted: textMuted,
                        danger: danger,
                        onTap: () => _showDeleteAccountModal(context, t),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLanguageModal(BuildContext context, AppStrings t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: bg2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) => _LanguageSheet(
        current: state.lang,
        bg2: bg2,
        cardBorder: cardBorder,
        textPrimary: textPrimary,
        textMuted: textMuted,
        accentColor: colors.accent1,
        selectLanguageLabel: t.selectLanguage,
        cancelLabel: t.cancel,
        onSelect: (lang) {
          Navigator.pop(modalContext);
          final newState = state.copyWith(lang: lang);
          onStateChange(newState);
          onToast('${AppStrings.of(lang).languageSetTo} $lang');
        },
      ),
    );
  }

  void _showLogoutModal(BuildContext context, AppStrings t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: bg2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ConfirmSheet(
        icon: '🚪',
        isDanger: true,
        title: t.logOutTitle,
        body: t.logOutBody,
        confirmLabel: t.logOutConfirm,
        cancelLabel: t.cancel,
        bg2: bg2,
        cardBorder: cardBorder,
        textPrimary: textPrimary,
        textMuted: textMuted,
        panel: panel,
        danger: danger,
        accentColor: colors.accent1,
        onConfirm: () async {
          Navigator.pop(context);
          try {
            // 1. Delete Appwrite session so getCurrentUser() returns null
            final appwrite = Provider.of<AppwriteService>(
              context,
              listen: false,
            );
            // Try logout() method first; fallback to deleteSession directly
            try {
              await appwrite.logout();
            } catch (_) {
              await appwrite.account.deleteSession(sessionId: 'current');
            }
          } catch (_) {}
          // 2. Reset ProfileController — clears name, avatar, email, etc.
          if (context.mounted) {
            Provider.of<ProfileController>(context, listen: false).reset();
          }
          // 3. Clear onboardingComplete so next login shows onboarding
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('onboardingComplete', false);
          // 4. Navigate to SignIn, clear entire stack
          if (context.mounted) {
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil(AppRoutes.signin, (route) => false);
          }
        },
        onCancel: () => Navigator.pop(context),
      ),
    );
  }

  void _showLocationModal(BuildContext context, AppStrings t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: bg2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ConfirmSheet(
        icon: '📍',
        isDanger: false,
        title: t.enableLocation,
        body: t.enableLocationBody,
        confirmLabel: t.enableLocationConfirm,
        cancelLabel: t.notNow,
        bg2: bg2,
        cardBorder: cardBorder,
        textPrimary: textPrimary,
        textMuted: textMuted,
        panel: panel,
        danger: danger,
        accentColor: colors.accent1,
        onConfirm: () async {
          Navigator.pop(context);
          await _fetchAndUpdateLocation(context, t);
        },
        onCancel: () => Navigator.pop(context),
      ),
    );
  }

  Future<void> _fetchAndUpdateLocation(
      BuildContext context,
      AppStrings t,
      ) async {
    try {
      // Permission check
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          onToast('Location permission denied');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        onToast('Location permission permanently denied. Enable in settings.');
        await Geolocator.openAppSettings();
        return;
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      // Reverse geocode using Nominatim (OpenStreetMap) — no package needed
      String label =
          '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
      try {
        final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse'
              '?lat=${position.latitude}&lon=${position.longitude}'
              '&format=json&addressdetails=1',
        );
        final response = await http
            .get(
          uri,
          headers: {'User-Agent': 'AhviApp/1.0', 'Accept-Language': 'en'},
        )
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final address = data['address'] as Map<String, dynamic>? ?? {};

          // Pick best available name, most specific first
          final city = (address['city'] ?? '').toString().trim();
          final town = (address['town'] ?? '').toString().trim();
          final village = (address['village'] ?? '').toString().trim();
          final suburb = (address['suburb'] ?? '').toString().trim();
          final district = (address['district'] ?? '').toString().trim();
          final county = (address['county'] ?? '').toString().trim();
          final state = (address['state'] ?? '').toString().trim();
          final country = (address['country_code'] ?? '')
              .toString()
              .toUpperCase()
              .trim();

          final place = city.isNotEmpty
              ? city
              : town.isNotEmpty
              ? town
              : village.isNotEmpty
              ? village
              : suburb.isNotEmpty
              ? suburb
              : district.isNotEmpty
              ? district
              : county.isNotEmpty
              ? county
              : state;

          if (place.isNotEmpty) {
            label = country.isNotEmpty ? '$place, $country' : place;
          }
        }
      } catch (geocodeError) {
        debugPrint('Geocoding error: $geocodeError');
      }

      onStateChange(state.copyWith(locationLabel: label));
      onToast(t.locationEnabled);
    } catch (e) {
      onToast('Could not get location: ${e.toString()}');
    }
  }

  void _showDeleteAccountModal(BuildContext context, AppStrings t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: bg2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ConfirmSheet(
        icon: '🗑️',
        isDanger: true,
        title: t.deleteAccountTitle,
        body: t.deleteAccountBody,
        confirmLabel: t.deleteAccountConfirm,
        cancelLabel: t.cancel,
        bg2: bg2,
        cardBorder: cardBorder,
        textPrimary: textPrimary,
        textMuted: textMuted,
        panel: panel,
        danger: danger,
        accentColor: colors.accent1,
        onConfirm: () async {
          Navigator.pop(context);
          try {
            final appwrite = Provider.of<AppwriteService>(
              context,
              listen: false,
            );

            // STEP 2: Call the FastAPI backend to wipe the account, wardrobe,
            // and style history from the server.  Throws on failure so we
            // can show an error and abort before touching local state.
            final userId = appwrite.currentUserId ?? '';
            if (userId.isNotEmpty) {
              await appwrite.deleteAccountFromBackend(userId);
            }

            // STEP 2b: Tear down Appwrite sessions on all devices.
            try {
              await appwrite.deleteAccount();
            } catch (_) {
              // Fallback: at minimum kill the current session
              try {
                await appwrite.account.deleteSession(sessionId: 'current');
              } catch (_) {}
            }

            // STEP 3: Wipe ALL local storage so this device has zero memory
            // of onboarding, Style DNA, cached user identity, OTP state, etc.
            // A re-signup on this device will be treated as brand-new.
            final prefs = await SharedPreferences.getInstance();
            await prefs.clear();

            // STEP 4: Clear in-memory Provider / app state.
            if (context.mounted) {
              Provider.of<ProfileController>(context, listen: false).reset();
              appwrite.clearUserCache();
              await appwrite.clearCachedUserIdentity();
            }

            // STEP 5: Navigate to SignIn, clear entire back-stack.
            if (context.mounted) {
              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil(AppRoutes.signin, (route) => false);
            }
          } catch (e) {
            debugPrint('AHVI_DELETE_ACCOUNT_ERROR: $e');
            // Surface the failure so the user knows deletion did not complete.
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Could not delete account. Please try again.',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  backgroundColor: bg2,
                  shape: const StadiumBorder(),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(milliseconds: 3000),
                ),
              );
            }
          }
        },
        onCancel: () => Navigator.pop(context),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EDIT VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _EditView extends StatefulWidget {
  final ProfileState state;
  final ThemeColors colors;
  final Color bg, bg2, panel, card, cardBorder, textPrimary, textMuted;
  final ValueChanged<ProfileState> onSave;
  final VoidCallback onDiscard;
  final ValueChanged<String> onToast;

  const _EditView({
    super.key,
    required this.state,
    required this.colors,
    required this.bg,
    required this.bg2,
    required this.panel,
    required this.card,
    required this.cardBorder,
    required this.textPrimary,
    required this.textMuted,
    required this.onSave,
    required this.onDiscard,
    required this.onToast,
  });

  @override
  State<_EditView> createState() => _EditViewState();
}

class _EditViewState extends State<_EditView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _dobCtrl;

  late ProfileState _draft;
  bool _isDirty = false;
  bool _faceUploaded = false;
  bool _bodyUploaded = false;
  bool _tryOnEnabled = false;
  String _bodyGender =
      'women'; // tracks which gender tab is selected in Body Shape

  // ── Face analyser (mirrors onboarding3) ──
  late FaceDetector _faceDetector;
  bool _isAnalyzingFace = false;
  FaceAnalysisData? _faceAnalysisData;
  final ImagePicker _facePicker = ImagePicker();

  // ── Country code picker state (mirrors onboarding1) ──
  String _selectedCountryCode = '+91';
  String _selectedCountryFlag = '🇮🇳';
  int _selectedCountryMaxDigits = 10;
  OverlayEntry? _countryDropdownOverlay;
  final LayerLink _countryLayerLink = LayerLink();

  // ── DOB state (mirrors onboarding1) ──
  String? _dobDay;
  String? _dobMonth;
  String? _dobYear;

  // ── Gender pill press states ──
  final List<bool> _genderPillPressed = [false, false, false];

  static const List<Map<String, dynamic>> _countries = [
    {'flag': '🇮🇳', 'name': 'India', 'code': '+91', 'digits': 10},
    {'flag': '🇺🇸', 'name': 'United States', 'code': '+1', 'digits': 10},
    {'flag': '🇬🇧', 'name': 'United Kingdom', 'code': '+44', 'digits': 10},
    {'flag': '🇦🇺', 'name': 'Australia', 'code': '+61', 'digits': 9},
    {'flag': '🇨🇦', 'name': 'Canada', 'code': '+1', 'digits': 10},
    {'flag': '🇩🇪', 'name': 'Germany', 'code': '+49', 'digits': 11},
    {'flag': '🇫🇷', 'name': 'France', 'code': '+33', 'digits': 9},
    {'flag': '🇯🇵', 'name': 'Japan', 'code': '+81', 'digits': 10},
    {'flag': '🇨🇳', 'name': 'China', 'code': '+86', 'digits': 11},
    {'flag': '🇧🇷', 'name': 'Brazil', 'code': '+55', 'digits': 11},
    {'flag': '🇸🇬', 'name': 'Singapore', 'code': '+65', 'digits': 8},
    {'flag': '🇦🇪', 'name': 'UAE', 'code': '+971', 'digits': 9},
    {'flag': '🇵🇰', 'name': 'Pakistan', 'code': '+92', 'digits': 10},
    {'flag': '🇧🇩', 'name': 'Bangladesh', 'code': '+880', 'digits': 10},
    {'flag': '🇱🇰', 'name': 'Sri Lanka', 'code': '+94', 'digits': 9},
    {'flag': '🇳🇵', 'name': 'Nepal', 'code': '+977', 'digits': 10},
    {'flag': '🇲🇾', 'name': 'Malaysia', 'code': '+60', 'digits': 10},
    {'flag': '🇹🇭', 'name': 'Thailand', 'code': '+66', 'digits': 9},
    {'flag': '🇰🇷', 'name': 'South Korea', 'code': '+82', 'digits': 10},
    {'flag': '🇳🇬', 'name': 'Nigeria', 'code': '+234', 'digits': 10},
    {'flag': '🇿🇦', 'name': 'South Africa', 'code': '+27', 'digits': 9},
    {'flag': '🇷🇺', 'name': 'Russia', 'code': '+7', 'digits': 10},
    {'flag': '🇰🇪', 'name': 'Kenya', 'code': '+254', 'digits': 9},
    {'flag': '🇵🇭', 'name': 'Philippines', 'code': '+63', 'digits': 10},
    {'flag': '🇮🇩', 'name': 'Indonesia', 'code': '+62', 'digits': 11},
    {'flag': '🇻🇳', 'name': 'Vietnam', 'code': '+84', 'digits': 10},
    {'flag': '🇹🇷', 'name': 'Turkey', 'code': '+90', 'digits': 10},
    {'flag': '🇮🇱', 'name': 'Israel', 'code': '+972', 'digits': 9},
    {'flag': '🇪🇬', 'name': 'Egypt', 'code': '+20', 'digits': 10},
    {'flag': '🇲🇦', 'name': 'Morocco', 'code': '+212', 'digits': 9},
    {'flag': '🇳🇿', 'name': 'New Zealand', 'code': '+64', 'digits': 9},
  ];

  ThemeColors get c => widget.colors;
  AppStrings get _t => AppStrings.of(_draft.lang);
  Color get _bg => widget.bg;
  Color get _panel => widget.panel;
  Color get _card => widget.card;
  Color get _cardBorder => widget.cardBorder;
  Color get _textPrimary => widget.textPrimary;
  Color get _textMuted => widget.textMuted;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _faceUploaded = false;
    _bodyUploaded = false;
    _initializeFaceDetector();
    _draft = widget.state.copyWith();
    _nameCtrl = TextEditingController(text: widget.state.name);
    _emailCtrl = TextEditingController(text: widget.state.email);
    _dobCtrl = TextEditingController(text: widget.state.dob);

    // ── Parse existing phone into country code + number ──
    final phone = widget.state.phone;
    if (phone.isNotEmpty) {
      // Try to split "CODE NUMBER" e.g. "+91 9876543210"
      final spaceIdx = phone.indexOf(' ');
      if (spaceIdx > 0) {
        final code = phone.substring(0, spaceIdx);
        final number = phone.substring(spaceIdx + 1);
        final match = _countries.firstWhere(
              (c) => c['code'] == code,
          orElse: () => _countries.first,
        );
        _selectedCountryCode = match['code'] as String;
        _selectedCountryFlag = match['flag'] as String;
        _selectedCountryMaxDigits = match['digits'] as int;
        _phoneCtrl = TextEditingController(text: number);
      } else {
        _phoneCtrl = TextEditingController(text: phone);
      }
    } else {
      _phoneCtrl = TextEditingController();
    }

    // ── Parse existing DOB "DD MMMM YYYY" ──
    final dob = widget.state.dob;
    if (dob.isNotEmpty) {
      final parts = dob.split(' ');
      if (parts.length == 3) {
        _dobDay = parts[0];
        _dobMonth = parts[1];
        _dobYear = parts[2];
      }
    }

    // ── Sync bodyGender from existing shopPrefs ──
    if (widget.state.shopPrefs.contains('Men') &&
        !widget.state.shopPrefs.contains('Women')) {
      _bodyGender = 'men';
    } else {
      _bodyGender = 'women';
    }
  }

  @override
  void dispose() {
    _countryDropdownOverlay?.remove();
    _tabController.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _dobCtrl.dispose();
    _faceDetector.close();
    super.dispose();
  }

  void _markDirty() => setState(() => _isDirty = true);

  // ─────────────────────────────────────────────────────────────────────
  // FACE ANALYSER (mirrors onboarding3.dart) — real camera capture + ML
  // Kit face detection, used to auto-fill Face Shape and Skin Tone below.
  // ─────────────────────────────────────────────────────────────────────

  void _initializeFaceDetector() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableClassification: true,
        enableContours: true,
      ),
    );
  }

  Future<void> _captureAndAnalyzeFacePhoto() async {
    if (_isAnalyzingFace) return;

    final status = await Permission.camera.request();
    if (status.isPermanentlyDenied) {
      widget.onToast('Camera permission denied. Please enable it in Settings.');
      await openAppSettings();
      return;
    }
    if (!status.isGranted) {
      widget.onToast('Camera permission is required for face scan.');
      return;
    }

    XFile? photo;
    try {
      photo = await _facePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
      );
    } catch (e) {
      debugPrint('Face capture error: $e');
      widget.onToast('Failed to capture face photo.');
      return;
    }
    if (photo == null) return;

    setState(() => _isAnalyzingFace = true);

    try {
      final imageFile = File(photo.path);
      final inputImage = InputImage.fromFile(imageFile);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        widget.onToast('No face detected. Please try a clear, front-facing photo.');
        setState(() => _isAnalyzingFace = false);
        return;
      }

      final imageBytes = await imageFile.readAsBytes();
      final decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) {
        widget.onToast('Failed to process image.');
        setState(() => _isAnalyzingFace = false);
        return;
      }

      final face = faces.first;

      // Extract facial features (mirrors onboarding3's _analyzeFaceAdvanced)
      final faceShape = _analyzeFaceShape(face);
      final skinToneData = _extractSkinTone(decodedImage, face);
      final skinToneLabel = skinToneData['label'] as String;
      final skinToneColor = skinToneData['color'] as Color;
      final skinToneIndex = _nearestSkinToneIndex(skinToneColor);
      final skinQuality = _calculateSkinQuality(decodedImage, face);
      final acneData = _detectAcne(decodedImage, face);
      final pigmentationData = _detectPigmentation(decodedImage, face);
      final eyeShapeData = _analyzeEyeShape(face);
      final lipColorData = _analyzeLipColor(decodedImage, face);
      final darkerCircles = _detectDarkCircles(decodedImage, face);

      final recommendations = _generateRecommendations(
        skinToneLabel,
        acneData['detected'] as bool,
        pigmentationData['detected'] as bool,
        eyeShapeData,
        darkerCircles,
        faceShape,
      );

      final analysisData = FaceAnalysisData(
        faceDetected: true,
        faceShape: faceShape,
        skinTone: skinToneLabel,
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
        _faceUploaded = true;
        _faceAnalysisData = analysisData;
        _draft = _draft.copyWith(
          faceShape: faceShape,
          skinTone: skinToneIndex,
          avatarPath: _draft.avatarPath ?? imageFile.path,
        );
        _isAnalyzingFace = false;
        _isDirty = true;
      });

      widget.onToast('Detected: $faceShape face shape');
    } catch (e) {
      debugPrint('Face analysis error: $e');
      widget.onToast('Failed to analyze face. Please try again.');
      setState(() => _isAnalyzingFace = false);
    }
  }

  // ── Face Shape Analysis ─────────────────────────────────────────
  // Uses the ML Kit face oval contour to compare forehead, cheekbone,
  // and jaw widths against overall face length for a heuristic
  // classification, matching the values in kFaceShapes.
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

  // ── Skin Tone Extraction (actual sampled color) ─────────────────
  // Samples the forehead and both cheeks and averages them for a
  // representative reading, returning the actual Color.
  Map<String, dynamic> _extractSkinTone(img.Image image, Face face) {
    const fallback = {'label': 'Medium', 'color': Color(0xFFC68863)};
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

      if (samples == 0) return fallback;

      final avgR = (rSum / samples).round().clamp(0, 255);
      final avgG = (gSum / samples).round().clamp(0, 255);
      final avgB = (bSum / samples).round().clamp(0, 255);
      final skinColor = Color.fromARGB(255, avgR, avgG, avgB);
      final brightness = (avgR + avgG + avgB) / 3;

      String label;
      if (brightness > 200) {
        label = 'Very Fair';
      } else if (brightness > 170) {
        label = 'Fair';
      } else if (brightness > 140) {
        label = 'Light Medium';
      } else if (brightness > 110) {
        label = 'Medium';
      } else if (brightness > 80) {
        label = 'Medium Deep';
      } else if (brightness > 60) {
        label = 'Deep';
      } else {
        label = 'Very Deep';
      }

      return {'label': label, 'color': skinColor};
    } catch (e) {
      return fallback;
    }
  }

  // Maps a sampled skin color to the closest swatch in kSkinTones so it
  // can populate ProfileState.skinTone (a 1-based index into that list).
  int _nearestSkinToneIndex(Color sampled) {
    int bestIndex = 0;
    double bestDistance = double.infinity;

    for (int i = 0; i < kSkinTones.length; i++) {
      final swatch = kSkinTones[i];
      final dr = sampled.red - swatch.red;
      final dg = sampled.green - swatch.green;
      final db = sampled.blue - swatch.blue;
      final distance = (dr * dr + dg * dg + db * db).toDouble();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return bestIndex + 1; // matches the 1-based convention used elsewhere
  }

  // ── Acne Detection ─────────────────────────────────────────────
  Map<String, dynamic> _detectAcne(img.Image image, Face face) {
    try {
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

          // Detect red spots (potential acne)
          if (r > g + 30 && r > b + 30) {
            irregularPixels++;
          }
        }
      }

      final acnePercentage = totalPixels > 0 ? (irregularPixels / totalPixels * 100).toInt() : 0;
      final detected = acnePercentage > 5;
      final severity = acnePercentage.clamp(0, 100);

      return {
        'detected': detected,
        'severity': severity,
      };
    } catch (e) {
      return {'detected': false, 'severity': 0};
    }
  }

  // ── Pigmentation Detection ─────────────────────────────────────
  Map<String, dynamic> _detectPigmentation(img.Image image, Face face) {
    try {
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
      final detected = intensity > 0.3;

      return {
        'detected': detected,
        'intensity': intensity,
      };
    } catch (e) {
      return {'detected': false, 'intensity': 0.0};
    }
  }

  // ── Eye Shape Analysis ────────────────────────────────────────
  String _analyzeEyeShape(Face face) {
    try {
      if (face.landmarks.isEmpty) return 'Standard';

      final leftEyeLandmark = face.landmarks.values.firstWhere(
            (lm) => lm?.type == FaceLandmarkType.leftEye,
        orElse: () => null,
      );

      if (leftEyeLandmark == null) return 'Standard';

      final position = leftEyeLandmark.position;
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

  // ── Eye Size Calculation ──────────────────────────────────────
  double _calculateEyeSize(Face face) {
    try {
      if (face.landmarks.isEmpty) return 0.5;

      final eyeWidth = face.boundingBox.width * 0.15;
      return (eyeWidth / (face.boundingBox.width * 0.3)).clamp(0.0, 1.0);
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
  double _calculateLipFullness(Face face) {
    try {
      final lipsHeight = face.boundingBox.height * 0.08;
      return (lipsHeight / (face.boundingBox.height * 0.15)).clamp(0.0, 1.0);
    } catch (e) {
      return 0.5;
    }
  }

  // ── Dark Circles Detection ────────────────────────────────────
  bool _detectDarkCircles(img.Image image, Face face) {
    try {
      final bbox = face.boundingBox;
      final underEyeY = (bbox.top + bbox.height * 0.5).toInt();
      final sampleX = (bbox.center.dx * image.width).toInt();

      if (sampleX < 0 || sampleX >= image.width || underEyeY < 0 || underEyeY >= image.height) {
        return false;
      }

      final pixel = image.getPixelSafe(sampleX, underEyeY);
      final brightness = (pixel.r.toInt() + pixel.g.toInt() + pixel.b.toInt()) / 3;

      return brightness < 100;
    } catch (e) {
      return false;
    }
  }

  // ── Skin Quality Calculation ──────────────────────────────────
  double _calculateSkinQuality(img.Image image, Face face) {
    try {
      final acneData = _detectAcne(image, face);
      final pigmentationData = _detectPigmentation(image, face);

      double quality = 100.0;
      quality -= (acneData['severity'] as int) * 0.5;
      quality -= ((pigmentationData['intensity'] as double) * 100) * 0.3;

      return quality.clamp(0.0, 100.0);
    } catch (e) {
      return 75.0;
    }
  }

  // ── Generate Recommendations ──────────────────────────────────
  List<String> _generateRecommendations(
      String skinTone,
      bool hasAcne,
      bool hasPigmentation,
      String eyeShape,
      bool darkCircles,
      String faceShape,
      ) {
    final recommendations = <String>[];

    if (hasAcne) {
      recommendations.add('Try acne-fighting products with salicylic acid');
    }

    if (hasPigmentation) {
      recommendations.add('Consider vitamin C serums for brightening');
    }

    if (darkCircles) {
      recommendations.add('Use eye creams with caffeine to reduce puffiness');
    }

    if (eyeShape == 'Hooded') {
      recommendations.add('Highlight inner corner for wider eye appearance');
    }

    switch (faceShape) {
      case 'Round':
        recommendations.add('Contour cheeks softly to add definition');
        break;
      case 'Square':
        recommendations.add('Soften angles with rounded blush placement');
        break;
      case 'Heart':
        recommendations.add('Balance a wider forehead with soft, side-swept styling');
        break;
      case 'Oblong':
        recommendations.add('Add visual width with horizontal blush placement');
        break;
      case 'Diamond':
        recommendations.add('Highlight cheekbones — your strongest feature');
        break;
      default:
        recommendations.add('Your balanced face shape suits most styles');
    }

    recommendations.add('Stay hydrated for healthy, glowing skin');

    if (recommendations.isEmpty) {
      recommendations.add('Your skin looks great! Maintain current routine');
    }

    return recommendations;
  }

  Widget _buildFaceShapeCard(
      Map<String, String> shape,
      bool isActive,
      ThemeColors colors,
      ) {
    return GestureDetector(
      onTap: () => setState(() {
        _draft = _draft.copyWith(faceShape: shape['name']!);
        _markDirty();
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? colors.accent1 : _cardBorder,
            width: isActive ? 2 : 1,
          ),
          color: isActive ? colors.accent1.withOpacity(0.1) : _panel,
        ),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(13),
                ),
                child: Image.asset(
                  shape['img']!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (_, _, _) =>
                      Container(
                        color: _card,
                        child: Center(
                          child: Icon(
                            Icons.face_outlined,
                            color: _textMuted,
                            size: 36,
                          ),
                        ),
                      ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                shape['name']!,
                style: TextStyle(
                  color: isActive ? colors.accent1 : _textMuted,
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyShapeCard(
      Map<String, String> shape,
      bool isActive,
      ThemeColors colors,
      ) {
    return GestureDetector(
      onTap: () => setState(() {
        _draft = _draft.copyWith(bodyShape: shape['name']!);
        _markDirty();
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? colors.accent1 : _cardBorder,
            width: isActive ? 2 : 1,
          ),
          color: isActive ? colors.accent1.withOpacity(0.1) : _panel,
        ),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(13),
                ),
                child: Image.asset(
                  shape['img']!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  // ✅ FIX: Changed from filled Icons.person to outline version
                  // and wrapped in Container with proper centering
                  errorBuilder: (_, _, _) =>
                      Container(
                        color: _card,
                        child: Center(
                          child: Icon(
                            Icons.person_outline,
                            color: _textMuted,
                            size: 36,
                          ),
                        ),
                      ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                shape['name']!,
                style: TextStyle(
                  color: isActive ? colors.accent1 : _textMuted,
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCountryPicker() {
    if (_countryDropdownOverlay != null) {
      _removeCountryDropdown();
      return;
    }
    final overlay = Overlay.of(context);
    _countryDropdownOverlay = OverlayEntry(
      builder: (_) => _ProfileCountryDropdown(
        link: _countryLayerLink,
        countries: _countries,
        selectedCode: _selectedCountryCode,
        selectedFlag: _selectedCountryFlag,
        cardBg: widget.bg2,
        cardBorder: _cardBorder,
        textPrimary: _textPrimary,
        textMuted: _textMuted,
        accentColor: c.accent1,
        onSelected: (country) {
          setState(() {
            _selectedCountryCode = country['code'] as String;
            _selectedCountryFlag = country['flag'] as String;
            _selectedCountryMaxDigits = country['digits'] as int;
            _phoneCtrl.clear();
          });
          _removeCountryDropdown();
          _markDirty();
        },
        onDismiss: _removeCountryDropdown,
      ),
    );
    overlay.insert(_countryDropdownOverlay!);
  }

  void _removeCountryDropdown() {
    _countryDropdownOverlay?.remove();
    _countryDropdownOverlay = null;
  }

  void _showDobPicker(
      String title,
      List<String> options,
      ValueChanged<String?> onChanged,
      ) {
    int tempIndex = 0;
    showModalBottomSheet(
      context: context,
      backgroundColor: widget.bg2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SizedBox(
        height: 280,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _cardBorder,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: TextStyle(color: _textMuted, fontSize: 13),
                  ),
                  GestureDetector(
                    onTap: () {
                      onChanged(options[tempIndex]);
                      Navigator.pop(context);
                    },
                    child: Text(
                      'Done',
                      style: TextStyle(
                        color: c.accent1,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoPicker(
                backgroundColor: Colors.transparent,
                itemExtent: 36,
                onSelectedItemChanged: (i) => tempIndex = i,
                children: options
                    .map(
                      (o) => Center(
                    child: Text(
                      o,
                      style: TextStyle(color: _textPrimary, fontSize: 15),
                    ),
                  ),
                )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDobDropdown(
      String hint,
      String? value,
      List<String> options,
      ValueChanged<String?> onChanged,
      ) {
    final isSelected = value != null;
    return GestureDetector(
      onTap: () => _showDobPicker(hint, options, onChanged),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
        decoration: BoxDecoration(
          color: isSelected ? _panel.withOpacity(0.8) : _panel,
          border: Border.all(
            color: isSelected ? c.accent1 : _cardBorder,
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: c.accent1.withOpacity(0.15),
              blurRadius: 12,
              spreadRadius: 3,
            ),
          ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                value ?? hint,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: isSelected ? _textPrimary : _textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery);
    if (img == null) return;

    // Launch crop UI — circular crop locked to 1:1 (v12.x API)
    final cropped = await ImageCropper().cropImage(
      sourcePath: img.path,
      compressQuality: 90,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Photo',
          toolbarColor: _draft.isDark
              ? const Color(0xFF0D0E14)
              : const Color(0xFFF4F4F8),
          toolbarWidgetColor: _draft.isDark
              ? const Color(0xFFF0F0F8)
              : const Color(0xFF18192A),
          activeControlsWidgetColor: const Color(0xFF6B91FF),
          backgroundColor: _draft.isDark
              ? const Color(0xFF0D0E14)
              : const Color(0xFFF4F4F8),
          cropStyle: CropStyle.circle,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
          aspectRatioPresets: [CropAspectRatioPreset.square],
        ),
        IOSUiSettings(
          title: 'Crop Photo',
          cropStyle: CropStyle.circle,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
          aspectRatioPresets: [CropAspectRatioPreset.square],
        ),
      ],
    );

    if (cropped != null) {
      setState(() {
        _draft = _draft.copyWith(avatarPath: cropped.path);
        _isDirty = true;
      });
      // Auto-save avatar immediately to ProfileController so home screen
      // reflects the new pic right away — user shouldn't have to tap Save
      // just for a photo change.
      widget.onSave(
        _draft.copyWith(
          name: _nameCtrl.text.trim().isEmpty
              ? 'New User'
              : _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          phone: _phoneCtrl.text.trim().isNotEmpty
              ? '$_selectedCountryCode ${_phoneCtrl.text.trim()}'
              : '',
          dob: (_dobDay != null && _dobMonth != null && _dobYear != null)
              ? '$_dobDay $_dobMonth $_dobYear'
              : _dobCtrl.text.trim(),
          avatarPath: cropped.path,
        ),
      );
      // Mark as clean so back button doesn't show discard warning for only a photo change
      setState(() => _isDirty = false);
      widget.onToast(_t.photoUpdated);
    }
  }

  void _handleBack() {
    if (_isDirty) {
      _showDiscardModal();
    } else {
      widget.onDiscard();
    }
  }

  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final name = _nameCtrl.text.trim().isEmpty
        ? 'New User'
        : _nameCtrl.text.trim();
    // Build phone string "CODE NUMBER" matching onboarding1 format
    final phoneNumber = _phoneCtrl.text.trim();
    final phone = phoneNumber.isNotEmpty
        ? '$_selectedCountryCode $phoneNumber'
        : '';
    // Build DOB string "DD MMMM YYYY" matching onboarding1 format
    final dob = (_dobDay != null && _dobMonth != null && _dobYear != null)
        ? '$_dobDay $_dobMonth $_dobYear'
        : _dobCtrl.text.trim();

    final updatedDraft = _draft.copyWith(
      name: name,
      email: _emailCtrl.text.trim(),
      phone: phone,
      dob: dob,
    );

    // ── STEP 1: Sync to Appwrite DB ─────────────────────────────────────────
    try {
      final appwrite = Provider.of<AppwriteService>(context, listen: false);
      await appwrite.updateCurrentUserProfileFields({
        'name': name,
        'email': updatedDraft.email,
        'phone': phone,
        'dob': dob,
        'gender': updatedDraft.gender,
        'skinTone': updatedDraft.skinTone,
        'faceShape': updatedDraft.faceShape,
        'bodyShape': updatedDraft.bodyShape,
        'stylePreferences': updatedDraft.styles.toList(),
        'shopPrefs': updatedDraft.shopPrefs.toList(),
      });
      // Also update the Appwrite Auth account name so account.get() stays fresh
      await appwrite.account.updateName(name: name);
    } catch (e) {
      debugPrint('AHVI_PROFILE_SAVE_APPWRITE_ERROR: $e');
      // Don't block the UI — fall through to update local state anyway
    }

    // ── STEP 2: Overwrite SharedPreferences cache ────────────────────────────
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userName', name);
      await prefs.setString('userEmail', updatedDraft.email);
      await prefs.setString('userPhone', phone);
      await prefs.setString('userDob', dob);
      await prefs.setString('userGender', updatedDraft.gender);
      await prefs.setInt('userSkinTone', updatedDraft.skinTone);
      await prefs.setString('userFaceShape', updatedDraft.faceShape);
      await prefs.setString('userBodyShape', updatedDraft.bodyShape);
      await prefs.setStringList('userStyles', updatedDraft.styles.toList());
      await prefs.setStringList('userShopPrefs', updatedDraft.shopPrefs.toList());
    } catch (e) {
      debugPrint('AHVI_PROFILE_SAVE_PREFS_ERROR: $e');
    }

    // ── STEP 3: Update Provider state → instant UI refresh ──────────────────
    if (mounted) setState(() => _saving = false);
    widget.onSave(updatedDraft);
  }

  void _showDiscardModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: widget.bg2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ConfirmSheet(
        icon: '⚠️',
        isDanger: true,
        title: _t.discardChanges,
        body: _t.discardChangesBody,
        confirmLabel: _t.discard,
        cancelLabel: _t.keepEditing,
        bg2: widget.bg2,
        cardBorder: _cardBorder,
        textPrimary: _textPrimary,
        textMuted: _textMuted,
        panel: _panel,
        danger: const Color(0xFFF06080),
        accentColor: c.accent1,
        onConfirm: () {
          Navigator.pop(context);
          widget.onDiscard();
        },
        onCancel: () => Navigator.pop(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // Top bar
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
            child: Row(
              children: [
                _HeaderBtn(
                  icon: '‹',
                  bg: _panel,
                  border: _cardBorder,
                  textMuted: _textMuted,
                  onTap: _handleBack,
                ),
                const Spacer(),
                Text(
                  _t.editProfile,
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 36),
              ],
            ),
          ),

          // Avatar
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AvatarWidget(
                state: _draft,
                colors: c,
                bg: _bg,
                bg2: widget.bg2,
                size: 92,
                onPickImage: _pickAvatar,
              ),
            ),
          ),

          // Tabs
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _cardBorder),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                gradient: LinearGradient(
                  colors: [c.accent1, c.accent2],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: c.accent1.withOpacity(0.38),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: _textMuted,
              labelStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
              tabs: [
                Tab(text: _t.basics, height: 42),
                Tab(text: _t.style, height: 42),
                Tab(text: _t.tryOn, height: 42),
              ],
              dividerColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
            ),
          ),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // BASICS TAB
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Full Name ──
                      _FieldLabel(text: _t.fullName, textMuted: _textMuted),
                      _FieldInput(
                        ctrl: _nameCtrl,
                        hint: _t.yourName,
                        panel: _panel,
                        cardBorder: _cardBorder,
                        textPrimary: _textPrimary,
                        textMuted: _textMuted,
                        accentColor: c.accent1,
                        onChanged: (_) => _markDirty(),
                      ),

                      // ── Email ──
                      _FieldLabel(text: _t.email, textMuted: _textMuted),
                      _FieldInput(
                        ctrl: _emailCtrl,
                        hint: 'email@example.com',
                        keyboardType: TextInputType.emailAddress,
                        panel: _panel,
                        cardBorder: _cardBorder,
                        textPrimary: _textPrimary,
                        textMuted: _textMuted,
                        accentColor: c.accent1,
                        onChanged: (_) => _markDirty(),
                      ),

                      // ── Phone — country code picker (onboarding1 style) ──
                      _FieldLabel(text: _t.phone, textMuted: _textMuted),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Country code button
                          CompositedTransformTarget(
                            link: _countryLayerLink,
                            child: GestureDetector(
                              onTap: _showCountryPicker,
                              child: Container(
                                height: 50,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: _panel,
                                  border: Border.all(
                                    color: _cardBorder,
                                    width: 1.5,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _selectedCountryFlag,
                                      style: const TextStyle(fontSize: 20),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _selectedCountryCode,
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w500,
                                        color: _textPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: _textMuted,
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Number input
                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child: TextField(
                                controller: _phoneCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(
                                    _selectedCountryMaxDigits,
                                  ),
                                ],
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                  color: _textPrimary,
                                ),
                                onChanged: (_) => _markDirty(),
                                decoration: InputDecoration(
                                  hintText: '00000 00000',
                                  hintStyle: TextStyle(
                                    color: _textMuted,
                                    fontSize: 15,
                                  ),
                                  filled: true,
                                  fillColor: _panel,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                      color: _cardBorder,
                                      width: 1.5,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                      color: c.accent1,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // ── Date of Birth — 3 dropdowns with CupertinoPicker (onboarding1 style) ──
                      _FieldLabel(text: _t.dateOfBirth, textMuted: _textMuted),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: _buildDobDropdown(
                              'Day',
                              _dobDay,
                              List.generate(31, (i) => '${i + 1}'),
                                  (val) => setState(() {
                                _dobDay = val;
                                _markDirty();
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildDobDropdown(
                              'Month',
                              _dobMonth,
                              const [
                                'January',
                                'February',
                                'March',
                                'April',
                                'May',
                                'June',
                                'July',
                                'August',
                                'September',
                                'October',
                                'November',
                                'December',
                              ],
                                  (val) => setState(() {
                                _dobMonth = val;
                                _markDirty();
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildDobDropdown(
                              'Year',
                              _dobYear,
                              List.generate(
                                100,
                                    (i) => '${DateTime.now().year - 13 - i}',
                              ),
                                  (val) => setState(() {
                                _dobYear = val;
                                _markDirty();
                              }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // ── Gender (onboarding1-style pill selector) ──
                      // Was previously missing here — ProfileState already
                      // stored `gender`, but there was no UI to view/edit it
                      // after onboarding. Options match onboarding1 exactly.
                      _FieldLabel(text: _t.gender, textMuted: _textMuted),
                      const SizedBox(height: 6),
                      Row(
                        children: List.generate(3, (i) {
                          const genders = ['Male', 'Female', 'Others'];
                          final label = genders[i];
                          final isActive = _draft.gender == label;
                          return Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: i < genders.length - 1 ? 8 : 0,
                              ),
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _draft = _draft.copyWith(gender: label);
                                  _markDirty();
                                }),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? c.accent1.withOpacity(0.13)
                                        : _panel,
                                    border: Border.all(
                                      color: isActive
                                          ? c.accent1
                                          : _cardBorder,
                                      width: isActive ? 1.5 : 1,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    label,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: isActive
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: isActive
                                          ? _textPrimary
                                          : _textMuted,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 14),

                      // ── Skin Tone ──
                      _FieldLabel(text: _t.skinTone, textMuted: _textMuted),
                      const SizedBox(height: 6),
                      Row(
                        children: List.generate(kSkinTones.length, (i) {
                          final active = _draft.skinTone == i + 1;
                          return GestureDetector(
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(skinTone: i + 1);
                              _markDirty();
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.only(right: 10),
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: kSkinTones[i],
                                shape: BoxShape.circle,
                                border: active
                                    ? Border.all(color: c.accent1, width: 3)
                                    : Border.all(
                                  color: Colors.transparent,
                                  width: 3,
                                ),
                              ),
                              transform: active
                                  ? (Matrix4.identity()..scale(1.15))
                                  : Matrix4.identity(),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 14),

                      // ── Shop Preferences — Women / Men / Both (onboarding1 exact logic) ──
                      _FieldLabel(
                        text: _t.shopPreferences,
                        textMuted: _textMuted,
                      ),
                      const SizedBox(height: 6),
                          () {
                        final bool womenSelected =
                            _draft.shopPrefs.length == 1 &&
                                _draft.shopPrefs.contains('Women');
                        final bool menSelected =
                            _draft.shopPrefs.length == 1 &&
                                _draft.shopPrefs.contains('Men');
                        final bool bothSelected =
                            _draft.shopPrefs.contains('Women') &&
                                _draft.shopPrefs.contains('Men');
                        bool isCardActive(String label) {
                          if (label == 'Women') return womenSelected;
                          if (label == 'Men') return menSelected;
                          return bothSelected;
                        }

                        const shopCards = [
                          {'label': 'Women', 'img': 'assets/shop/women.jpg'},
                          {'label': 'Men', 'img': 'assets/shop/men.jpg'},
                          {'label': 'Both', 'img': 'assets/shop/both.jpeg'},
                        ];
                        return Row(
                          children: List.generate(shopCards.length, (index) {
                            final pref = shopCards[index];
                            final label = pref['label']!;
                            final isActive = isCardActive(label);
                            return Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left: index == 0 ? 0 : 5,
                                  right: index == shopCards.length - 1 ? 0 : 5,
                                ),
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    if (label == 'Both') {
                                      _draft = _draft.copyWith(
                                        shopPrefs: {'Women', 'Men'},
                                      );
                                      _bodyGender = 'both';
                                      _draft = _draft.copyWith(
                                        bodyShape: kBodyShapes['women']!
                                            .first['name']!,
                                      );
                                    } else if (label == 'Women') {
                                      _draft = _draft.copyWith(
                                        shopPrefs: {'Women'},
                                      );
                                      _bodyGender = 'women';
                                      _draft = _draft.copyWith(
                                        bodyShape: kBodyShapes['women']!
                                            .first['name']!,
                                      );
                                    } else {
                                      _draft = _draft.copyWith(
                                        shopPrefs: {'Men'},
                                      );
                                      _bodyGender = 'men';
                                      _draft = _draft.copyWith(
                                        bodyShape:
                                        kBodyShapes['men']!.first['name']!,
                                      );
                                    }
                                    _markDirty();
                                  }),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    height: 160,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isActive
                                            ? c.accent1
                                            : _cardBorder,
                                        width: isActive ? 1.5 : 1,
                                      ),
                                      color: isActive
                                          ? c.accent1.withOpacity(0.13)
                                          : _panel,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(11),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Image.asset(
                                            pref['img']!,
                                            fit: BoxFit.cover,
                                            alignment: Alignment.topCenter,
                                            errorBuilder: (_, _, _) =>
                                            const SizedBox(),
                                          ),
                                          Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  Colors.transparent,
                                                  Colors.black.withOpacity(
                                                    0.65,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Align(
                                            alignment: Alignment.bottomLeft,
                                            child: Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: Row(
                                                children: [
                                                  if (isActive)
                                                    Padding(
                                                      padding:
                                                      const EdgeInsets.only(
                                                        right: 4,
                                                      ),
                                                      child: Icon(
                                                        Icons.check_circle,
                                                        color: c.accent1,
                                                        size: 13,
                                                      ),
                                                    ),
                                                  Text(
                                                    label,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                      fontWeight:
                                                      FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        );
                      }(),

                      // ── Body Shape — onboarding1 exact: both → Women+Men sections separately ──
                      _ProfileBodyShapeReveal(
                        visible:
                        _draft.shopPrefs.contains('Women') ||
                            _draft.shopPrefs.contains('Men'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 14),
                            _FieldLabel(
                              text: _t.bodyShape,
                              textMuted: _textMuted,
                            ),
                            if (_bodyGender == 'both') ...[
                              // Women section
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'Women',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: c.accent1,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              GridView.count(
                                crossAxisCount: 3,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 0.65,
                                children: kBodyShapes['women']!.map((shape) {
                                  final isActive =
                                      _draft.bodyShape == shape['name'];
                                  return _buildBodyShapeCard(
                                    shape,
                                    isActive,
                                    c,
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 16),
                              // Men section
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'Men',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: c.accent2,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              GridView.count(
                                crossAxisCount: 3,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 0.65,
                                children: kBodyShapes['men']!.map((shape) {
                                  final isActive =
                                      _draft.bodyShape == shape['name'];
                                  return _buildBodyShapeCard(
                                    shape,
                                    isActive,
                                    c,
                                  );
                                }).toList(),
                              ),
                            ] else
                              GridView.count(
                                crossAxisCount: 3,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 0.65,
                                children:
                                kBodyShapes[_bodyGender == 'both'
                                    ? 'women'
                                    : _bodyGender]!
                                    .map((shape) {
                                  final isActive =
                                      _draft.bodyShape == shape['name'];
                                  return _buildBodyShapeCard(
                                    shape,
                                    isActive,
                                    c,
                                  );
                                })
                                    .toList(),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),

                // STYLE TAB
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t.chooseStyles,
                        style: TextStyle(color: _textMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _t.tapToSelect,
                        style: TextStyle(
                          color: _textMuted.withOpacity(0.7),
                          fontSize: 10.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 3 / 4,
                        children: kStyleCards.map((sc) {
                          final active = _draft.styles.contains(sc['label']);
                          return _StyleImgCard(
                            label: sc['label']!,
                            imgUrl: sc['img']!,
                            active: active,
                            colors: c,
                            cardBorder: _cardBorder,
                            panel: _panel,
                            onTap: () => setState(() {
                              final newStyles = Set<String>.from(_draft.styles);
                              if (active) {
                                newStyles.remove(sc['label']);
                              } else {
                                newStyles.add(sc['label']!);
                              }
                              _draft = _draft.copyWith(styles: newStyles);
                              _markDirty();
                            }),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),

                // TRY ON TAB
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      // Intro card
                      Container(
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _cardBorder),
                          boxShadow: [
                            BoxShadow(
                              color: c.accent1.withOpacity(0.10),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // shimmer top strip
                            Container(
                              height: 1.5,
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(20),
                                ),
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    c.accent1.withOpacity(0.5),
                                    c.accent2.withOpacity(0.3),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                18,
                                16,
                                18,
                                16,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          c.accent1.withOpacity(0.18),
                                          c.accent2.withOpacity(0.12),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(15),
                                      border: Border.all(
                                        color: c.accent1.withOpacity(0.30),
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.person_outline,
                                      color: c.accent1,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _t.personalizedFitPreview,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: _textPrimary,
                                            letterSpacing: -0.15,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          _t.personalizedFitBody,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: _textMuted,
                                            fontWeight: FontWeight.w400,
                                            height: 1.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Toggle
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _cardBorder),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _t.enableTryOn,
                                    style: TextStyle(
                                      color: _textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Turn on to upload photos for a personalised fit preview.',
                                    style: TextStyle(
                                      color: _textMuted,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () => setState(() {
                                _tryOnEnabled = !_tryOnEnabled;
                                _markDirty();
                              }),
                              child: _ToggleSwitch(
                                value: _tryOnEnabled,
                                colors: c,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Optional badge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _panel,
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(color: _cardBorder),
                            ),
                            child: Text(
                              'Both uploads are optional',
                              style: TextStyle(
                                fontSize: 11,
                                color: _textMuted,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Face upload row
                      _TryOnUploadRow(
                        title: _t.uploadFacePhoto,
                        subtitle:
                        'Used only to enhance facial fit and styling.',
                        uploaded: _faceUploaded,
                        isAnalyzing: _isAnalyzingFace,
                        resultLabel: _faceUploaded
                            ? '${_draft.faceShape} face detected'
                            : null,
                        isFace: true,
                        colors: c,
                        card: _card,
                        cardBorder: _cardBorder,
                        panel: _panel,
                        textPrimary: _textPrimary,
                        textMuted: _textMuted,
                        onTap: _captureAndAnalyzeFacePhoto,
                      ),
                      if (_faceAnalysisData != null) ...[
                        const SizedBox(height: 12),
                        _FaceAnalysisPreview(
                          data: _faceAnalysisData!,
                          colors: c,
                          card: _card,
                          cardBorder: _cardBorder,
                          textPrimary: _textPrimary,
                          textMuted: _textMuted,
                          isDark: _draft.isDark,
                        ),
                      ],
                      const SizedBox(height: 12),

                      // Body upload row
                      _TryOnUploadRow(
                        title: _t.uploadBodyPhoto,
                        subtitle: 'Improves outfit proportion accuracy.',
                        uploaded: _bodyUploaded,
                        isFace: false,
                        colors: c,
                        card: _card,
                        cardBorder: _cardBorder,
                        panel: _panel,
                        textPrimary: _textPrimary,
                        textMuted: _textMuted,
                        onTap: () => setState(() {
                          _bodyUploaded = !_bodyUploaded;
                          _markDirty();
                        }),
                      ),
                      const SizedBox(height: 16),

                      // Privacy block
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: c.accent3.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: c.accent3.withOpacity(0.20),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: c.accent3.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.shield_outlined,
                                color: c.accent3,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 12),
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
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Photos are used solely for fit modeling and are deleted on request. AHVI does not sell or share personal data.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _textMuted,
                                      fontWeight: FontWeight.w300,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Continue / Save Button
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              final tab = _tabController.index;
              final isLastTab = tab == 2;
              final label = tab == 0
                  ? '${_t.style}  →'
                  : tab == 1
                  ? '${_t.tryOn}  →'
                  : _t.profileUpdated.replaceAll('✓ ', '');
              final canTap = isLastTab ? (_isDirty && !_saving) : true;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: GestureDetector(
                  onTap: canTap
                      ? () {
                    if (isLastTab) {
                      _save();
                    } else {
                      _tabController.animateTo(tab + 1);
                    }
                  }
                      : null,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: canTap ? 1.0 : 0.4,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [c.accent1, c.accent2],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: c.accent1.withOpacity(0.28),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: (_saving && isLastTab)
                            ? SizedBox(
                          key: const ValueKey('saving'),
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: _textPrimary,
                          ),
                        )
                            : Text(
                          label,
                          key: ValueKey(tab),
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _AvatarWidget extends StatelessWidget {
  final ProfileState state;
  final ThemeColors colors;
  final Color bg, bg2;
  final double size;
  final VoidCallback? onPickImage;

  const _AvatarWidget({
    required this.state,
    required this.colors,
    required this.bg,
    required this.bg2,
    required this.size,
    required this.onPickImage,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 16,
      height: size + 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glow ring
          Container(
            width: size + 36,
            height: size + 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  colors.accent1.withOpacity(0.22),
                  colors.accent2.withOpacity(0.09),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Gradient ring
          Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [colors.accent2, colors.accent1, colors.accent3],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.accent1.withOpacity(0.3),
                  blurRadius: 28,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [bg2, const Color(0xFF1A1C26)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(0.10),
                  width: 2.5,
                ),
              ),
              clipBehavior: Clip.hardEdge,
              child: state.avatarPath != null
                  ? Image.file(File(state.avatarPath!), fit: BoxFit.cover)
                  : Center(
                child: Text(
                  (state.name.isEmpty ? 'C' : state.name[0])
                      .toUpperCase(),
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w300,
                    color: colors.accent1,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
          ),
          // Camera badge
          if (onPickImage != null)
            Positioned(
              bottom: 0,
              right: 0,
              child: GestureDetector(
                onTap: onPickImage,
                child: Container(
                  width: 27,
                  height: 27,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.accent1,
                    border: Border.all(color: bg, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: colors.accent1.withOpacity(0.4),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Text('📷', style: TextStyle(fontSize: 10)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeaderBtn extends StatelessWidget {
  final String icon;
  final Color bg, border, textMuted;
  final VoidCallback? onTap;

  const _HeaderBtn({
    required this.icon,
    required this.bg,
    required this.border,
    required this.textMuted,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.28), blurRadius: 8),
          ],
        ),
        alignment: Alignment.center,
        child: Text(icon, style: TextStyle(fontSize: 18, color: textMuted)),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color textMuted;
  const _SectionLabel({required this.label, required this.textMuted});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: textMuted,
          letterSpacing: 1.3,
        ),
      ),
    );
  }
}

class _SectionGroup extends StatelessWidget {
  final List<Widget> children;
  const _SectionGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: children
            .map(
              (c) =>
              Padding(padding: const EdgeInsets.only(bottom: 3), child: c),
        )
            .toList(),
      ),
    );
  }
}

class _ListItem extends StatelessWidget {
  final String icon;
  final String label;
  final String? meta;
  final bool iconAccent;
  final bool iconDanger;
  final bool labelDanger;
  final ThemeColors colors;
  final Color card, cardBorder, textPrimary, textMuted;
  final Color? danger;
  final VoidCallback? onTap;

  const _ListItem({
    required this.icon,
    required this.label,
    this.meta,
    this.iconAccent = false,
    this.iconDanger = false,
    this.labelDanger = false,
    required this.colors,
    required this.card,
    required this.cardBorder,
    required this.textPrimary,
    required this.textMuted,
    this.danger,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.transparent),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconDanger
                    ? colors.accent1.withOpacity(0.13)
                    : iconAccent
                    ? colors.accent1.withOpacity(0.12)
                    : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: iconDanger
                      ? colors.accent1.withOpacity(0.38)
                      : iconAccent
                      ? colors.accent1.withOpacity(0.28)
                      : cardBorder,
                ),
              ),
              alignment: Alignment.center,
              child: Text(icon, style: const TextStyle(fontSize: 15)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: labelDanger ? colors.accent1 : textMuted,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.1,
                ),
              ),
            ),
            if (meta != null) ...[
              Text(
                meta!,
                style: TextStyle(
                  color: textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Text('›', style: TextStyle(color: textMuted, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _ToggleSwitch extends StatelessWidget {
  final bool value;
  final ThemeColors colors;
  const _ToggleSwitch({required this.value, required this.colors});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 44,
      height: 25,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: value
            ? LinearGradient(colors: [colors.accent1, colors.accent2])
            : null,
        color: value ? null : const Color(0xFF22253A),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.elasticOut,
            left: value ? 22 : 3,
            top: 3,
            child: Container(
              width: 19,
              height: 19,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  final ProfileState state;
  final ThemeColors colors;
  final Color panel, textPrimary, textMuted;
  final ValueChanged<AppTheme> onSelect;

  const _ThemeRow({
    required this.state,
    required this.colors,
    required this.panel,
    required this.textPrimary,
    required this.textMuted,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final themes = [
      (
      AppTheme.coolBlue,
      'Cool Blue',
      [const Color(0xFF6B91FF), const Color(0xFF04D7C8)],
      ),
      (
      AppTheme.sunsetPop,
      'Sunset Pop',
      [const Color(0xFFFF9E66), const Color(0xFFFF8EC7)],
      ),
      (
      AppTheme.futureCandy,
      'Future Candy',
      [const Color(0xFFFF8EC7), const Color(0xFF04D7C8)],
      ),
    ];

    return Row(
      children: themes.map((t) {
        final active = state.theme == t.$1;
        return Expanded(
          child: GestureDetector(
            onTap: () => onSelect(t.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: active ? panel : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                boxShadow: active
                    ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.20),
                    blurRadius: 8,
                  ),
                ]
                    : [],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: t.$3,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.22),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      t.$2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? textPrimary : textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final Color textMuted;
  const _FieldLabel({required this.text, required this.textMuted});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: textMuted,
          letterSpacing: 1.3,
        ),
      ),
    );
  }
}

class _FieldInput extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final TextInputType? keyboardType;
  final Color panel, cardBorder, textPrimary, textMuted, accentColor;
  final ValueChanged<String>? onChanged;

  const _FieldInput({
    required this.ctrl,
    required this.hint,
    this.keyboardType,
    required this.panel,
    required this.cardBorder,
    required this.textPrimary,
    required this.textMuted,
    required this.accentColor,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: TextStyle(
          color: textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w300,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: textMuted, fontWeight: FontWeight.w300),
          filled: true,
          fillColor: panel,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 13,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: BorderSide(color: cardBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: BorderSide(color: cardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: BorderSide(color: accentColor.withOpacity(0.28)),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final Color panel,
      cardBorder,
      textMuted,
      accentDim,
      accentBorder,
      accentColor;

  const _Chip({
    required this.label,
    required this.active,
    required this.panel,
    required this.cardBorder,
    required this.textMuted,
    required this.accentDim,
    required this.accentBorder,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: active ? accentDim : panel,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: active ? accentBorder : cardBorder),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? accentColor : textMuted,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _PrefCard extends StatelessWidget {
  final String label, imgUrl;
  final bool active;
  final ThemeColors colors;
  final Color cardBorder, panel;
  final VoidCallback onTap;

  const _PrefCard({
    required this.label,
    required this.imgUrl,
    required this.active,
    required this.colors,
    required this.cardBorder,
    required this.panel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? colors.accent1 : cardBorder,
            width: active ? 2 : 2,
          ),
          boxShadow: active
              ? [
            BoxShadow(
              color: colors.accent1.withOpacity(0.28),
              blurRadius: 8,
            ),
          ]
              : [],
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withOpacity(active ? 0.08 : 0.20),
                BlendMode.darken,
              ),
              child: Image.asset(
                imgUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: panel,
                  child: const Icon(Icons.image, color: Colors.white30),
                ),
              ),
            ),
            if (active)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [colors.accent1, colors.accent2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '✓',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.52),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withOpacity(0.15)),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StyleImgCard extends StatelessWidget {
  final String label, imgUrl;
  final bool active;
  final ThemeColors colors;
  final Color cardBorder, panel;
  final VoidCallback onTap;

  const _StyleImgCard({
    required this.label,
    required this.imgUrl,
    required this.active,
    required this.colors,
    required this.cardBorder,
    required this.panel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? colors.accent1 : cardBorder,
            width: 2,
          ),
          boxShadow: active
              ? [
            BoxShadow(
              color: colors.accent1.withOpacity(0.30),
              blurRadius: 8,
            ),
          ]
              : [],
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withOpacity(active ? 0.08 : 0.22),
                BlendMode.darken,
              ),
              child: Image.asset(
                imgUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: panel,
                  child: const Icon(Icons.image, color: Colors.white30),
                ),
              ),
            ),
            if (active)
              Positioned(
                top: 9,
                right: 9,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [colors.accent1, colors.accent2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '✓',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TRY ON UPLOAD ROW
// ─────────────────────────────────────────────────────────────────────────────

class _TryOnUploadRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool uploaded;
  final bool isFace;
  final bool isAnalyzing;
  final String? resultLabel;
  final ThemeColors colors;
  final Color card, cardBorder, panel, textPrimary, textMuted;
  final VoidCallback onTap;

  const _TryOnUploadRow({
    required this.title,
    required this.subtitle,
    required this.uploaded,
    required this.isFace,
    this.isAnalyzing = false,
    this.resultLabel,
    required this.colors,
    required this.card,
    required this.cardBorder,
    required this.panel,
    required this.textPrimary,
    required this.textMuted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = uploaded
        ? colors.accent1.withOpacity(0.40)
        : cardBorder;
    final bgColor = uploaded ? colors.accent1.withOpacity(0.07) : card;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: uploaded
              ? [
            BoxShadow(
              color: colors.accent1.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ]
              : [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: uploaded ? colors.accent1.withOpacity(0.15) : panel,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: uploaded
                      ? colors.accent1.withOpacity(0.35)
                      : cardBorder,
                ),
              ),
              child: isAnalyzing
                  ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.accent1,
                ),
              )
                  : Icon(
                isFace
                    ? Icons.person_outline
                    : Icons.accessibility_new_outlined,
                color: uploaded ? colors.accent1 : textMuted,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (isAnalyzing)
                    Text(
                      'Analyzing…',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.accent1,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else if (!uploaded)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: textMuted,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                      ),
                    ),
                  if (uploaded && !isAnalyzing)
                    Row(
                      children: [
                        Icon(Icons.check, color: colors.accent2, size: 12),
                        const SizedBox(width: 5),
                        Text(
                          resultLabel ?? 'Photo added · encrypted',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.accent2,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Action indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: uploaded ? colors.accent1.withOpacity(0.18) : panel,
                shape: BoxShape.circle,
                border: Border.all(
                  color: uploaded
                      ? colors.accent1.withOpacity(0.35)
                      : cardBorder,
                ),
              ),
              child: Icon(
                uploaded ? Icons.check : Icons.chevron_right,
                color: uploaded ? colors.accent1 : textMuted,
                size: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FACE ANALYSIS PREVIEW  (mirrors onboarding3.dart's _FaceAnalysisPreview)
// ─────────────────────────────────────────────────────────────────────────────

class _FaceAnalysisPreview extends StatelessWidget {
  final FaceAnalysisData data;
  final ThemeColors colors;
  final Color card, cardBorder, textPrimary, textMuted;
  final bool isDark;

  const _FaceAnalysisPreview({
    required this.data,
    required this.colors,
    required this.card,
    required this.cardBorder,
    required this.textPrimary,
    required this.textMuted,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final danger = isDark ? const Color(0xFFFF6B6E) : const Color(0xFFE5484D);
    final warning = isDark ? const Color(0xFFFFC94D) : const Color(0xFFF5A524);
    final statusPurple =
    isDark ? const Color(0xFFA78BFA) : const Color(0xFF8B5CF6);
    final statusPink =
    isDark ? const Color(0xFFF472B6) : const Color(0xFFEC4899);
    final recommendationBg =
    isDark ? const Color(0xFF3A2E12) : const Color(0xFFFFF8E8);
    final recommendationBorder =
    isDark ? const Color(0xFF5C4720) : const Color(0xFFFFE5B4);
    final recommendationTitle =
    isDark ? const Color(0xFFFFC66D) : const Color(0xFFD97706);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '✨ Face Analysis Results',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 16),

          // Skin Analysis Section
          _AnalysisSection(
            title: '🎨 Skin Profile',
            textPrimary: textPrimary,
            textMuted: textMuted,
            cardBorder: cardBorder,
            items: [
              _AnalysisItem(
                label: 'Skin Tone',
                value: data.skinTone,
                icon: '🌿',
                color: colors.accent3,
                swatchColor: data.skinToneColor,
              ),
              _AnalysisItem(
                label: 'Skin Quality',
                value: '${data.skinQuality.toStringAsFixed(0)}%',
                icon: '✨',
                color: colors.accent1,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Acne & Pigmentation Section
          _AnalysisSection(
            title: '🔍 Skin Conditions',
            textPrimary: textPrimary,
            textMuted: textMuted,
            cardBorder: cardBorder,
            items: [
              _AnalysisItem(
                label: 'Acne Status',
                value: data.acneDetected
                    ? 'Detected (${data.acneSeverity}%)'
                    : 'Clear',
                icon: data.acneDetected ? '⚠️' : '✅',
                color: data.acneDetected ? danger : colors.accent3,
              ),
              _AnalysisItem(
                label: 'Pigmentation',
                value: data.pigmentationDetected ? 'Present' : 'Even',
                icon: data.pigmentationDetected ? '⚠️' : '✅',
                color: data.pigmentationDetected ? warning : colors.accent3,
              ),
              if (data.darkerCircles)
                _AnalysisItem(
                  label: 'Dark Circles',
                  value: 'Detected',
                  icon: '👁️',
                  color: statusPurple,
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Eye & Lip Section
          _AnalysisSection(
            title: '👁️ Facial Features',
            textPrimary: textPrimary,
            textMuted: textMuted,
            cardBorder: cardBorder,
            items: [
              _AnalysisItem(
                label: 'Face Shape',
                value: data.faceShape,
                icon: '🧑',
                color: colors.accent1,
              ),
              _AnalysisItem(
                label: 'Eye Shape',
                value: data.eyeShape,
                icon: '👁️',
                color: colors.accent2,
              ),
              _AnalysisItem(
                label: 'Eye Size',
                value: _getSizeLabel(data.eyeSize),
                icon: '💫',
                color: colors.accent2,
              ),
              _AnalysisItem(
                label: 'Lip Color',
                value: data.lipColor,
                icon: '💋',
                color: statusPink,
              ),
              _AnalysisItem(
                label: 'Lip Fullness',
                value: _getSizeLabel(data.lipFullness),
                icon: '✨',
                color: statusPink,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Recommendations Section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: recommendationBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: recommendationBorder, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '💡 Personalized Recommendations',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: recommendationTitle,
                  ),
                ),
                const SizedBox(height: 8),
                ...data.recommendations.map(
                      (rec) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ', style: TextStyle(color: textMuted)),
                        Expanded(
                          child: Text(
                            rec,
                            style: TextStyle(
                              fontSize: 12,
                              color: textMuted,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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

class _AnalysisSection extends StatelessWidget {
  final String title;
  final List<_AnalysisItem> items;
  final Color textPrimary, textMuted, cardBorder;

  const _AnalysisSection({
    required this.title,
    required this.items,
    required this.textPrimary,
    required this.textMuted,
    required this.cardBorder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: textMuted,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        ...items.map(
              (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(item.icon, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: textPrimary,
                          fontWeight: FontWeight.w500,
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
                            border: Border.all(color: cardBorder, width: 1),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
          ),
        ),
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

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM SHEETS
// ─────────────────────────────────────────────────────────────────────────────

// ── Animated reveal widget for Body Shape section in Profile edit ──
class _ProfileBodyShapeReveal extends StatefulWidget {
  final bool visible;
  final Widget child;

  const _ProfileBodyShapeReveal({required this.visible, required this.child});

  @override
  State<_ProfileBodyShapeReveal> createState() =>
      _ProfileBodyShapeRevealState();
}

class _ProfileBodyShapeRevealState extends State<_ProfileBodyShapeReveal>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _scale;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );

    // Fade: eases in smoothly
    _fade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );

    // Slide: comes from slightly below (positive y = down)
    _slide = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    // Subtle scale: grows from 0.95 → 1.0
    _scale = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    if (widget.visible) _ctrl.value = 1.0;
  }

  @override
  void didUpdateWidget(_ProfileBodyShapeReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _ctrl.forward(from: 0.0);
    } else if (!widget.visible && oldWidget.visible) {
      _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return AnimatedSize(
          duration: const Duration(milliseconds: 480),
          curve: Curves.easeInOutCubic,
          child: _ctrl.isDismissed
              ? const SizedBox.shrink()
              : FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: ScaleTransition(
                scale: _scale,
                alignment: Alignment.topCenter,
                child: widget.child,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LanguageSheet extends StatelessWidget {
  final String current;
  final Color bg2, cardBorder, textPrimary, textMuted, accentColor;
  final String selectLanguageLabel;
  final String cancelLabel;
  final ValueChanged<String> onSelect;

  const _LanguageSheet({
    required this.current,
    required this.bg2,
    required this.cardBorder,
    required this.textPrimary,
    required this.textMuted,
    required this.accentColor,
    required this.selectLanguageLabel,
    required this.cancelLabel,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 13, bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: accentColor.withOpacity(0.28)),
            ),
            alignment: Alignment.center,
            child: const Text('🌐', style: TextStyle(fontSize: 24)),
          ),
          const SizedBox(height: 14),
          Text(
            selectLanguageLabel,
            style: TextStyle(
              color: textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...kLanguages.map(
                (l) => GestureDetector(
              onTap: () => onSelect(l),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: cardBorder)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      child: Text(
                        l == current ? '✓' : '',
                        style: TextStyle(color: accentColor, fontSize: 15),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      l,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cardBorder),
              ),
              alignment: Alignment.center,
              child: Text(
                cancelLabel,
                style: TextStyle(color: textMuted, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmSheet extends StatelessWidget {
  final String icon, title, body, confirmLabel, cancelLabel;
  final bool isDanger;
  final Color bg2,
      cardBorder,
      textPrimary,
      textMuted,
      panel,
      danger,
      accentColor;
  final VoidCallback onConfirm, onCancel;

  const _ConfirmSheet({
    required this.icon,
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.isDanger,
    required this.bg2,
    required this.cardBorder,
    required this.textPrimary,
    required this.textMuted,
    required this.panel,
    required this.danger,
    required this.accentColor,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 13, bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: accentColor.withOpacity(0.28)),
            ),
            alignment: Alignment.center,
            child: Text(icon, style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              color: textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(color: textMuted, fontSize: 13.5, height: 1.5),
          ),
          const SizedBox(height: 22),
          GestureDetector(
            onTap: onConfirm,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accentColor, accentColor.withOpacity(0.8)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withOpacity(0.28),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                confirmLabel,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onCancel,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cardBorder),
              ),
              alignment: Alignment.center,
              child: Text(
                cancelLabel,
                style: TextStyle(color: textMuted, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COUNTRY DROPDOWN OVERLAY  (used by profile edit Basics tab phone field)
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileCountryDropdown extends StatefulWidget {
  final LayerLink link;
  final List<Map<String, dynamic>> countries;
  final String selectedCode;
  final String selectedFlag;
  final Color cardBg, cardBorder, textPrimary, textMuted, accentColor;
  final void Function(Map<String, dynamic>) onSelected;
  final VoidCallback onDismiss;

  const _ProfileCountryDropdown({
    required this.link,
    required this.countries,
    required this.selectedCode,
    required this.selectedFlag,
    required this.cardBg,
    required this.cardBorder,
    required this.textPrimary,
    required this.textMuted,
    required this.accentColor,
    required this.onSelected,
    required this.onDismiss,
  });

  @override
  State<_ProfileCountryDropdown> createState() =>
      _ProfileCountryDropdownState();
}

class _ProfileCountryDropdownState extends State<_ProfileCountryDropdown> {
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.countries.where((c) {
      final name = (c['name'] as String).toLowerCase();
      final code = c['code'] as String;
      final q = _search.toLowerCase();
      return name.contains(q) || code.contains(q);
    }).toList();

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDismiss,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link: widget.link,
          showWhenUnlinked: false,
          offset: const Offset(0, 54),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 260,
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                color: widget.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: widget.cardBorder, width: 1.2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x4D000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                    child: TextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      onChanged: (v) => setState(() => _search = v),
                      style: TextStyle(fontSize: 13, color: widget.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search…',
                        hintStyle: TextStyle(
                          color: widget.textMuted,
                          fontSize: 13,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: widget.textMuted,
                          size: 17,
                        ),
                        filled: true,
                        fillColor: widget.cardBorder.withOpacity(0.15),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        isDense: true,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: widget.cardBorder,
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: widget.accentColor,
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final country = filtered[i];
                        final isSelected =
                            country['code'] == widget.selectedCode &&
                                country['flag'] == widget.selectedFlag;
                        return GestureDetector(
                          onTap: () => widget.onSelected(country),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? widget.accentColor.withOpacity(0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  country['flag'] as String,
                                  style: const TextStyle(fontSize: 18),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    country['name'] as String,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                      color: widget.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  country['code'] as String,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: widget.textMuted,
                                  ),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.check_rounded,
                                    color: widget.accentColor,
                                    size: 15,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}