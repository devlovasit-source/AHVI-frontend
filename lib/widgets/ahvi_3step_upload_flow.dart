// ============================================================
// AHVI_3STEP_UPLOAD_FLOW.DART
// 3-Step Progressive Modal for Single & Multi-Item Wardrobe Uploads
// ============================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:myapp/theme/theme_tokens.dart';

// ============================================================
// DATA MODELS
// ============================================================

class DetectedItem {
  final String id;
  final String name;
  final String color;
  final String style;
  final List<String> occasions;
  final List<String> pairsWith;
  final int pairingCount;
  final int matchCount;
  final int occasionCount;
  final String imageUrl;
  bool isSelected;

  DetectedItem({
    required this.id,
    required this.name,
    required this.color,
    required this.style,
    required this.occasions,
    required this.pairsWith,
    required this.pairingCount,
    required this.matchCount,
    required this.occasionCount,
    required this.imageUrl,
    this.isSelected = true,
  });
}

// ============================================================
// MAIN MODAL
// ============================================================

class Ahvi3StepUploadModal extends StatefulWidget {
  final List<DetectedItem> detectedItems;
  final VoidCallback onClose;
  final Function(List<DetectedItem>) onConfirm;
  final String? originalImageUrl;

  const Ahvi3StepUploadModal({
    required this.detectedItems,
    required this.onClose,
    required this.onConfirm,
    this.originalImageUrl,
  });

  @override
  State<Ahvi3StepUploadModal> createState() => _Ahvi3StepUploadModalState();
}

