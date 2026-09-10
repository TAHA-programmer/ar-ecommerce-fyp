/// The production Virtual Try-On (VTO) asset contract for a single product
/// (Phase 9.3 Stage 2 — data contract only; no runtime behaviour is wired to
/// this yet).
///
/// Deliberately shaped as the 2-D-image sibling of [ProductArMetadata]:
///   * one immutable typed value object, parsed from / serialised to **flat
///     `vto*` keys** on the `products/{id}` Firestore document (the `arModel*`
///     / `arScale*` keys set the precedent);
///   * [fromProductData] never throws — a document with no VTO signal yields
///     `null` (the product simply has no try-on config, a normal state); a
///     document with a *present but incomplete/broken* config yields a
///     non-`null` object whose [isRenderable] is `false`, so a future customer
///     gate refuses it rather than guessing, and [validationIssues] explains
///     why for admin / diagnostics.
///
/// What it represents:
///   * [garmentCategory] — a closed set ({top, outerwear, dress, bottom}); this
///     is the only styling hint the later server-side call passes to the image
///     model. It is NOT a fit/size input.
///   * [garmentsByColor] — one [VtoGarmentAsset] per colour the product offers
///     (developer decision D6: one asset per colour). Keyed by
///     `ProductColorOption.name` (`'blue'`, `'beige'`, …).
///   * [garmentDefault] — a single product-wide asset, permitted by D6 only
///     when the colourways are genuinely visually identical; used to resolve
///     any colour that has no dedicated entry.
///
/// What it deliberately does NOT hold:
///   * The enabled/disabled switch — that is [ProductModel.vtoDisabled], exactly
///     mirroring [ProductModel.arModelDisabled], so deleting the config clears
///     the switch with it (`copyWith(clearVtoMetadata: true)`).
///   * The VTO model type (male / female) — already
///     [ProductModel.vtoModelType]; one source of truth, no duplication.
///   * Any provider / API key / endpoint / credential. The image provider is a
///     **server-side deployment concern** (a Phase 9.4 Cloud Function holds the
///     credential and the provider binding). The Stage-1 provider decision (D2,
///     2026-09-10) is recorded in [selectedProvider] / [selectedProviderModel]
///     as documentation + a test anchor only — it is never written to Firestore
///     and no client code depends on it.
class ProductVtoMetadata {
  /// The current metadata-shape contract identifier. Bump when the wire shape
  /// changes in a way that invalidates stored documents.
  static const String currentContract = 'twin-ar/vto-contract-9.3';

  /// The closed set of garment categories the try-on flow understands. Passed
  /// to the later server-side call as a styling hint only.
  static const Set<String> supportedGarmentCategories = {
    'top',
    'outerwear',
    'dress',
    'bottom',
  };

  /// **Reference only.** The Phase 9.3 Stage-1-selected image provider
  /// (developer decision D2, 2026-09-10, `21_PHASE_9_3_VIRTUAL_TRYON_TRACKER.md`
  /// §17.7). Recorded here so the contract documents the choice and a test can
  /// assert it does not silently drift. **Never serialised to Firestore, never
  /// embedded in a client build path, never a runtime dependency.** The actual
  /// invocation is server-side (Phase 9.4) with the credential in Secret
  /// Manager.
  static const String selectedProvider = 'gemini';
  static const String selectedProviderModel = 'gemini-2.5-flash-image';

  /// Firestore key the mapper writes the enabled/disabled switch under. The
  /// switch itself is [ProductModel.vtoDisabled] (mirrors `arModelDisabled`).
  static const String disabledFirestoreKey = 'vtoDisabled';

  final String garmentCategory;

  /// `ProductColorOption.name` -> the garment asset for that colour.
  final Map<String, VtoGarmentAsset> garmentsByColor;

  /// A single asset used for any colour with no dedicated [garmentsByColor]
  /// entry, or `null`.
  final VtoGarmentAsset? garmentDefault;

  final String contract;

