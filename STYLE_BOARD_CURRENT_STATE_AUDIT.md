# AHVI Style Board — Architecture Audit

**Branch:** `claude/ahvi-style-board-audit-rfvxdq`  
**Commit:** `99bc53c`  
**Worktree:** clean  
**Audit date:** 2026-07-29  

---

## 1. Executive Verdict

**Grade B- (Partially canonical)**

The core lock/shuffle contract path is architecturally sound and well-exercised by tests. `EditorialBoardLayoutEngine` is correctly isolated. `AhviOutfitBoardCard` already serves as the single active-board renderer for Recommendation, Style This, and Build Outfit — no new renderer is needed.

Three structural problems reduce the grade:

1. **Save/Share read stale pre-shuffle data** (highest severity — user-visible correctness bug with zero test coverage).
2. **Four independent role resolvers** disagree on identical category strings.
3. **`ShareableOutfitBoard._ShareCanvas`** uses hardcoded fractional positions rather than `EditorialBoardLayoutEngine`, so the share PNG diverges from the live card.

Two legacy components (`StyleBoardBody`, `BoardLayoutEngine`) are dead code — not mounted in any live widget tree.

---

## 2. Current Branch and Commit

```
Branch : claude/ahvi-style-board-audit-rfvxdq
HEAD   : 99bc53c483f08b4983d28926004052a2edf05f74
Status : clean
```

Note: target branch `fix/beta-apk-p0-integration` does not exist in this remote. Audit was performed against the equivalent codebase on the current branch. All findings apply equally to the same sources on either branch.

---

## 3. Surface Inventory

| Surface | Entry point | Response parser | Model | Renderer | Layout engine | Asset resolver | Actions |
|---------|-------------|-----------------|-------|----------|---------------|----------------|---------|
| **Recommendation** | `visual_direction_carousel.dart` → `AhviOutfitBoardCard` | `ahvi_block_response_parser.dart` `parseAhviResponse()` | `OutfitBoardModel.fromPayload()` → `StyleBoardData` | `EditorialBoardCanvas` | `EditorialBoardLayoutEngine` | `_transparentUrlFor()` in `ahvi_outfit_board_card.dart` | Save, Share, Like, Dislike |
| **Style This** | Same `AhviOutfitBoardCard` (scenario=style_this) | Same parser; `board_items` authoritative path | `StyleBoardData` + `StyleBoardController` | `EditorialBoardCanvas` | `EditorialBoardLayoutEngine` | Same `_transparentUrlFor()` | Save, Share, Shuffle (if `supportsShuffle`), Lock per item |
| **Build Outfit** | Same `AhviOutfitBoardCard` (scenario=build_outfit) | Same parser; scenario=build_outfit | `StyleBoardData` + `StyleBoardController` | `EditorialBoardCanvas` | `EditorialBoardLayoutEngine` | Same `_transparentUrlFor()` | Save, Share, Shuffle, Lock per item |
| **Saved Board thumb** | `saved_board_card.dart` → `SavedBoardThumb` | `extractSavedBoardImages()` in `saved_board_images.dart` | Raw Appwrite Document map | `EditorialBoardCanvas` (via `boardDataFromMap()`) | `EditorialBoardLayoutEngine` | Separate URL chain in `saved_board_images.dart` | Share (text-only), Detail sheet |
| **Saved Board detail** | Detail sheet on `SavedBoardCard` | Same as thumb | Same raw map | `SavedBoardThumb` at height:340 | `EditorialBoardLayoutEngine` | Same | Share (text-only) |
| **Share/Export PNG** | `OutfitActionBar._share()` → `ShareableOutfitBoard` | Reads original direction JSON `_saveItems()` | Hardcoded `ShareBoardItem` list | `_ShareCanvas` (hardcoded fractional positions) | **None** (hardcoded positions) | `item['image_url']` from original direction only | PNG capture → SharePlus |
| **Legacy style board** | `board_renderer.dart` `StyleBoardBody` | `boardDataFromMap()` | `StyleBoardData` | `StyleBoardBody` column/row layout | `BoardLayoutEngine` | `_selectTransparentUrl()` | None (dead code) |

---

## 4. End-to-End Flow Maps

### 4A. Recommendation

