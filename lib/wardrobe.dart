// ============================================================
// WARDROBE.DART - UPDATED WITH 3-STEP AHVI UPLOAD FLOW
// ============================================================
// KEY CHANGES:
// 1. Added imports for new 3-step modal and DetectedItem model
// 2. Replaced detection modal with Ahvi3StepUploadModal
// 3. Updated _runDetection to return DetectedItem list
// 4. Kept camera/gallery picking logic unchanged
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:myapp/services/backend_service.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/services/connectivity_watcher.dart';
import 'package:myapp/services/offline_cache.dart';
import 'package:provider/provider.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:myapp/app_localizations.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/widgets/ahvi_header.dart';
import 'package:myapp/widgets/ahvi_stylist_chat.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// NEW IMPORTS FOR 3-STEP FLOW
// ============================================================
import 'package:myapp/widgets/ahvi_3step_upload_flow.dart'; // NEW
import 'package:myapp/models/detected_item.dart'; // NEW

// ============================================================
// APPWRITE & ENVIRONMENT
// ============================================================
import 'package:appwrite/appwrite.dart';
import 'package:myapp/config/env.dart';

// ... rest of existing imports and color helper functions ...

// ============================================================
// PUBLIC HELPER - UPDATED FOR NEW 3-STEP MODAL
// ============================================================
void showAddToWardrobeModal(
  BuildContext context, {
  void Function(Map<String, dynamic> item)? onSaved,
}) {
  // OLD: showDialog with _AddItemModal
  // NEW: No longer needed - camera picker launches 3-step modal directly
  // This function is kept for backward compatibility
  showDialog(
    context: context,
    useRootNavigator: true,
    barrierColor: Colors.black54,
    builder: (_) => _AddItemModal(onSave: (item) => onSaved?.call(item)),
  );
}

// ============================================================
// NEW HELPER - LAUNCH 3-STEP UPLOAD FLOW
// ============================================================
void launch3StepUploadFlow(
  BuildContext context, {
  required List<DetectedItem> detectedItems,
  String? originalImageUrl,
  required Function(List<DetectedItem>) onConfirm,
}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => Ahvi3StepUploadModal(
      detectedItems: detectedItems,
      originalImageUrl: originalImageUrl,
      onClose: () => Navigator.pop(context),
      onConfirm: onConfirm,
    ),
  );
}

// ... existing WardrobeItem, helper functions, etc. ...

// ============================================================
// WARDROBE SCREEN STATE CLASS - KEY CHANGES
// ============================================================
class _WardrobeState extends State<Wardrobe> with TickerProviderStateMixin {
  // ... existing variables ...
  
  // Add this for tracking image URLs for 3-step modal
  String? _lastCaptureImageUrl;
  
  @override
  void initState() {
    super.initState();
    // ... existing init code ...
  }

  // ============================================================
  // CAMERA CAPTURE - UPDATED TO USE 3-STEP FLOW
  // ============================================================
  Future<void> _captureAndDetect() async {
    if (!_camReady) return;
    HapticFeedback.mediumImpact();
    try {
      final xfile = await _camCtrl!.takePicture();
      final rawBytes = await File(xfile.path).readAsBytes();
      final bytes = await _fixOrientation(rawBytes);

      // Dispose camera to save battery
      await _camCtrl?.dispose();
      _camCtrl = null;
      if (mounted) setState(() => _camReady = false);

      setState(() {
        _capturedBytes = bytes;
        _step = _ModalStep.detecting;
        _detectError = null;
      });
      
      // NEW: Run detection and launch 3-step modal
      await _runDetectionFor3Step(bytes);
      
    } catch (e) {
      setState(() => _step = _ModalStep.camera);
      _showError('Failed to capture image');
    }
  }