  /// Colour keys that were present in the `vtoGarments` Firestore map but whose
  /// value could not be parsed to an asset (not a map, or a map with no
  /// `storagePath`). Populated **only** by [fromProductData] — a malformed
  /// entry is never silently dropped: it forces [isRenderable] to `false` and
  /// shows a diagnosable [issues] line. Always empty for a hand-constructed
  /// instance. `'(vtoGarments is not a map)'` appears here when the whole field
  /// is the wrong type.
  final List<String> malformedGarmentSlots;

  /// `true` when `vtoGarmentDefault` was present in Firestore but unparseable.
  /// Same fail-closed / diagnosable treatment as [malformedGarmentSlots].
  final bool garmentDefaultMalformed;

  const ProductVtoMetadata({
    required this.garmentCategory,
    this.garmentsByColor = const {},
    this.garmentDefault,
    this.contract = currentContract,
    this.malformedGarmentSlots = const [],
    this.garmentDefaultMalformed = false,
  });

  // ── Firestore keys ───────────────────────────────────────────────────────
  static const _kCategory = 'vtoGarmentCategory';
  static const _kContract = 'vtoContract';
  static const _kGarments = 'vtoGarments';
  static const _kDefault = 'vtoGarmentDefault';

  /// The `vto*` fields to merge into a `products/{id}` Firestore map. The
  /// enabled/disabled switch is written separately by the mapper (only when
  /// `true`), exactly like `arModelDisabled`.
  Map<String, dynamic> toFirestoreFields() => {
    _kCategory: garmentCategory,
    _kContract: contract,
    _kGarments: {
      for (final e in garmentsByColor.entries) e.key: e.value.toMap(),
    },
    if (garmentDefault != null) _kDefault: garmentDefault!.toMap(),
  };

  static String _str(Object? v) => v is String ? v.trim() : '';

  /// Any `vto*` key at all (even null-valued) counts as a signal — so an
  /// isolated / leftover field (`vtoContract` on its own, a stray `vtoDisabled`,
  /// a malformed `vtoGarments`) produces a **diagnosable, non-renderable**
  /// object rather than being silently treated as "no Virtual Try-On".
  static bool _hasAnyVtoSignal(Map<String, dynamic> data) =>
      data.containsKey(_kCategory) ||
      data.containsKey(_kContract) ||
      data.containsKey(_kGarments) ||
      data.containsKey(_kDefault) ||
      data.containsKey(disabledFirestoreKey);

  /// Parse from a whole `products/{id}` data map. Returns `null` **only** when
  /// the product carries no `vto*` signal at all. Otherwise returns an object
  /// that may still be non-[isRenderable] — the caller decides. Never throws;
  /// never silently drops or normalises a malformed field.
  static ProductVtoMetadata? fromProductData(Map<String, dynamic> data) {
    if (!_hasAnyVtoSignal(data)) return null;

    final byColor = <String, VtoGarmentAsset>{};
    final malformed = <String>[];
    final rawGarments = data[_kGarments];
    if (rawGarments is Map) {
      rawGarments.forEach((k, v) {
        final key = k.toString();
        final asset = VtoGarmentAsset.fromMap(v);
        if (asset != null) {
          byColor[key] = asset;
        } else if (v != null) {
          // present but unparseable (not a map, or a map with no storagePath)
          malformed.add(key);
        }
      });
    } else if (rawGarments != null) {
      malformed.add('(vtoGarments is not a map)');
    }

    final rawDefault = data[_kDefault];
    final parsedDefault = VtoGarmentAsset.fromMap(rawDefault);

    return ProductVtoMetadata(
      // Kept verbatim (lower-cased) — an unsupported value stays honestly
      // non-renderable rather than being silently coerced.
      garmentCategory: _str(data[_kCategory]).toLowerCase(),
      garmentsByColor: Map.unmodifiable(byColor),
      garmentDefault: parsedDefault,
      contract: _str(data[_kContract]),
      malformedGarmentSlots: List.unmodifiable(malformed),
      garmentDefaultMalformed: parsedDefault == null && rawDefault != null,
    );
  }