```
Chat response JSON
  └─ ahvi_block_response_parser.dart parseAhviResponse()
       └─ _processVisualDirections() / _styleBoardToDirection()
            └─ AhviResponseBlock(type=visualDirections, data=Map)
  └─ ahvi_block_renderer.dart → VisualDirectionCarousel
       └─ _underlyingOutfitItems() — checks board_items/boardItems/items/pieces
       └─ AhviOutfitBoardCard(direction=Map, width=360)
            └─ initState → _parseBoard()
                 └─ OutfitBoardModel.fromPayload(direction)
                      title: archetype > direction_name > title
                      items: board_items authoritative; else hero + complete_the_look + items
                 └─ _toStyleBoardData(): maps items, deduplicates by URL/name,
                      applies _enforceSlots (max top/bottom/foot/outer/dress=1, acc=4)
                      reads board_id/revision/scenario/source_policy from direction
            └─ _replaceBoard(board):
                 StyleBoardState created; AHVI_BOARD_CONTRACT_CHECK logged
                 supportsShuffle=false → controller = null
            └─ build():
                 OutfitContextStrip (title + occasion chip)
                 EditorialBoardCanvas → EditorialBoardLayoutEngine → EditorialBoardItem
                   _transparentUrlFor(): board_image_url > transparent_image_url >
                     cutout_url(ready) > image_url(cutout_ready) > image_url(itemId+source) > null
                   Image.network(BoxFit.contain) + Transform.scale(visualScale) + shadow
                 OutfitActionBar: Save | Like | Dislike | Share
                 BoardStoryExpandable (why_it_works, styling_tip — collapsed)
```

- Uses current revision: N/A (no controller)
- Reconstructs independently: No (single parse path)
- Re-fetches: No
- Drops fields: `board_id`, `revision`, `source_policy` parsed but unused (no controller created)

### 4B. Style This

Identical parse path to 4A. Direction additionally carries:
- `board_id` non-empty and not prefixed `outfit_card_`
- `revision >= 1`
- `source_policy = 'wardrobe'` or `'style_asset'`
- `scenario = 'style_this'`

```
_replaceBoard():
  StyleBoardState.supportsShuffle = true → StyleBoardController created
  AHVI_BOARD_CONTRACT_CHECK logged with per-predicate pass/fail

BoardMutationBar rendered:
  Lock icon per item (item.isLockable), Shuffle button

User taps Shuffle:
  StyleBoardController.shuffle()
    deep copy snapshot
    sets isRegenerating on unlocked items
    StyleBoardApiService.buildShufflePayload():
      scenario: 'shuffle_unlocked'
      source_policy, revision, locked_items, board_items, shuffle_slots, exclude_item_ids
    _validate(result):
      boardId unchanged, revision strictly ++,
      lockedItemsPreserved, items non-empty,
      sourcePolicy and scenario unchanged,
      unlocked items satisfy source policy,
      locked item fields unchanged
    pass → _state = new state; undo stack updated
    fail → _state = snapshot; error code returned

_currentBoard getter: _initialBoard metadata + controller.state.items
EditorialBoardCanvas re-renders with new items
```

- Uses current revision: Yes (contract-validated)
- Reconstructs independently: No
- Re-fetches: Only on Shuffle
- Drops fields: `story` fields carried from `_initialBoard` through all shuffles

### 4C. Build Outfit

Identical to 4B except `scenario = 'build_outfit'`, `source_policy` may be `'mixed'`, payload carries `allow_wardrobe_fallback: true` if applicable. Multiple items may be locked simultaneously.

### 4D. Saved Board

```
BoardsScreen / SavedBoardCard
  └─ getAllSavedBoards() / getSavedBoardsByOccasion()  [appwrite_service.dart]
       returns List<Document> (Map<String, dynamic>)
  └─ _itemsForBoard():
       tries: doc['itemIds'] → wardrobe hydration (getWardrobeItems)
       else: doc['savedBoardItems'] / doc['items'] / doc['outfitItems'] / doc['board_payload']
       else: extractSavedBoardImages(doc.data)  [saved_board_images.dart]
  └─ SavedBoardThumb(items, boardMap=doc.data):
       boardDataFromMap(boardMap) → StyleBoardData
         NO board_id/revision/sourcePolicy → supportsShuffle=false, items not lockable
       EditorialBoardCanvas(board, width, height)
  └─ Detail sheet:
       whyItWorks / why_it_works / explanation / outfitDescription shown
       stylingTip / styling_tip / styleTip / tip shown
       Share: text-only via SharePlus (no image capture)
```

- Uses current revision: No (never had one; Appwrite doc has no revision field)
- Reconstructs independently: Yes (from raw Appwrite doc via `boardDataFromMap`)
- Re-fetches: No (uses stored doc)
- Drops fields: board_id, revision, source_policy, story — none persisted to Appwrite

### 4E. Share / Export PNG

```
OutfitActionBar._share():
  _captureShareComposition():
    _shareBoardItems() = _saveItems():
      reads ORIGINAL direction['board_items'] / direction['boardItems'] / direction['items']
      ← NOT controller.state.items — shuffled items EXCLUDED
    builds ShareableOutfitBoard(title, occasion, items) offscreen
    RepaintBoundary.toImage(pixelRatio=1.5) → PNG bytes
  fallback: _shareBoundaryKey on live canvas

ShareableOutfitBoard / _ShareCanvas:
  kShareBackground = Color(0xFFFAF9F6)  opaque
  4:5 aspect
  Hardcoded fractional positions per role (no EditorialBoardLayoutEngine)
  _ShareGarment: Transform.scale(footwear:1.30, others:1.06) + BoxFit.contain
  Shows: AHVI branding, title, occasion chip, 'Styled on AHVI' footer
  Excludes: why_it_works, styling_tip
```

