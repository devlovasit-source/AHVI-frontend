// Shared occasion vocabulary/display helpers — the single place occasion
// wording gets reconciled between the backend and every frontend consumer
// (wardrobe review, saved-item editing, PairingEngine, item detail). Moved
// out of wardrobe.dart so those consumers don't have to depend on the whole
// wardrobe module just for vocabulary logic.

/// The canonical 9-value occasion vocabulary shown as toggleable chips on
/// both the upload review screen and the saved-item edit dialog.
const List<String> kOccasionChipVocabulary = [
  'Everyday',
  'Casual',
  'Work',
  'Dinner',
  'Travel',
  'Sport',
  'Party',
  'Festive',
  'Wedding',
];

/// Turns a raw occasion value (possibly an internal/localisation key like
/// `upload_occasion_everyday`, or a snake_case backend value) into a
/// human-readable label. Never renders raw keys in the review UI.
String humanizeOccasion(String raw) {
  var v = raw.trim();
  if (v.isEmpty) return v;
  v = v.replaceFirst(RegExp(r'^upload_occasion_', caseSensitive: false), '');
  v = v.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  if (v.isEmpty) return v;
  return v
      .split(' ')
      .map(
        (w) => w.isEmpty
            ? w
            : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
      )
      .join(' ');
}

/// Backend occasion tokens that mean the same thing as an existing review
/// chip but use different wording — not just different casing/underscores,
/// which humanizeOccasion already handles on its own. Only aliases we're
/// certain of are listed here; anything else (client_meeting, business_lunch,
/// home, private, lounge, ...) intentionally falls through to
/// humanizeOccasion's plain formatting rather than being guessed at, so no
/// occasion is ever silently discarded — it just isn't re-worded.
const Map<String, String> _occasionAliases = {
  'office': 'Work',
  'work': 'Work',
  'date': 'Dinner',
  'dinner': 'Dinner',
  'casual': 'Casual',
  'travel': 'Travel',
  'party': 'Party',
  'festive': 'Festive',
  'wedding': 'Wedding',
};

/// Single shared entry point for turning a raw backend/legacy occasion
/// value into the label the review chips, item-detail pills, and
/// PairingEngine's occasion matching all agree on. Checks the semantic
/// alias map first, then falls back to humanizeOccasion's mechanical
/// casing/underscore cleanup for anything not in the map — this is the
/// only place occasion vocabulary gets reconciled anywhere in the app.
String canonicalizeOccasion(String raw) {
  var key = raw.trim().toLowerCase();
  key = key.replaceFirst(RegExp(r'^upload_occasion_'), '');
  key = key.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  final alias = _occasionAliases[key];
  if (alias != null) return alias;
  return humanizeOccasion(raw);
}