  /// Human-readable reasons the VTO metadata in [data] is not usable, or `[]`
  /// when it is fully valid. `['no Virtual Try-On metadata']` when there is no
  /// config at all. Pure — safe to call from anywhere.
  static List<String> validationIssues(Map<String, dynamic>? data) {
    if (data == null || !_hasAnyVtoSignal(data)) {
      return const ['no Virtual Try-On metadata'];
    }
    final parsed = fromProductData(data);
    return parsed == null
        ? const ['no Virtual Try-On metadata']
        : parsed.issues;
  }

  /// `true` only when the contract id, garment category and every garment asset
  /// (per-colour + default) are all well-formed, at least one garment asset
  /// exists, and nothing in the source data was malformed. **Id-agnostic** — a
  /// customer eligibility path must use [isRenderableForProduct] instead, which
  /// also verifies every stored path actually belongs to the product.
  bool get isRenderable => issues.isEmpty;

  /// [isRenderable] **and** every stored asset path belongs to [productId]
  /// (`assetsBelongToProduct`). This is the single gate a customer-facing
  /// eligibility check must use — [isRenderable] alone would let a well-formed
  /// but cross-product Storage path (`products/OTHER/vto/…`) look launchable.
  bool isRenderableForProduct(String productId) =>
      isRenderable && assetsBelongToProduct(productId);

  List<String> get issues {
    final out = <String>[];
    if (contract.isEmpty) {
      out.add('vto contract id is missing');
    }
    if (!supportedGarmentCategories.contains(garmentCategory)) {
      out.add(
        'garment category must be one of '
        '${supportedGarmentCategories.join(", ")} (got "$garmentCategory")',
      );
    }
    if (garmentsByColor.isEmpty &&
        garmentDefault == null &&
        malformedGarmentSlots.isEmpty &&
        !garmentDefaultMalformed) {
      out.add(
        'no garment asset configured (need a per-colour asset or a default)',
      );
    }
    for (final slot in malformedGarmentSlots) {
      out.add(
        'garment "$slot": entry is missing or malformed '
        '(expected a map with a storagePath)',
      );
    }
    if (garmentDefaultMalformed) {
      out.add(
        'default garment: entry is missing or malformed '
        '(expected a map with a storagePath)',
      );
    }
    for (final entry in garmentsByColor.entries) {
      for (final i in entry.value.issues) {
        out.add('garment "${entry.key}": $i');
      }
    }
    final d = garmentDefault;
    if (d != null) {
      for (final i in d.issues) {
        out.add('default garment: $i');
      }
    }
    return out;
  }

  /// The garment asset for [colorKey] (a `ProductColorOption.name`), falling
  /// back to [garmentDefault]. **Fail-closed:** returns `null` when the resolved
  /// asset is itself not [VtoGarmentAsset.isRenderable], so a customer flow can
  /// never be handed a broken reference.
  VtoGarmentAsset? resolveGarment(String? colorKey) {
    final a =
        (colorKey != null ? garmentsByColor[colorKey] : null) ?? garmentDefault;
    return (a != null && a.isRenderable) ? a : null;
  }

  /// Colour keys in [garmentsByColor] that are not a known `ProductColorOption`
  /// name — a diagnostic for admin (a typo'd key silently fails to resolve for
  /// that colour). Not part of [isRenderable]; the [ProductModel]-level gate
  /// catches the real consequence (the colour won't resolve).
  Iterable<String> unknownColorKeys(Set<String> knownColorNames) =>
      garmentsByColor.keys.where((k) => !knownColorNames.contains(k));

  /// Defence-in-depth: every stored asset path is exactly the path the Admin
  /// upload flow would derive from this product's id + the asset's own slot
  /// (`{colorKey}` or `default`) + version. Guards against ever serving one
  /// product's session with another product's Storage object after a migration
  /// / hand-edit. `false` when there are no assets at all.
  bool assetsBelongToProduct(String productId) {
    var any = false;
    for (final e in garmentsByColor.entries) {
      any = true;
      if (!e.value.matchesExpectedPath(productId, e.key)) return false;
    }
    final d = garmentDefault;
    if (d != null) {
      any = true;
      if (!d.matchesExpectedPath(productId, 'default')) return false;
    }
    return any;
  }