- Uses current revision: No
- Reconstructs independently: Yes (hardcoded layout)
- Re-fetches: No
- Drops fields: all reasoning copy; shuffled item state

---

## 5. Reuse Matrix

| Capability | Recommendation | Style This | Build Outfit | Saved Board | Share/Export |
|------------|:--------------:|:----------:|:------------:|:-----------:|:------------:|
| `AhviOutfitBoardCard` | YES | YES | YES | NO | NO |
| `EditorialBoardCanvas` | YES | YES | YES | YES (via SavedBoardThumb) | NO |
| `EditorialBoardLayoutEngine` | YES | YES | YES | YES | **NO** (hardcoded) |
| `StyleBoardController` | NO | YES | YES | NO | NO |
| `BoardMutationBar` | NO | YES | YES | NO | NO |
| `OutfitActionBar` | YES | YES | YES | NO | — |
| `_transparentUrlFor()` | YES | YES | YES | NO | NO |
| `ShareableOutfitBoard` | YES | YES | YES | NO | — |
| `BoardLayoutEngine` (legacy) | NO | NO | NO | NO | NO |
| `StyleBoardBody` (legacy) | NO | NO | NO | NO | NO |
| `boardDataFromMap()` | NO | NO | NO | YES | NO |
| `extractSavedBoardImages()` | NO | NO | NO | YES | NO |

**Classification of partial rows:**

- `EditorialBoardCanvas` — *partially shared*: all surfaces except Share export use it; `_ShareCanvas` is an independent reimplementation.
- `EditorialBoardLayoutEngine` — *partially shared*: same note; hardcoded positions in `_ShareCanvas` duplicate its output at a fixed viewport.
- `StyleBoardController` — *partially shared*: only when board contract predicates pass (Style This, Build Outfit). Recommendation never gets a controller.
- `OutfitActionBar` — *partially shared*: used by active-board surfaces. Saved board has its own minimal share action.

---

## 6. Model / Field Mapping

| Backend/JSON field | Parsed into | Recommendation | Style This / Build Outfit | Saved Board | Share/Export |
|--------------------|-------------|:--------------:|:-------------------------:|:-----------:|:------------:|
| `board_id` | `StyleBoardState.boardId` | parsed, unused | gate predicate `boardIdOk` | absent | absent |
| `revision` | `StyleBoardState.revision` | parsed, unused | `revisionOk`; sent in payload | absent | absent |
| `source_policy` | `StyleBoardState.sourcePolicy` | parsed, unused | gate + payload + validated in response | absent | absent |
| `scenario` | `StyleBoardState.scenario` | parsed, unused | validated unchanged in response | absent | absent |
| `board_items[].board_image_url` | `StyleBoardItem.boardImageUrl` | 1st priority | same | not checked | **not used** |
| `board_items[].transparent_image_url` | `StyleBoardItem.maskedUrl` | 2nd priority | same | 3rd priority in extractSavedBoardImages | **not used** |
| `board_items[].cutout_url` + `cutout_status=ready` | `StyleBoardItem.cutoutUrl` | 3rd priority | same | not checked | **not used** |
| `board_items[].image_url` (board_status=cutout_ready) | `StyleBoardItem.imageUrl` | 4th priority | same | fallback | **1st and only** |
| `board_items[].image_url` (itemId+source present) | `StyleBoardItem.imageUrl` | 5th priority | same | fallback | same |
| `board_items[].role` / `slot` | `StyleBoardItem.role` | `_roleFor()` | same | `boardItemRoleFromText()` | direct string |
| `board_items[].locked` | `StyleBoardItem.locked` | not used | `toggleLock()` initial state | not applicable | not applicable |
| `board_items[].position.{x,y,w,h}` | `BoardPosition` | used if `isUsable` | same; validated on locked items | not used | not used |
| `board_items[].item_id` / `wardrobe_item_id` / `$id` | `StyleBoardItem.itemId` | not needed | `isLockable` gate; in locked_items payload | not used | not used |
| `board_items[].source` | `StyleBoardItem.source` | skip-if-private | `isLockable` gate; policy validation | not checked | not used |
| `board_items[].accessory_type` | `StyleBoardItem.accessoryType` | passed through | sent in board_items payload | not used | not used |
| `board_items[].board_role` | `StyleBoardItem.boardRole` | display label | same | not used | not used |
| `story.{summary,why,tip,role}` | `BoardStory` → `StyleBoardData.story` | shown | same | **not parsed from Appwrite doc** | **excluded** |
| `title` / `archetype` / `direction_name` | `OutfitBoardModel.title` | OutfitContextStrip | same | separate Appwrite chain | share image |
| `occasion` | `StyleBoardData.occasion` | chip label | same | normalized to 5 buckets at save | chip label |
| `why_it_works` / `whyItWorks` | `StyleBoardData.whyItWorks` | BoardStoryExpandable | same | detail sheet | **excluded** |
| `styling_tip` / `stylingTip` | `StyleBoardData.stylingTip` | BoardStoryExpandable | same | detail sheet | **excluded** |

