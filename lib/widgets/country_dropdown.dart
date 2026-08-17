import 'package:flutter/material.dart';

// ── Country Dropdown Overlay — appears below the button ──
class CountryDropdownOverlay extends StatefulWidget {
  final LayerLink link;
  final List<Map<String, dynamic>> countries;
  final String selectedCode;
  final String selectedFlag;
  final void Function(Map<String, dynamic>) onSelected;
  final VoidCallback onDismiss;

  const CountryDropdownOverlay({
    super.key,
    required this.link,
    required this.countries,
    required this.selectedCode,
    required this.selectedFlag,
    required this.onSelected,
    required this.onDismiss,
  });
  @override
  State<CountryDropdownOverlay> createState() => _CountryDropdownOverlayState();
}

class _CountryDropdownOverlayState extends State<CountryDropdownOverlay> {
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const sheetBg = Color(0xFFFFFFFF);
    const itemBg = Color(0xFFF0F4FF);
    const borderCol = Color(0xFFE5E9F7);
    const labelCol = Color(0xFF66708A);
    const textCol = Color(0xFF1A1D26);
    const accentCol = Color(0xFF6B91FF);

    final filtered = widget.countries.where((c) {
      final name = (c['name'] as String).toLowerCase();
      final code = c['code'] as String;
      final q = _search.toLowerCase();
      return name.contains(q) || code.contains(q);
    }).toList();

    return Stack(
      children: [
        // Dismiss tap area
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDismiss,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand(),
          ),
        ),
        // Dropdown positioned below the button
        CompositedTransformFollower(
          link: widget.link,
          showWhenUnlinked: false,
          offset: const Offset(0, 54), // below button (height 50 + 4 gap)
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 260,
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderCol, width: 1.2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x18000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Search bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                    child: TextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      onChanged: (v) => setState(() => _search = v),
                      style: const TextStyle(
                        fontSize: 13,
                        color: textCol,
                        fontFamily: 'DM Sans',
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search…',
                        hintStyle: const TextStyle(
                          color: labelCol,
                          fontSize: 13,
                          fontFamily: 'DM Sans',
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: labelCol,
                          size: 17,
                        ),
                        filled: true,
                        fillColor: itemBg,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        isDense: true,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: borderCol,
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: accentCol,
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // List
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final c = filtered[i];
                        final isSelected =
                            c['code'] == widget.selectedCode &&
                            c['flag'] == widget.selectedFlag;
                        return GestureDetector(
                          onTap: () => widget.onSelected(c),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0x256B91FF)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  c['flag'] as String,
                                  style: const TextStyle(fontSize: 18),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    c['name'] as String,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                      color: textCol,
                                      fontFamily: 'DM Sans',
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  c['code'] as String,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: labelCol,
                                    fontFamily: 'DM Sans',
                                  ),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.check_rounded,
                                    color: accentCol,
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