  /// The stored Storage object paths that are **provably [productId]'s own** —
  /// each is *exactly*
  /// `products/{productId}/vto/garment-{slot}-v{version}.{jpg|png}` for its own
  /// slot (`{colorKey}` or `default`). A cross-product path, a hand-edited
  /// path, or a wrong-version path is **excluded**. A caller that only ever
  /// passes objects from this set to Storage (download / delete) can therefore
  /// never read or delete another product's object, even from corrupted
  /// metadata. Never throws.
  Set<String> ownedAssetPaths(String productId) {
    final out = <String>{};
    for (final e in garmentsByColor.entries) {
      if (e.value.matchesExpectedPath(productId, e.key)) {
        out.add(e.value.storagePath);
      }
    }
    final d = garmentDefault;
    if (d != null && d.matchesExpectedPath(productId, 'default')) {
      out.add(d.storagePath);
    }
    return out;
  }

  /// `true` when at least one stored asset path is **not** its own expected
  /// per-slot path for [productId] (a cross-product / hand-edited / wrong-slot /
  /// wrong-version path). A cleanup, preview or delete caller should surface
  /// this as an honest "one or more stored paths look foreign — left untouched
  /// for manual review" diagnostic and never issue a Storage call for it.
  bool hasForeignAssetPath(String productId) {
    for (final e in garmentsByColor.entries) {
      if (!e.value.matchesExpectedPath(productId, e.key)) return true;
    }
    final d = garmentDefault;
    if (d != null && !d.matchesExpectedPath(productId, 'default')) return true;
    return false;
  }

  ProductVtoMetadata copyWith({
    String? garmentCategory,
    Map<String, VtoGarmentAsset>? garmentsByColor,
    VtoGarmentAsset? garmentDefault,
    String? contract,
    bool clearGarmentDefault = false,
  }) => ProductVtoMetadata(
    garmentCategory: garmentCategory ?? this.garmentCategory,
    garmentsByColor: garmentsByColor ?? this.garmentsByColor,
    garmentDefault: clearGarmentDefault
        ? null
        : (garmentDefault ?? this.garmentDefault),
    contract: contract ?? this.contract,
    // Parse artifacts carried verbatim so `a.copyWith() == a`; a deliberate
    // edit that supplies a fresh `garmentsByColor` supersedes the stale slots
    // on the next `fromProductData` round anyway.
    malformedGarmentSlots: malformedGarmentSlots,
    garmentDefaultMalformed: garmentDefaultMalformed,
  );

  @override
  bool operator ==(Object other) =>
      other is ProductVtoMetadata &&
      other.garmentCategory == garmentCategory &&
      other.contract == contract &&
      other.garmentDefault == garmentDefault &&
      other.garmentDefaultMalformed == garmentDefaultMalformed &&
      _listEquals(other.malformedGarmentSlots, malformedGarmentSlots) &&
      _mapEquals(other.garmentsByColor, garmentsByColor);