**Aliases supported:** `board_items` / `boardItems` / `items` / `pieces` for item list; `why_it_works` / `whyItWorks`; `styling_tip` / `stylingTip`; `item_id` / `wardrobe_item_id` / `$id`.

**Fields dropped before Share/Export:** `board_id`, `revision`, `source_policy`, `scenario`, `story.*`, `why_it_works`, `styling_tip`, `board_image_url`, `masked_url`, `cutout_url` — share only reads `image_url`.

**Fields dropped at Appwrite save:** `board_id`, `revision`, `source_policy`, `story.*` — not written to saved board document. Saved boards can never be shuffled.

---

## 7. Image Resolver Findings

### Priority chains

**`_transparentUrlFor()` in `ahvi_outfit_board_card.dart`** (Recommendation, Style This, Build Outfit):
1. `board_items[].board_image_url`
2. `board_items[].transparent_image_url`
3. `board_items[].cutout_url` (only if `cutout_status == 'ready'`)
4. `board_items[].image_url` (only if `board_status == 'cutout_ready'`)
5. `board_items[].image_url` (only if item has non-empty `itemId` AND `source`)
6. → `null` + logs `AHVI_BOARD_ASSET_SKIPPED_NON_TRANSPARENT`; item omitted from layout

**`extractSavedBoardImages()` in `saved_board_images.dart`** (Saved Board):
1. `normalized_url` / `normalizedUrl`
2. `masked_url` / `maskedUrl`
3. `imageUrl` / `image_url` / `url` / `thumbnailUrl`
4. Doc-level `thumbnailUrl` / `imageUrl`

**`_shareItems()` in `ahvi_outfit_board_card.dart`** (Share export):
1. `item['image_url']` only — no fallback, no transparent priority

**`_selectTransparentUrl()` in `board_renderer.dart`** (dead code, legacy):
Priority similar to `_transparentUrlFor()` but falls through to `item.imageUrl` rather than null.

**`getWardrobeItems()` in `appwrite_service.dart`** (wardrobe hydration):
1. `normalized_url`
2. `masked_url`
3. `image_url`
4. `raw_url`

### BoxFit per surface

| Surface | BoxFit |
|---------|--------|
| `EditorialBoardItem` (new renderer) | `BoxFit.contain` |
| `SavedBoardThumb` single-image fallback | `BoxFit.cover` |
| `_ShareGarment` (share export) | `BoxFit.contain` |
| `CollageTile` in `editorial_collage.dart` | `BoxFit.cover` |

### White/pale rectangle root cause

`EditorialBoardItem` renders at full slot size with `BoxFit.contain`. If the backend transparent PNG has large empty margins (common in cutout assets), the actual garment occupies only a fraction of the contained image, appearing small inside the allocated slot. The `visualScale` multiplier partially compensates but cannot correct a 2× margin artifact.

If `_transparentUrlFor()` returns `null`, the item is **entirely skipped** — the layout engine has reserved space for it, producing a dead gap at that position.

### Cropped-jeans root cause

The `bottom` slot in `classicThreePlusAccessory` uses `editorialAlignmentForRole(bottom) = Alignment.topCenter`. The waistband anchors to the top of the allocated rect. If the transparent PNG contains full-length trousers AND the allocated height is smaller than the full AR requires, `BoxFit.contain` letterboxes at the **bottom**, clipping the hem. `visualScale = 1.10×` for `bottom` zooms inward, compressing the remaining visible height further.

**Evidence:** `editorial_board_layout_engine.dart` `bottom` placement at `y=0.40h, width=0.50w` with AR=1.55 yields height = `0.50w / 1.55`. At canvas 360×450 that is height ≈ 116 px for a slot whose visible content starts at `y=180`. A full-leg trouser at AR 0.65 (wide-crop image) will have its lower third letterboxed.

### Diagnostic coverage

| Tag | Present | Surfaces covered |
|-----|---------|-----------------|
| `AHVI_BOARD_ASSET_SKIPPED_NON_TRANSPARENT` | YES | Rec / Style This / Build Outfit |
| `AHVI_BOARD_RENDER_ASSET_SELECTION` | YES | Same |
| `AHVI_BOARD_CONTRACT_CHECK` | YES | Same |
| `AHVI_BOARD_LAYOUT ...` | YES (debug) | Same |
| `AHVI_IMAGE_SELECTION_DECISION` | **ABSENT** | — |
| `AHVI_IMAGE_FIELD_COMPARE` | **ABSENT** | — |
| `AHVI_WARDROBE_IMAGE_RESOLVE` | **ABSENT** | — |
| `AHVI_BOARD_FIELD_COMPARE` | **ABSENT** | — |

Wardrobe image resolution has zero field-level logging.

---

## 8. Layout Findings

### `EditorialBoardLayoutEngine` (active)

**Template selection:**

| Condition | Template |
|-----------|----------|
| `dress != null` | `dressFocused` |
| top + bottom + footwear, `acc ≤ 2` | `classicThreePlusAccessory` |
| top + bottom + footwear, `acc > 2` | `accessoryHeavy` |
| any other non-empty combination | `generic` |
| no items | `empty` |

