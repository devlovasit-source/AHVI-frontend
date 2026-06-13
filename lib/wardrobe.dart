// ============================================================
// WARDROBE.DART - V2 (Premium AI Stylist UX)
// ============================================================
// Includes:
//  - 3-step AHVI upload flow (camera + gallery)
//  - New item detail modal (Works Well With / Best For / Style This)
//  - Grid with BoxFit.contain images, tighter metadata
//  - Ask AHVI FAB no longer overlaps grid content
// ============================================================

import 'dart:io';
import 'package:camera/camera.dart';
import 'package:myapp/services/backend_service.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:provider/provider.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/widgets/ahvi_header.dart';
import 'package:myapp/widgets/ahvi_stylist_chat.dart';

// 3-step upload flow + models
import 'package:myapp/widgets/ahvi_3step_upload_flow.dart';
import 'package:myapp/models/detected_item.dart';

// V2 item detail modal + pairing engine
import 'package:myapp/widgets/ahvi_item_detail_modal.dart';
import 'package:myapp/widgets/pairing_engine.dart';

// ============================================================
// MODAL STEP ENUM (camera capture flow)
// ============================================================
enum _ModalStep { camera, detecting, results }

// ============================================================
// PUBLIC WIDGET
// ============================================================
class Wardrobe extends StatefulWidget {
  const Wardrobe({super.key});

  @override
  State<Wardrobe> createState() => _WardrobeState();
}

// ============================================================
// HELPER - LAUNCH 3-STEP UPLOAD FLOW
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

// ============================================================
// WARDROBE SCREEN STATE
// ============================================================
class _WardrobeState extends State<Wardrobe> with TickerProviderStateMixin {
  // ----------------------------------------------------------
  // Core state
  // ----------------------------------------------------------
  final List<WardrobeItem> _items = [];
  bool _loading = true;

  // Camera state
  CameraController? _camCtrl;
  bool _camReady = false;

  // Capture/detect modal state
  _ModalStep _step = _ModalStep.camera;
  Uint8List? _capturedBytes;
  String? _detectError;
  String? _lastCaptureImageUrl;

  // FAB visibility (hide while scrolling so it doesn't block items)
  final ScrollController _gridScrollCtrl = ScrollController();
  bool _fabVisible = true;

  @override
  void initState() {
    super.initState();
    _loadWardrobeItems();
    _initCamera();

    _gridScrollCtrl.addListener(() {
      final dir = _gridScrollCtrl.position.userScrollDirection;
      if (dir == ScrollDirection.reverse && _fabVisible) {
        setState(() => _fabVisible = false);
      } else if (dir == ScrollDirection.forward && !_fabVisible) {
        setState(() => _fabVisible = true);
      }
    });
  }

  @override
  void dispose() {
    _camCtrl?.dispose();
    _gridScrollCtrl.dispose();
    super.dispose();
  }

  // ============================================================
  // LOAD WARDROBE ITEMS
  // ============================================================
  Future<void> _loadWardrobeItems() async {
    try {
      final appwriteService = Provider.of<AppwriteService>(
        context,
        listen: false,
      );
      final items = await appwriteService.getWardrobeItems();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Failed to load wardrobe: ${e.toString()}');
    }
  }