class _Ahvi3StepUploadModalState extends State<Ahvi3StepUploadModal>
    with TickerProviderStateMixin {
  late AnimationController _stepTransitionCtrl;
  late PageController _carouselCtrl;
  
  int _currentStep = 0; // 0=Understanding, 1=Reveal, 2=Insight
  int _currentItemIndex = 0;
  bool _step1Complete = false;
  List<DetectedItem> _selectedItems = [];

  final List<String> _detectionChecks = [
    'Item type detected',
    'Color identified',
    'Style profile analyzed',
    'Occasion suitability assessed',
  ];
  late List<bool> _checklistComplete;

  @override
  void initState() {
    super.initState();
    _stepTransitionCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _carouselCtrl = PageController();
    _checklistComplete = List.filled(_detectionChecks.length, false);
    _selectedItems = List.from(widget.detectedItems);
    
    _startStep1Animation();
  }

  void _startStep1Animation() {
    // Stagger checklist completion
    for (int i = 0; i < _detectionChecks.length; i++) {
      Future.delayed(Duration(milliseconds: 300 + (i * 150)), () {
        if (mounted) {
          setState(() => _checklistComplete[i] = true);
        }
      });
    }
    
    // Auto-advance after 1.5 seconds
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && !_step1Complete) {
        _advanceStep();
      }
    });
  }

  void _advanceStep() async {
    await _stepTransitionCtrl.forward();
    if (mounted) {
      setState(() {
        _currentStep++;
        if (_currentStep == 1) {
          _step1Complete = true;
        }
      });
    }
    _stepTransitionCtrl.reset();
  }

  void _goBackStep() async {
    await _stepTransitionCtrl.forward();
    if (mounted) {
      setState(() => _currentStep--);
    }
    _stepTransitionCtrl.reset();
  }

  void _onItemSelected(int index) {
    setState(() {
      _selectedItems[index].isSelected = !_selectedItems[index].isSelected;
    });
  }

  void _submitSelection() {
    final selected = _selectedItems.where((item) => item.isSelected).toList();
    if (selected.isNotEmpty) {
      widget.onConfirm(selected);
      widget.onClose();
    }
  }

  @override
  void dispose() {
    _stepTransitionCtrl.dispose();
    _carouselCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSingleItem = widget.detectedItems.length == 1;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          // Background blur
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              color: Colors.black54,
            ),
          ),
          // Modal container
          Center(
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: 400,
                maxHeight: 800,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: _currentStep == 0 ? Color(0xFF1a1a1a) : Colors.white,
              ),
              child: Stack(
                children: [
                  // Step content
                  PageView(
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      // STEP 0: Understanding
                      _buildStep1Understanding(),
                      
                      // STEP 1: Editorial Reveal
                      _buildStep2Reveal(isSingleItem),
                      
                      // STEP 2: AHVI Insight
                      _buildStep3Insight(isSingleItem),
                    ],
                    controller: PageController(initialPage: _currentStep),
                    onPageChanged: (_) {},
                  ),
                  
                  // Top bar with close button
                  Positioned(
                    top: 16,
                    right: 16,
                    child: GestureDetector(
                      onTap: widget.onClose,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black26,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  
                  // Back button (only on Step 2 for multi-item)
                  if (_currentStep == 1 && !isSingleItem)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: GestureDetector(
                        onTap: _goBackStep,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black12,
                          ),
                          child: Icon(
                            Icons.chevron_left_rounded,
                            color: Colors.black87,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STEP 1: UNDERSTANDING
  // ============================================================
  
  Widget _buildStep1Understanding() {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    
    return Container(
      decoration: BoxDecoration(
        image: widget.originalImageUrl != null
            ? DecorationImage(
                image: NetworkImage(widget.originalImageUrl!),
                fit: BoxFit.cover,
              )
            : null,
        color: Color(0xFF1a1a1a),
      ),
      child: Stack(
        children: [
          // Dark overlay
          Container(
            color: Colors.black.withValues(alpha: 0.6),
          ),
          // Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Spinning sparkle icon
                _AnimatingSparkle(),
                const SizedBox(height: 24),
                
                // Title
                Text(
                  'AHVI is understanding\nthis piece...',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 32),
                
                // Checklist
                Column(
                  children: List.generate(
                    _detectionChecks.length,
                    (index) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          AnimatedOpacity(
                            opacity: _checklistComplete[index] ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 300),
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: t.accent.primary,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _detectionChecks[index],
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                
                // Progress indicator
                Text(
                  'Analyzing visual features...',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white54,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          
          // Progress bar at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    t.accent.primary,
                    t.accent.secondary,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STEP 2: EDITORIAL REVEAL
  // ============================================================
  
  Widget _buildStep2Reveal(bool isSingleItem) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final item = _selectedItems[_currentItemIndex];
    
    return SingleChildScrollView(
      child: Column(
        children: [
          // Item carousel navigation (multi-item only)
          if (!isSingleItem)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text(
                      '${_currentItemIndex + 1}/${_selectedItems.length}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      _carouselCtrl.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          
          // Product image
          Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey[200],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                item.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey[300],
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Item name & specs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Text(
                  item.name,
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.color} • ${item.style}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          // Wardrobe stats
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'In Your Wardrobe',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildStatCard(
                        count: item.pairingCount,
                        label: 'Shirts',
                        detail: 'pair well',
                      ),
                      _buildStatCard(
                        count: item.matchCount,
                        label: 'Trousers',
                        detail: 'match',
                      ),
                      _buildStatCard(
                        count: item.occasionCount,
                        label: 'Occasions',
                        detail: 'suit this item',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // CTA Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: MaterialButton(
                onPressed: _advanceStep,
                color: t.accent.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50),
                ),
                elevation: 4,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Next',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
  
  Widget _buildStatCard({
    required int count,
    required String label,
    required String detail,
  }) {
    return Flexible(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            count.toString(),
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            detail,
            style: GoogleFonts.inter(
              fontSize: 10,
              color: Colors.black54,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STEP 3: AHVI INSIGHT
  // ============================================================
  
  Widget _buildStep3Insight(bool isSingleItem) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final item = _selectedItems[_currentItemIndex];
    final selectedCount = _selectedItems.where((i) => i.isSelected).length;
    
    return Container(
      color: Color(0xFF1a1a1a),
      child: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 16),
                
                // Header
                Center(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _AnimatingSparkle(size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'AHVI Insight',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: t.accent.primary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Clear intelligence.\nNo stylist, just insight.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                // Best For section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Best For',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildOccasionBadge('💼', 'Office\nMeetings'),
                          _buildOccasionBadge('🎯', 'Smart\nCasual'),
                          _buildOccasionBadge('🎭', 'Evening\nEvents'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                // Pairs Well With
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pairs Well With',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Column(
                        children: item.pairsWith
                            .take(4)
                            .map(
                              (pair) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: t.accent.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      pair,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                // Multi-item selection (if needed)
                if (!isSingleItem && _selectedItems.length > 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add to Wardrobe',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Column(
                          children: List.generate(
                            _selectedItems.length,
                            (index) {
                              final itemToSelect = _selectedItems[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: GestureDetector(
                                  onTap: () => _onItemSelected(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: itemToSelect.isSelected
                                            ? t.accent.primary
                                            : Colors.white24,
                                        width: 1.5,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Checkbox(
                                          value: itemToSelect.isSelected,
                                          onChanged: (_) =>
                                              _onItemSelected(index),
                                          fillColor:
                                              MaterialStateProperty.all(
                                            itemToSelect.isSelected
                                                ? t.accent.primary
                                                : Colors.transparent,
                                          ),
                                          borderSide: BorderSide(
                                            color: itemToSelect.isSelected
                                                ? t.accent.primary
                                                : Colors.white30,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          itemToSelect.name,
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                
                const SizedBox(height: 24),
                
                // CTA Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: MaterialButton(
                      onPressed: selectedCount > 0 ? _submitSelection : null,
                      color: selectedCount > 0
                          ? t.accent.primary
                          : Colors.grey[700],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                      elevation: 4,
                      disabledElevation: 0,
                      child: Text(
                        isSingleItem
                            ? 'Add to Wardrobe'
                            : 'Add ${selectedCount > 0 ? selectedCount : 0} items',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: selectedCount > 0
                              ? Colors.white
                              : Colors.white54,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Privacy notice
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 12,
                        color: Colors.white54,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Your data is private and secure',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildOccasionBadge(String emoji, String label) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white.withValues(alpha: 0.05),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Center(
            child: Text(
              emoji,
              style: const TextStyle(fontSize: 28),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: Colors.white,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// ANIMATED SPARKLE WIDGET
// ============================================================

class _AnimatingSparkle extends StatefulWidget {
  final double size;
  const _AnimatingSparkle({this.size = 32});

  @override
  State<_AnimatingSparkle> createState() => _AnimatingSparkleState();
}

class _AnimatingSparkleState extends State<_AnimatingSparkle>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
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
      builder: (_, __) => Transform.rotate(
        angle: _ctrl.value * 2 * 3.14159,
        child: Icon(
          Icons.auto_awesome_rounded,
          size: widget.size,
          color: Colors.amber[400],
        ),
      ),
    );
  }
}