**Per-role aspect ratios:** top=1.18, bottom=1.55, dress=1.70, outerwear=1.35, footwear=0.62, accessory=1.05, unknown=1.20

**`classicThreePlusAccessory` placements (fractions of canvas):**

| Role | x | y | width |
|------|---|---|-------|
| top | 0.15w | 0.07h | 0.62w |
| bottom | 0.45w | 0.40h | 0.50w |
| footwear | 0.10w | 0.70h | 0.46w |

**Per-role visual scale and alignment:**

| Role | Scale | Alignment |
|------|-------|-----------|
| footwear | 1.38 | center |
| accessory | 1.16 | center |
| top | 1.15 | center |
| dress | 1.12 | center |
| outerwear | 1.12 | center |
| bottom | 1.10 | **topCenter** |
| unknown | 1.08 | center |

**Canvas:** 4:5 portrait. Safe zones: top 5%, sides 6%, bottom 10%.  
**Composition normalization:** sparse boards (coverage < 0.78w/0.74h) scaled up to 0.88w/0.86h; dense boards unchanged; max scale 1.18.

### `BoardLayoutEngine` (legacy, dead)

Status: code present, not mounted. Consumer `StyleBoardBody` is also dead. Both are candidates for deletion.

### `_ShareCanvas` (share export)

Hardcoded fractional positions with no call to `EditorialBoardLayoutEngine`. Scale constants differ from editorial: footwear=1.30, others=1.06. This produces a share PNG that does not match the live card for any composition.

---

## 9. Interaction-Mode Findings

### Mode derivation (all flows)

```
board contract predicates:
  boardIdOk:          board_id non-empty, not starting with 'outfit_card_'
  revisionOk:         revision > 0
  sourcePolicyOk:     source_policy in {'wardrobe','style_asset','mixed'}
  stableItemIdsOk:    all items have item_id / wardrobe_item_id / $id
  requestCarriedItemsOk: raw map non-empty on all items

supportsShuffle = ALL predicates pass
→ true  → StyleBoardController created, BoardMutationBar rendered
→ false → controller = null, BoardMutationBar absent (Recommendation mode)
```

The mode is not an explicit enum — it is inferred from `supportsShuffle` / `controller != null`. Style This and Build Outfit are distinguished only by `scenario` in the payload.

`failedContractPredicates` is computed and logged but **not surfaced to the user** in any toast or debug overlay.

### Legacy bypass

`StyleBoardBody` and `BoardLayoutEngine` have no lock/shuffle capability. They are dead code.

---

## 10. Save / Shuffle / Share Findings

| Stage | Source rendered / saved |
|-------|------------------------|
| Initial load | `_initialBoard` (parsed from direction) |
| After lock | `_currentBoard` getter: `_initialBoard` metadata + `controller.state.items` |
| During shuffle (loading) | `controller.state.items` with `isRegenerating=true` on unlocked slots |
| After shuffle success | `controller.state.items` (new backend items) |
| After `undo()` | `controller.state.items` (restored pre-shuffle snapshot) |
| **Save** | **`_saveItems()` reads ORIGINAL `direction['board_items']` — pre-shuffle** |
| **Share** | **`_shareBoardItems()` → same `_saveItems()` — pre-shuffle** |

**Confirmed bug:** A user who shuffles and taps Save will persist the original unshuffled items to Appwrite. `StyleBoardController.state.items` is never consulted during save. Zero tests cover this case.

**Share PNG reconstruction:** `ShareableOutfitBoard` is built from `_saveItems()` (original items) with hardcoded `_ShareCanvas` positions, not `EditorialBoardLayoutEngine`. The share image will differ both in item content (post-shuffle ignored) and in layout geometry.

**Test evidence:**
- `outfit_board_save_share_test.dart`: confirms `save` callback fires with `imageUrl` from original direction's first item — stale-save behaviour is present and untested.
- `style_board_lock_shuffle_test.dart`: "typed failure restores exact snapshot" confirms rollback works correctly.
- `ahvi_outfit_board_card_lock_shuffle_test.dart`: "same-board rebuild preserves locks" confirms controller state survives widget rebuild.

---

## 11. Title and Reasoning Hierarchy

### `AhviOutfitBoardCard` vertical layout (top → bottom)

```
1. OutfitContextStrip
     title: archetype > direction_name > title  (maxLines:1, ellipsis)
     occasion chip + adjective tags

2. EditorialBoardCanvas  (4:5 aspect)
     BoardStoryHeader (if story present):
       headline (story.summary or occasion)  (maxLines:1)
       summaryText                           (maxLines:1)

3. BoardMutationBar  (only if controller != null)
     Lock toggles + Shuffle button

4. OutfitActionBar
     Save | Shuffle | Like | Dislike | Share

5. BoardStoryExpandable  (collapsed by default)
     "Why this works" toggle
     Expanded: why, personalNote, occasionFit, tip
```