  @override
  int get hashCode => Object.hash(
    garmentCategory,
    contract,
    garmentDefault,
    garmentDefaultMalformed,
    Object.hashAll(malformedGarmentSlots),
    Object.hashAllUnordered(
      garmentsByColor.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() =>
      'ProductVtoMetadata($garmentCategory, colours=${garmentsByColor.keys.toList()}, '
      'default=${garmentDefault != null}, malformed=$malformedGarmentSlots, '
      'renderable=$isRenderable)';

  static bool _mapEquals(
    Map<String, VtoGarmentAsset> a,
    Map<String, VtoGarmentAsset> b,
  ) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A single stored garment reference image for Virtual Try-On (one colour, or
/// the product-wide default). The 2-D sibling of the GLB fields inside
/// [ProductArMetadata].
class VtoGarmentAsset {
  /// Hard transport ceiling — a stored object above this is rejected
  /// (`isRenderable == false`). Mirrors the Room-AR `kArModelTransportMaxBytes`
  /// idea: the Admin *authoring* budget (Stage 3) will be lower.
  static const int maxBytes = 12 * 1024 * 1024;

  /// Below this longest-edge pixel size the asset still renders but is flagged
  /// for the admin ([isBelowRecommendedResolution]) — informed by the Stage-1
  /// finding that a 300×369 garment "worked but was poor". Not a hard reject.
  static const int recommendedMinLongEdgePx = 768;

  static const int _maxDimensionPx = 20000;

  static const Set<String> supportedContentTypes = {'image/jpeg', 'image/png'};

  /// Firebase Storage **object path** (never a download URL), e.g.
  /// `products/mens-oxford-shirt/vto/garment-blue-v1.jpg`.
  final String storagePath;

  /// Lowercase hex SHA-256 (64 chars) of the exact image bytes — verified on
  /// upload and again on re-download before the metadata is written (Stage 3).
  final String sha256;

  /// `image/jpeg` or `image/png`.
  final String contentType;

  final int byteSize;
  final int width;
  final int height;

  /// Monotonic per-slot version (`1`, `2`, …) for cache-busting and
  /// replace-without-disruption.
  final int version;

  const VtoGarmentAsset({
    required this.storagePath,
    required this.sha256,
    required this.contentType,
    required this.byteSize,
    required this.width,
    required this.height,
    this.version = 1,
  });

  static const _kPath = 'storagePath';
  static const _kSha = 'sha256';
  static const _kType = 'contentType';
  static const _kBytes = 'byteSize';
  static const _kWidth = 'width';
  static const _kHeight = 'height';
  static const _kVersion = 'version';

  Map<String, dynamic> toMap() => {
    _kPath: storagePath,
    _kSha: sha256,
    _kType: contentType,
    _kBytes: byteSize,
    _kWidth: width,
    _kHeight: height,
    _kVersion: version,
  };

  static String _str(Object? v) => v is String ? v.trim() : '';

  /// A **strict** integer read: an `int`, or a `double` that is finite and
  /// whole (`2.0`, since Firestore may store an integer as a double). Anything
  /// else — a string, a non-whole `2.7`, `NaN`, `null` — becomes `-1`, which
  /// every downstream check (`> 0`, `>= 1`) rejects. Nothing is silently
  /// truncated or coerced.
  static int _strictInt(Object? v) {
    if (v is int) return v;
    if (v is double && v.isFinite && v == v.roundToDouble()) return v.toInt();
    return -1;
  }

  /// Parse one asset map. Returns `null` when [raw] is not a map or carries no
  /// [storagePath] at all (that slot simply has no asset — the caller decides
  /// whether that is "absent" or "malformed"). A present-but-broken map yields
  /// a non-`null`, non-[isRenderable] object with populated [issues]. Never
  /// throws.
  static VtoGarmentAsset? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.map((k, v) => MapEntry(k.toString(), v));
    if (_str(map[_kPath]).isEmpty) return null;
    return VtoGarmentAsset(
      storagePath: _str(map[_kPath]),
      // Kept verbatim — the contract requires lowercase hex, so a mixed-case
      // value is honestly non-renderable.
      sha256: _str(map[_kSha]),
      contentType: _str(map[_kType]).toLowerCase(),
      byteSize: _strictInt(map[_kBytes]),
      width: _strictInt(map[_kWidth]),
      height: _strictInt(map[_kHeight]),
      version: _strictInt(map[_kVersion]),
    );
  }

  static final RegExp _sha256Re = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _driveLetterRe = RegExp(r'^[A-Za-z]:');

  bool get isRenderable => issues.isEmpty;

  List<String> get issues {
    final out = <String>[];
    final path = storagePath;
    if (path.isEmpty) {
      out.add('storage path is empty');
    } else {
      if (path.startsWith('http://') || path.startsWith('https://')) {
        out.add('storage path is a URL, not a Storage object path');
      }
      if (path.contains('\\') || _driveLetterRe.hasMatch(path)) {
        out.add('storage path looks like a Windows path');
      }
      if (path.startsWith('assets/') ||
          path.startsWith('flutter_assets/') ||
          path.startsWith('/')) {
        out.add('storage path looks like a bundled/absolute asset path');
      }
      if (path.contains('?')) {
        out.add('storage path carries a query string (signed URL?)');
      }
      if (!path.contains('/vto/')) {
        out.add('storage path is not under a product /vto/ folder');
      }
      final lower = path.toLowerCase();
      if (!(lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.png'))) {
        out.add('storage path does not end in .jpg/.jpeg/.png');
      }
    }

    if (!supportedContentTypes.contains(contentType)) {
      out.add(
        'contentType must be image/jpeg or image/png (got "$contentType")',
      );
    } else {
      final lower = storagePath.toLowerCase();
      final extPng = lower.endsWith('.png');
      final extJpg = lower.endsWith('.jpg') || lower.endsWith('.jpeg');
      if (contentType == 'image/png' && !extPng) {
        out.add('contentType image/png but path is not .png');
      }
      if (contentType == 'image/jpeg' && !extJpg) {
        out.add('contentType image/jpeg but path is not .jpg/.jpeg');
      }
    }

    if (!_sha256Re.hasMatch(sha256)) {
      out.add('sha256 must be 64 lowercase hex characters');
    }
    if (byteSize <= 0) {
      out.add('byteSize must be a whole number > 0');
    } else if (byteSize > maxBytes) {
      out.add('byteSize exceeds the ${maxBytes ~/ (1024 * 1024)} MiB ceiling');
    }
    if (width <= 0 || width > _maxDimensionPx) {
      out.add('width must be a whole number in 1..$_maxDimensionPx');
    }
    if (height <= 0 || height > _maxDimensionPx) {
      out.add('height must be a whole number in 1..$_maxDimensionPx');
    }
    if (version < 1) {
      out.add('version must be a whole number >= 1');
    }
    return out;
  }

  /// `true` when the longest edge is under [recommendedMinLongEdgePx] — a
  /// non-blocking admin flag, not part of [isRenderable].
  bool get isBelowRecommendedResolution {
    if (width <= 0 || height <= 0) return true;
    return (width >= height ? width : height) < recommendedMinLongEdgePx;
  }

  String get fileExtension => contentType == 'image/png' ? 'png' : 'jpg';

  /// `true` only when [storagePath] is exactly
  /// `products/{productId}/vto/garment-{slot}-v{version}.{jpg|png}` — where
  /// [slot] is a `ProductColorOption.name` or the literal `default`.
  bool matchesExpectedPath(String productId, String slot) =>
      storagePath ==
      'products/$productId/vto/garment-$slot-v$version.$fileExtension';

  VtoGarmentAsset copyWith({
    String? storagePath,
    String? sha256,
    String? contentType,
    int? byteSize,
    int? width,
    int? height,
    int? version,
  }) => VtoGarmentAsset(
    storagePath: storagePath ?? this.storagePath,
    sha256: sha256 ?? this.sha256,
    contentType: contentType ?? this.contentType,
    byteSize: byteSize ?? this.byteSize,
    width: width ?? this.width,
    height: height ?? this.height,
    version: version ?? this.version,
  );

  @override
  bool operator ==(Object other) =>
      other is VtoGarmentAsset &&
      other.storagePath == storagePath &&
      other.sha256 == sha256 &&
      other.contentType == contentType &&
      other.byteSize == byteSize &&
      other.width == width &&
      other.height == height &&
      other.version == version;

  @override
  int get hashCode => Object.hash(
    storagePath,
    sha256,
    contentType,
    byteSize,
    width,
    height,
    version,
  );

  @override
  String toString() =>
      'VtoGarmentAsset($storagePath v$version $contentType ${width}x$height '
      '${byteSize}B renderable=$isRenderable)';
}