  // ============================================================
  // CAMERA LIFECYCLE
  // ============================================================
  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final camera = cameras.first;
      _camCtrl = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _camCtrl!.initialize();
      if (!mounted) return;
      setState(() => _camReady = true);
    } catch (e) {
      debugPrint('Camera init failed: $e');
    }
  }

  Future<void> _flipCamera() async {
    if (_camCtrl == null) return;
    try {
      final cameras = await availableCameras();
      if (cameras.length < 2) return;

      final current = _camCtrl!.description;
      final next = cameras.firstWhere(
        (c) => c.lensDirection != current.lensDirection,
        orElse: () => current,
      );

      await _camCtrl?.dispose();
      _camCtrl = CameraController(next, ResolutionPreset.high, enableAudio: false);
      await _camCtrl!.initialize();
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      debugPrint('Flip camera failed: $e');
    }
  }

  Future<void> _toggleFlash() async {
    if (_camCtrl == null) return;
    try {
      final current = _camCtrl!.value.flashMode;
      final next = current == FlashMode.off ? FlashMode.torch : FlashMode.off;
      await _camCtrl!.setFlashMode(next);
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      debugPrint('Toggle flash failed: $e');
    }
  }

  /// Fixes EXIF orientation issues from camera/gallery images.
  Future<Uint8List> _fixOrientation(Uint8List bytes) async {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;
      final fixed = img.bakeOrientation(decoded);
      return Uint8List.fromList(img.encodeJpg(fixed, quality: 90));
    } catch (e) {
      debugPrint('Orientation fix failed: $e');
      return bytes;
    }
  }

  // ============================================================
  // CAMERA CAPTURE - 3-STEP FLOW
  // ============================================================
  Future<void> _captureAndDetect() async {
    if (!_camReady || _camCtrl == null) return;
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

      await _runDetectionFor3Step(bytes);
    } catch (e) {
      setState(() => _step = _ModalStep.camera);
      _showError('Failed to capture image');
    }
  }

  // ============================================================
  // GALLERY PICK - 3-STEP FLOW
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
        setState(() {
          _capturedBytes = bytesList.first;
          _step = _ModalStep.detecting;
          _detectError = null;
        });
        await _runDetectionFor3Step(bytesList.first);
      } else {
        setState(() {
          _capturedBytes = bytesList.first;
          _step = _ModalStep.detecting;
          _detectError = null;
        });
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
  // DETECTION WITH 3-STEP MODAL INTEGRATION
  // ============================================================
  Future<void> _runDetectionFor3Step(Uint8List imageBytes) async {
    try {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(
                Theme.of(context).extension<AppThemeTokens>()!.accent.primary,
              ),
            ),
          ),
        );
      }

      final imageUrl = await _uploadImageToR2(imageBytes);
      _lastCaptureImageUrl = imageUrl;

      final detectedItems = await _detectClothingItems(imageBytes);

      if (!mounted) return;
      Navigator.pop(context); // close loading

      if (detectedItems.isEmpty) {
        _showError('Could not detect any clothing items. Please try again.');
        setState(() => _step = _ModalStep.camera);
        return;
      }

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
      if (!mounted) return;
      Navigator.pop(context); // close loading
      _showError('Detection failed: ${e.toString()}');
      setState(() => _step = _ModalStep.camera);
    }
  }

  // ============================================================
  // HANDLE MULTIPLE IMAGES
  // ============================================================
  Future<void> _runMultipleDetections(List<Uint8List> imageBytesList) async {
    try {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(
                Theme.of(context).extension<AppThemeTokens>()!.accent.primary,
              ),
            ),
          ),
        );
      }

      List<DetectedItem> allDetectedItems = [];

      for (int i = 0; i < imageBytesList.length; i++) {
        try {
          await _uploadImageToR2(imageBytesList[i]);
          final items = await _detectClothingItems(imageBytesList[i]);
          allDetectedItems.addAll(items);
        } catch (e) {
          debugPrint('Error detecting image ${i + 1}: $e');
          continue;
        }
      }

      if (!mounted) return;
      Navigator.pop(context); // close loading

      if (allDetectedItems.isEmpty) {
        _showError('Could not detect any items in the selected images.');
        setState(() => _step = _ModalStep.camera);
        return;
      }

      if (mounted) {
        launch3StepUploadFlow(
          context,
          detectedItems: allDetectedItems,
          originalImageUrl: null,
          onConfirm: (selectedItems) {
            _saveSelectedItemsToWardrobe(selectedItems);
          },
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showError('Batch detection failed: ${e.toString()}');
      setState(() => _step = _ModalStep.camera);
    }
  }

  // ============================================================
  // DETECT CLOTHING ITEMS (backend API)
  // ============================================================
  Future<List<DetectedItem>> _detectClothingItems(Uint8List imageBytes) async {
    try {
      final backendService = Provider.of<BackendService>(context, listen: false);
      final response = await backendService.analyzeImage(imageBytes);

      if (response == null || response['success'] == false) {
        throw Exception(response?['error'] ?? 'Detection failed');
      }

      final itemsList = (response['items'] as List?)
              ?.map((item) => DetectedItem.fromJson(Map<String, dynamic>.from(item)))
              .toList() ??
          [];

      return itemsList;
    } catch (e) {
      debugPrint('Detection error: $e');
      rethrow;
    }
  }

  // ============================================================
  // SAVE SELECTED ITEMS TO WARDROBE
  // ============================================================
  Future<void> _saveSelectedItemsToWardrobe(List<DetectedItem> selectedItems) async {
    try {
      _showMessage('Adding ${selectedItems.length} item(s) to wardrobe...');

      final appwriteService = Provider.of<AppwriteService>(context, listen: false);

      for (final detectedItem in selectedItems) {
        final wardrobeItem = detectedItem.toWardrobeItem();
        await appwriteService.createItem(wardrobeItem);

        if (mounted) {
          setState(() => _items.add(wardrobeItem));
        }
      }

      if (mounted) {
        _showMessage('✓ ${selectedItems.length} item(s) added to wardrobe!');
      }

      setState(() {
        _capturedBytes = null;
        _step = _ModalStep.camera;
      });

      // Re-init camera for next capture
      if (!_camReady) {
        await _initCamera();
      }
    } catch (e) {
      _showError('Failed to save items: ${e.toString()}');
    }
  }

  // ============================================================
  // UPLOAD IMAGE TO R2
  // ============================================================
  Future<String> _uploadImageToR2(Uint8List bytes) async {
    try {
      final backendService = Provider.of<BackendService>(context, listen: false);
      final url = await backendService.uploadImage(bytes);
      return url;
    } catch (e) {
      throw Exception('Failed to upload image: $e');
    }
  }

  // ============================================================
  // ITEM ACTIONS (wired into V2 detail modal)
  // ============================================================
  Future<void> _markWorn(WardrobeItem item) async {
    setState(() => item.worn += 1);
    try {
      final appwriteService = Provider.of<AppwriteService>(context, listen: false);
      await appwriteService.updateItem(item);
      _showMessage('Marked as worn today');
    } catch (e) {
      _showError('Failed to update: ${e.toString()}');
    }
  }

  Future<void> _toggleLike(WardrobeItem item) async {
    setState(() => item.liked = !item.liked);
    try {
      final appwriteService = Provider.of<AppwriteService>(context, listen: false);
      await appwriteService.updateItem(item);
    } catch (e) {
      _showError('Failed to update: ${e.toString()}');
    }
  }

  void _shareItem(WardrobeItem item) {
    // Hook up to your existing share implementation (e.g. share_plus)
    _showMessage('Sharing ${item.name}...');
  }

  Future<void> _removeItem(WardrobeItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove item'),
        content: Text('Remove "${item.name}" from your wardrobe?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final appwriteService = Provider.of<AppwriteService>(context, listen: false);
      await appwriteService.deleteItem(item.id);
      if (mounted) {
        setState(() => _items.removeWhere((i) => i.id == item.id));
      }
      _showMessage('Removed ${item.name}');
    } catch (e) {
      _showError('Failed to remove: ${e.toString()}');
    }
  }

  void _openEditFlow(WardrobeItem item) {
    // Hook up to your existing edit screen/modal
    _showMessage('Edit ${item.name}');
  }

  // ============================================================
  // MESSAGES
  // ============================================================
  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
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
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFC),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const AhviHeader(title: 'Wardrobe'),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _items.isEmpty
                          ? _buildEmptyState(t)
                          : _buildGrid(t),
                ),
              ],
            ),

            // -------------------------------------------
            // Ask AHVI FAB — hides while scrolling (P0 #7)
            // Positioned above bottom nav bar (bottom: 80)
            // so it never overlaps wardrobe items.
            // -------------------------------------------
            Positioned(
              right: 16,
              bottom: 80, // sits above bottom nav (~60) + safe margin
              child: AnimatedOpacity(
                opacity: _fabVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: AnimatedScale(
                  scale: _fabVisible ? 1.0 : 0.85,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_fabVisible,
                    child: _AskAhviFab(
                      onTap: () {
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(builder: (_) => const AhviStylistChat()),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddOptions,
        backgroundColor: t.accent.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // ============================================================
  // EMPTY STATE
  // ============================================================
  Widget _buildEmptyState(AppThemeTokens t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.checkroom, size: 64, color: t.accent.primary.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(
              'Your wardrobe is empty',
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to add your first item with AHVI',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF8A8A8E)),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // GRID (P0 #6: increased image area, trimmed metadata)
  // ============================================================
  Widget _buildGrid(AppThemeTokens t) {
    return GridView.builder(
      controller: _gridScrollCtrl,
      // P0 #7: bottom padding clears FAB (56) + bottom nav (60) + margin (16)
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 132),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.62, // taller cards → more image, less metadata
      ),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        return _WardrobeGridCard(
          item: item,
          accentColor: t.accent.primary,
          onTap: () => showItemDetailModal(
            context,
            item: item,
            allItems: _items,
            onWore: () => _markWorn(item),
            onEdit: () => _openEditFlow(item),
            onLike: () => _toggleLike(item),
            onShare: () => _shareItem(item),
            onRemove: () => _removeItem(item),
          ),
        );
      },
    );
  }

  // ============================================================
  // ADD OPTIONS (camera / gallery)
  // ============================================================
  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(ctx);
                _captureAndDetect();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickGallery();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// GRID CARD (P0 #1 + #6)
// ============================================================
class _WardrobeGridCard extends StatelessWidget {
  final WardrobeItem item;
  final Color accentColor;
  final VoidCallback onTap;

  const _WardrobeGridCard({
    required this.item,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -------------------------------------------
            // IMAGE (P0 #1: BoxFit.contain, not cover)
            // -------------------------------------------
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFFEFEFF7),
                  child: (item.displayUrl != null && item.displayUrl!.isNotEmpty)
                      ? Image.network(
                          item.displayUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.checkroom,
                            size: 40,
                            color: Color(0xFFBFBFD6),
                          ),
                        )
                      : const Icon(Icons.checkroom, size: 40, color: Color(0xFFBFBFD6)),
                ),
              ),
            ),

            // -------------------------------------------
            // METADATA (P0 #6: trimmed - name + cat + worn badge)
            // -------------------------------------------
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.cat,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: accentColor,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: item.worn == 0
                              ? const Color(0xFFF2F2F7)
                              : accentColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          item.worn == 0 ? 'New' : '${item.worn}x',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: item.worn == 0 ? const Color(0xFF8A8A8E) : accentColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ASK AHVI FAB
// ============================================================
class _AskAhviFab extends StatelessWidget {
  final VoidCallback onTap;
  const _AskAhviFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            colors: [t.accent.primary, t.accent.secondary],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow: [
            BoxShadow(
              color: t.accent.primary.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              'Ask AHVI',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