**Note:** `_shareBoundaryKey` RepaintBoundary wraps items 1+2 only. Items 3–5 are outside the share capture.

### `ShareableOutfitBoard` layout (share export)

```
1. AHVI branding
2. Title text
3. Occasion chip
4. _ShareCanvas (garments)
5. 'Styled on AHVI' footer
```

Reasoning copy (why_it_works, styling_tip) excluded.

### Reasoning text priority

| Getter | 1st | 2nd | 3rd |
|--------|-----|-----|-----|
| `whyText` | `story.why` | `whyItWorks` | — |
| `tipText` | `story.tip` | `stylingTip` | — |
| `summaryText` | `story.summary` | `whyItWorks` | `occasion` |

### `AhviOutfitBoardDetailSheet` reasoning order

1. `rationale` > `reason` > `why` > `short_note` > `why_it_works` > `styling_tip`
2. Pieces list from `board_items[].name`

---

## 12. Semantic Context Findings

### Occasion label priority chain

| Location | Resolution |
|----------|------------|
| `OutfitContextStrip` | `board.occasion` from `StyleBoardData.occasion` |
| `StyleBoardData.occasion` | direct from direction JSON `occasion` field |
| `StyleBoardData.roleLabel` | `boardRole ?? story?.role ?? occasion` |
| `StyleBoardData.summaryText` | `story?.summary ?? whyItWorks ?? occasion` |
| Appwrite save | `_savedBoardOccasionLabel()` normalizes to 5 canonical buckets |
| Share image | direct `occasion` from original direction |

### Mismatch origins

1. **Occasion normalization drift:** `_savedBoardOccasionLabel()` collapses raw occasions to 5 buckets (Party, Office, Vacation, Occasion, Everything Else). Board shows raw `'smart casual office'`; saved board shows `'Office'`.

2. **Title source divergence:** `OutfitBoardModel.fromPayload()` resolves `archetype > direction_name > title`. `SavedBoardCard` reads from Appwrite doc via a separate chain (`title / boardCategoryLabel / occasion`). After save, the displayed title may differ between the active card and the saved board card.

3. **Four role resolvers with different coverage:**
   - `board_role_resolver.dart`: `.contains()` substring match — missing 'palazzo', 'jogger', 'tunic', 'cami', 'earring', 'headwear'
   - `BoardLayoutEngine.resolveRole()`: regex word-boundary match — more complete
   - `boardItemRoleFromText()` in `board_models.dart`: switch/case — covers earring/headwear/necklace
   - `_roleFor()` + `_mapItemRole()` in `ahvi_outfit_board_card.dart`: composite, used in live path

   The same backend category string (`'palazzo trouser'`) can resolve to different `BoardItemRole` values depending on which resolver is invoked.

---

## 13. Existing Test Coverage

| Test file | Behaviour | Quality | Missing |
|-----------|-----------|---------|---------|
| `visual_board_85_phase1_test.dart` | Board render, shuffle, density, golden PNG | Good | Failed `_validate()` paths |
| `ahvi_outfit_board_card_lock_shuffle_test.dart` | Multi-lock, revision conflict, loading, undo, policy | Good | Save reading stale items after shuffle |
| `style_board_lock_shuffle_test.dart` | Payload fields, policy validation, undo, source violation | Good | `accessory_type` end-to-end in payload |
| `style_board_shuffle_contract_test.dart` | Revision/source_policy in payload, board_id gates shuffle | Thin (3 tests) | Most contract edge cases |
| `style_board_visual_density_test.dart` | Visual scale bounds, sparse enlargement, dense unchanged | Good | `editorialAlignmentForRole` + BoxFit interaction |
| `board_story_test.dart` | `BoardStory.fromJson`, getter priority, null story | Good | `summaryText` when all three sources absent |
| `outfit_board_save_share_test.dart` | Save fires, double-tap prevention, share fallback | Medium | **Save does not use shuffled items (undetected bug)** |
| `shareable_outfit_board_test.dart` | Opaque background, branding, no reasoning, PNG bytes | Good | Share items matching post-shuffle state |

**Uncovered scenarios:**
- Stale save after shuffle (zero tests)
- Role resolver disagreement across four paths (zero tests)
- `extractSavedBoardImages` URL priority order (zero tests)
- `boardDataFromMap` missing contract fields (zero tests)
- `_ShareCanvas` hardcoded positions vs `EditorialBoardLayoutEngine` output (zero pixel tests)
- Wardrobe image resolution (`getWardrobeItems`) URL priority (zero tests)
- `_roleFor()` hero → dress re-detection path (zero tests)

---

## 14. Confirmed Defects