  // ============================================================
  // GALLERY PICK - UPDATED TO USE 3-STEP FLOW
  // ============================================================
  Future<void> _pickGallery() async {
    try {
      final picker = ImagePicker();
      final files = await picker.pickMultiImage(
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 82,
        limit: 6,
      );
      if (files.isEmpty) return;
      if (!mounted) return;

      // Dispose camera
      await _camCtrl?.dispose();
      _camCtrl = null;
      if (mounted) setState(() => _camReady = false);

      final capped = files.take(6).toList();
      if (files.length > 6) {
        _showMessage('Only the first 6 images were selected');
      }

      final rawList = await Future.wait(capped.map((f) => f.readAsBytes()));
      final bytesList = await Future.wait(rawList.map(_fixOrientation));
      if (!mounted) return;

      if (bytesList.length == 1) {
        // Single image
        setState(() {
          _capturedBytes = bytesList.first;
          _step = _ModalStep.detecting;
          _detectError = null;
        });
        // NEW: Use 3-step flow
        await _runDetectionFor3Step(bytesList.first);
      } else {
        // Multiple images - process each one
        setState(() {
          _capturedBytes = bytesList.first;
          _step = _ModalStep.detecting;
          _detectError = null;
        });
        // NEW: Process each image through 3-step flow
        await _runMultipleDetections(bytesList);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _detectError = 'Could not load images. Please try again.';
        _step = _ModalStep.results;
      });
      _showError(_detectError!);
    }
  }

  // ============================================================
  // NEW: DETECTION WITH 3-STEP MODAL INTEGRATION
  // ============================================================
  Future<void> _runDetectionFor3Step(Uint8List imageBytes) async {
    try {
      // Show loading dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(
                context.themeTokens.accent.primary,
              ),
            ),
          ),
        );
      }

      // Step 1: Upload image to R2 (if needed)
      final imageUrl = await _uploadImageToR2(imageBytes);
      _lastCaptureImageUrl = imageUrl;

      // Step 2: Call backend detection API
      final detectedItems = await _detectClothingItems(imageBytes);

      if (!mounted) return;
      
      // Close loading dialog
      Navigator.pop(context);

      // Step 3: Validate detection results
      if (detectedItems.isEmpty) {
        _showError('Could not detect any clothing items. Please try again.');
        setState(() => _step = _ModalStep.camera);
        return;
      }

      // Step 4: Launch 3-step modal with detected items
      if (mounted) {
        launch3StepUploadFlow(
          context,
          detectedItems: detectedItems,
          originalImageUrl: imageUrl,
          onConfirm: (selectedItems) {
            _saveSelectedItemsToWardrobe(selectedItems);
          },
        );
      }
    } catch (e) {
      if (!mounted) {
        Navigator.pop(context); // Close loading dialog
        return;
      }
      Navigator.pop(context); // Close loading dialog
      _showError('Detection failed: ${e.toString()}');
      setState(() => _step = _ModalStep.camera);
    }
  }

  // ============================================================
  // NEW: HANDLE MULTIPLE IMAGES
  // ============================================================
  Future<void> _runMultipleDetections(List<Uint8List> imageBytesList) async {
    try {
      // Show loading
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(
                context.themeTokens.accent.primary,
              ),
            ),
          ),
        );
      }

      List<DetectedItem> allDetectedItems = [];

      // Process each image
      for (int i = 0; i < imageBytesList.length; i++) {
        try {
          final imageUrl = await _uploadImageToR2(imageBytesList[i]);
          final items = await _detectClothingItems(imageBytesList[i]);
          allDetectedItems.addAll(items);
        } catch (e) {
          print('Error detecting image ${i + 1}: $e');
          continue; // Skip this image and continue
        }
      }

      if (!mounted) return;
      Navigator.pop(context); // Close loading

      if (allDetectedItems.isEmpty) {
        _showError('Could not detect any items in the selected images.');
        setState(() => _step = _ModalStep.camera);
        return;
      }

      // Launch 3-step modal with all detected items
      if (mounted) {
        launch3StepUploadFlow(
          context,
          detectedItems: allDetectedItems,
          originalImageUrl: null, // Multiple images
          onConfirm: (selectedItems) {
            _saveSelectedItemsToWardrobe(selectedItems);
          },
        );
      }
    } catch (e) {
      if (!mounted) {
        Navigator.pop(context);
        return;
      }
      Navigator.pop(context);
      _showError('Batch detection failed: ${e.toString()}');
      setState(() => _step = _ModalStep.camera);
    }
  }

  // ============================================================
  // NEW: DETECT CLOTHING ITEMS (calls backend API)
  // ============================================================
  Future<List<DetectedItem>> _detectClothingItems(Uint8List imageBytes) async {
    try {
      // Call your backend detection API
      final backendService = Provider.of<BackendService>(
        context,
        listen: false,
      );

      // Assuming your backend has a detection endpoint
      final response = await backendService.analyzeImage(imageBytes);

      if (response == null || response['success'] == false) {
        throw Exception(response?['error'] ?? 'Detection failed');
      }

      // Convert backend response to DetectedItem list
      final itemsList = (response['items'] as List?)
          ?.map((item) => DetectedItem.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList() ?? [];

      return itemsList;
    } catch (e) {
      print('Detection error: $e');
      rethrow;
    }
  }

  // ============================================================
  // NEW: SAVE SELECTED ITEMS TO WARDROBE
  // ============================================================
  Future<void> _saveSelectedItemsToWardrobe(
    List<DetectedItem> selectedItems,
  ) async {
    try {
      // Show saving indicator
      _showMessage('Adding ${selectedItems.length} item(s) to wardrobe...');

      final appwriteService = Provider.of<AppwriteService>(
        context,
        listen: false,
      );

      // Convert DetectedItem to WardrobeItem and save
      for (final detectedItem in selectedItems) {
        final wardrobeItem = detectedItem.toWardrobeItem();

        // Save to Appwrite
        await appwriteService.createItem(wardrobeItem);

        // Update local list
        if (mounted) {
          setState(() {
            _items.add(wardrobeItem);
          });
        }
      }

      // Show success message
      if (mounted) {
        _showMessage('✓ ${selectedItems.length} item(s) added to wardrobe!');
      }

      // Clear state
      setState(() {
        _capturedBytes = null;
        _step = _ModalStep.camera;
      });
    } catch (e) {
      _showError('Failed to save items: ${e.toString()}');
    }
  }

  // ============================================================
  // EXISTING HELPER: UPLOAD IMAGE TO R2
  // ============================================================
  Future<String> _uploadImageToR2(Uint8List bytes) async {
    try {
      // Your existing R2 upload logic
      // This should return the URL of the uploaded image
      final backendService = Provider.of<BackendService>(
        context,
        listen: false,
      );
      
      // Implement your R2 upload logic here
      // For now, returning a placeholder
      return 'https://your-r2-url.com/image.jpg';
    } catch (e) {
      throw Exception('Failed to upload image: $e');
    }
  }

  // ============================================================
  // EXISTING HELPERS: MESSAGES
  // ============================================================
  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ============================================================
  // KEEP EXISTING METHODS UNCHANGED
  // ============================================================
  // _initCamera()
  // _flipCamera()
  // _toggleFlash()
  // _fixOrientation()
  // All other existing methods remain the same

  @override
  Widget build(BuildContext context) {
    // Return your existing wardrobe UI
    return Scaffold(
      // ... your existing wardrobe screen UI ...
    );
  }
}

// ============================================================
// OLD _AddItemModal CLASS - KEPT FOR BACKWARD COMPATIBILITY
// ============================================================
// You can optionally remove this if you fully migrate to the 3-step flow
// Or keep it if you still need manual item entry without detection

class _AddItemModal extends StatefulWidget {
  final void Function(Map<String, dynamic> item) onSave;
  const _AddItemModal({required this.onSave});

  @override
  State<_AddItemModal> createState() => _AddItemModalState();
}

class _AddItemModalState extends State<_AddItemModal>
    with TickerProviderStateMixin {
  // ... existing implementation ...
  // This can be removed if you don't need it anymore
  
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