| # | Severity | Description | Location |
|---|----------|-------------|----------|
| D1 | HIGH | Save reads original pre-shuffle direction items, not `controller.state.items`. A user who shuffles then saves persists the wrong outfit. | `ahvi_outfit_board_card.dart` `_saveItems()` |
| D2 | HIGH | Share export (`ShareableOutfitBoard`) reads same stale items. Share PNG does not reflect current shuffled state. | `ahvi_outfit_board_card.dart` `_shareBoardItems()` |
| D3 | MEDIUM | `_ShareCanvas` uses hardcoded fractional positions; layout differs from `EditorialBoardLayoutEngine` for every composition. | `shareable_outfit_board.dart` `_ShareCanvas` |
| D4 | MEDIUM | Four role resolvers with different category coverage — same backend string can produce different `BoardItemRole` values. | `board_role_resolver.dart`, `board_renderer.dart`, `board_models.dart`, `ahvi_outfit_board_card.dart` |
| D5 | MEDIUM | Bottom item `topCenter` alignment + `BoxFit.contain` clips trouser hem. `visualScale=1.10` worsens it. | `editorial_board_renderer.dart` `editorialAlignmentForRole(bottom)` |
| D6 | LOW | `extractSavedBoardImages` does not check `board_image_url` or `cutout_url` — saved boards display lower-quality images than live boards. | `saved_board_images.dart` |
| D7 | LOW | Three diagnostic tags expected by monitoring (`AHVI_IMAGE_SELECTION_DECISION`, `AHVI_IMAGE_FIELD_COMPARE`, `AHVI_WARDROBE_IMAGE_RESOLVE`) are absent. | codebase-wide |
| D8 | LOW | `failedContractPredicates` computed but not surfaced in UI — users cannot distinguish "shuffle unavailable" from "board loaded". | `ahvi_outfit_board_card.dart` |

---

## 15. Suspected Defects (Requiring Runtime Evidence)

| # | Description | Evidence needed |
|---|-------------|-----------------|
| S1 | Pale rectangles on board may be caused by `_transparentUrlFor()` returning null for items with only `image_url` (no board_status or itemId+source). If so, visible gaps are gaps, not rectangles — but opaque fallback rendering might be filling them. | Run with `AHVI_BOARD_ASSET_SKIPPED_NON_TRANSPARENT` log and compare slot count to visible items. |
| S2 | Small shoe image may be partly caused by backend providing a wide-AR shoe PNG where the shoe occupies only the bottom third of the canvas. `BoxFit.contain` + AR=0.62 slot may still leave excess vertical space even at 1.38× scale. | Compare `board_image_url` dimensions vs slot dimensions at runtime. |
| S3 | Occasion label mismatch ("daily" shown on a "coffee date" request) may be parser falling through to `occasion` default before backend's `occasion` field arrives. | Confirm by logging `direction.occasion` at parse time. |
| S4 | `BoardLayoutEngine.resolveRole()` and `_roleFor()` may produce different roles for 'belt' (accessory vs unknown). Would cause belt to be excluded or misplaced in live board. | Add `AHVI_ROLE_RESOLVE` log to `_roleFor()` and compare against `board_role_resolver.dart`. |

---

## 16. Minimal Beta Recommendation (Option 1)

**Fix before Meghna's APK. Blast radius: small. 3 files, ~45 lines.**

### Fix D1 + D2: Save/Share using shuffled items

In `ahvi_outfit_board_card.dart`, `_saveItems()`:
```dart
// Current (stale):
final raw = direction['board_items'] ?? direction['boardItems'] ?? direction['items'];

// Fix:
final controllerItems = _controller?.state.items;
if (controllerItems != null && controllerItems.isNotEmpty) {
  return controllerItems.map((i) => i.toSaveJson()).toList();
}
final raw = direction['board_items'] ?? direction['boardItems'] ?? direction['items'];
```

Requires `StyleBoardItem.toSaveJson()` to emit the same fields as the original direction item (at minimum: `image_url`, `name`, `role`, `item_id`, `source`).

### Add regression test

In `outfit_board_save_share_test.dart`, add:
```dart
// After one shuffle, saved items should match the shuffled state, not the original.
```

### Add AHVI_IMAGE_SELECTION_DECISION log

In `_transparentUrlFor()`, log the selected URL and which priority chain branch was taken. Two lines.

**Files changed:** `ahvi_outfit_board_card.dart`, `style_board_state.dart` (if `toSaveJson` added there), `outfit_board_save_share_test.dart`.

---

## 17. Post-Beta Architecture Recommendation

**Sprint after beta: execute in order.**

### Step 1 — Single role resolver (Option 2 partial)

Merge `board_role_resolver.dart`, `BoardLayoutEngine.resolveRole()`, and `boardItemRoleFromText()` into one `BoardItemRoleResolver` class. Expand coverage to include 'palazzo', 'jogger', 'tunic', 'cami', 'earring', 'headwear'. Replace all four call sites. Blast radius: medium (5 files, ~120 lines). Eliminates D4.

### Step 2 — Share canvas alignment (Option 3 targeted)

Replace `_ShareCanvas` hardcoded positions with a call to `EditorialBoardLayoutEngine.resolve()`. Pass `controller?.state.items ?? _initialBoard.items`. Blast radius: small (2 files, ~80 lines). Eliminates D2 partial + D3.

### Step 3 — Delete legacy code

Delete `board_renderer.dart` (`StyleBoardBody`), `board_layout_engine.dart` (`BoardLayoutEngine`). Remove `_selectTransparentUrl()` in the deleted file. Blast radius: small (2 files deleted). Eliminates dead code. Verify no test references them.

### Step 4 — Add missing diagnostics

Add `AHVI_IMAGE_SELECTION_DECISION`, `AHVI_IMAGE_FIELD_COMPARE`, `AHVI_WARDROBE_IMAGE_RESOLVE`. Blast radius: small (3 files). Eliminates D7.

### Defer

- Full shared-board model convergence with Appwrite persistence of `board_id`/`revision` — large blast radius, requires Appwrite schema change, post-beta.
- `extractSavedBoardImages` URL priority alignment with `_transparentUrlFor()` — medium, post-beta.

---

## 18. Proposed Commit Sequence

```
fix(style-board): read shuffled controller items in save and share
  - _saveItems() consults controller.state.items when present
  - _shareBoardItems() delegates to updated _saveItems()
  - StyleBoardItem.toSaveJson() added

test(style-board): confirm save and share use post-shuffle items
  - outfit_board_save_share_test.dart: new scenario

fix(style-board): add AHVI_IMAGE_SELECTION_DECISION diagnostic log

[post-beta]
refactor(style-board): consolidate role resolvers into BoardItemRoleResolver

refactor(style-board): route _ShareCanvas through EditorialBoardLayoutEngine

chore(style-board): delete legacy StyleBoardBody and BoardLayoutEngine
```

---

## 19. Files Likely to Change

| File | Reason |
|------|--------|
| `lib/feature/chat/widgets/blocks/visual_directions/ahvi_outfit_board_card.dart` | D1+D2 fix (`_saveItems`), D8 (predicate toast), AHVI_IMAGE_SELECTION_DECISION log |
| `lib/style_board/style_board_state.dart` or `board_models.dart` | `StyleBoardItem.toSaveJson()` |
| `test/outfit_board_save_share_test.dart` | D1+D2 regression test |
| `lib/feature/chat/widgets/blocks/visual_directions/shareable_outfit_board.dart` | D3 fix (post-beta) |
| `lib/style_board/board_role_resolver.dart` | D4 fix (post-beta), expanded coverage |
| `lib/style_board/board_models.dart` | D4 fix (post-beta), remove `boardItemRoleFromText` |
| `lib/style_board/board_renderer.dart` | Delete (post-beta) |
| `lib/style_board/board_layout_engine.dart` | Delete (post-beta) |
| `lib/style_board/editorial_board_renderer.dart` | D5 fix — `topCenter` → `center` for bottom (post-beta) |
| `lib/style_board/saved_board_images.dart` | Add `board_image_url` / `cutout_url` to URL chain (post-beta) |

---

## 20. Explicit NO-GO Items

The following must not happen before beta:

- Do not replace `AhviOutfitBoardCard` with a new renderer — it is already the canonical active-board renderer for all three surfaces.
- Do not introduce a new shared-board model or new Appwrite schema — post-beta only.
- Do not delete `StyleBoardBody` or `BoardLayoutEngine` before verifying no test imports them.
- Do not change `EditorialBoardLayoutEngine` template selection logic or role aspect ratios without golden-test coverage.
- Do not change the `bottom` alignment from `topCenter` to `center` in beta — test coverage of item positions does not exist and regression risk is high.
- Do not touch `source_policy`, `scenario`, or `revision` validation predicates — the shuffle contract is the only well-tested part of the flow.
- Do not add dependencies or run `flutter pub get`.
- Do not commit to or push `main` directly.

---

## Quick-Reference: Key Questions Answered

| Question | Answer |
|----------|--------|
| Does `AhviOutfitBoardCard` act as canonical active-board renderer? | **YES** — all three surfaces route through it |
| Do Style This and Build Outfit route into it when board_id and revision present? | **YES** — `supportsShuffle=true` creates `StyleBoardController`; same widget |
| Is only the shared/export board using a legacy canvas? | **YES** — `_ShareCanvas` in `shareable_outfit_board.dart` |
| Are visual issues primarily asset selection and layout sizing? | **MOSTLY YES** — plus the stale-save bug which is the only correctness issue |
| Verdict | **B-: Partially canonical** |
| Board renderers | 3: `EditorialBoardCanvas` (active), `SavedBoardThumb` (delegates), `_ShareCanvas` (independent) |
| Layout engines | 2: `EditorialBoardLayoutEngine` (active), `BoardLayoutEngine` (dead) |
| Asset resolver paths | 5: `_transparentUrlFor`, `extractSavedBoardImages`, `_saveItems`, `_selectTransparentUrl` (dead), `getWardrobeItems` |
| Recommendation/Style This/Build Outfit share same card? | **YES** |
| Shared Board uses same canvas? | **NO** |
| Recommended beta strategy | **Option 1: fix `_saveItems()` to read controller state, add regression test, add image selection log** |
