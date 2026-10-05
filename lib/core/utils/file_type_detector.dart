import 'dart:typed_data';

/// Broad classification of a file the app can show or process.
enum AppFileKind { image, pdf, other }

/// Result of inspecting a file's name and (when available) its header bytes.
class DetectedFileType {
  const DetectedFileType({
    required this.kind,
    required this.extension,
    required this.mimeType,
    this.imageFormat,
  });

  const DetectedFileType.unknown()
      : kind = AppFileKind.other,
        extension = '',
        mimeType = 'application/octet-stream',
        imageFormat = null;

  /// Broad category used to pick actions and viewers.
  final AppFileKind kind;

  /// Lower-case extension without the dot ('' when unknown).
  final String extension;

  final String mimeType;

  /// Canonical image format when [kind] is [AppFileKind.image]
  /// (`jpg`, `png`, `webp`, `gif`, `bmp`, `tiff`, `heic`).
  final String? imageFormat;

  bool get isImage => kind == AppFileKind.image;

  bool get isPdf => kind == AppFileKind.pdf;
}

/// Detects file types from the file header first and the file name second.
///
/// Extensions alone are unreliable (a `.jpg` may actually contain a PNG, and
/// some pickers return files without an extension), so signature bytes win
/// whenever they are available.
abstract final class FileTypeDetector {
  /// Maximum PDF size allowed across all PDF modules (50 MB).
  static const int maxPdfSizeBytes = 50 * 1024 * 1024;

  /// Human-readable form of [maxPdfSizeBytes] ("50 MB").
  ///
  /// User-facing messages must interpolate this instead of hardcoding the
  /// number, so the limit and its wording can never drift apart.
  static String get maxPdfSizeLabel =>
      '${maxPdfSizeBytes ~/ (1024 * 1024)} MB';

  /// Maximum number of PDFs allowed in PDF Merge (3 files).
  static const int maxMergePdfCount = 3;

  /// Maximum combined pages allowed in PDF Merge (1200 pages).
  static const int maxMergeCombinedPages = 1200;

  /// Maximum combined size allowed in PDF Merge (100 MB).
  ///
  /// Merging buffers every input document in memory at once, so the per-file
  /// limit alone is not a safe bound: three 50 MB files would still need well
  /// over twice that in RAM. This caps the total instead.
  static const int maxMergeCombinedBytes = 100 * 1024 * 1024;

  /// Maximum number of images allowed for Image Resize at a time (25 images).
  static const int maxResizeImageCount = 25;

  /// Maximum number of images allowed for Format Conversion at a time (25 images).
  static const int maxFormatConvertImageCount = 25;

  /// Maximum number of images allowed for Image to PDF conversion at a time (20 images).
  static const int maxImageToPdfCount = 20;

  /// Canonical extension for each supported image signature.
  static const Set<String> imageExtensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'bmp',
    'tif',
    'tiff',
    'heic',
    'heif',
  };

  /// Detects the type of a file from its bytes and/or its name.
  static DetectedFileType detect({
    String? path,
    String? name,
    Uint8List? bytes,
  }) {
    final effectiveName = name ?? _basename(path);
    final extension = extensionOf(effectiveName);

    if (bytes != null && bytes.isNotEmpty) {
      final signature = imageFormatFromSignature(bytes);
      if (_looksLikePdf(bytes)) {
        return const DetectedFileType(
          kind: AppFileKind.pdf,
          extension: 'pdf',
          mimeType: 'application/pdf',
        );
      }
      if (signature != null) {
        return DetectedFileType(
          kind: AppFileKind.image,
          extension: signature == 'jpg' ? 'jpg' : signature,
          mimeType: mimeTypeFor(signature),
          imageFormat: signature,
        );
      }
    }

    if (extension == 'pdf') {
      return const DetectedFileType(
        kind: AppFileKind.pdf,
        extension: 'pdf',
        mimeType: 'application/pdf',
      );
    }
    if (imageExtensions.contains(extension)) {
      final canonical = canonicalImageExtension(extension) ?? extension;
      return DetectedFileType(
        kind: AppFileKind.image,
        extension: canonical,
        mimeType: mimeTypeFor(canonical),
        imageFormat: canonical,
      );
    }
    return DetectedFileType(
      kind: AppFileKind.other,
      extension: extension,
      mimeType: mimeTypeFor(extension),
    );
  }

  /// True when [bytes] hold a real image whose decoded format already matches
  /// [targetExtension], so converting would create an identical file.
  static bool isAlreadyInFormat({
    required String targetExtension,
    String? path,
    String? name,
    Uint8List? bytes,
  }) {
    final type = detect(path: path, name: name, bytes: bytes);
    if (!type.isImage) return false;
    final source = canonicalImageExtension(type.imageFormat ?? type.extension);
    final target = canonicalImageExtension(targetExtension);
    if (source == null || target == null) return false;
    // JPG and JPEG are the same codec; treat them as one format so the user is
    // told the image is already in the requested format.
    return _codecOf(source) == _codecOf(target);
  }

  /// Normalises aliases (`jpeg` -> `jpg`, `tif` -> `tiff`).
  static String? canonicalImageExtension(String? extension) {
    if (extension == null) return null;
    final value = extension.toLowerCase().replaceFirst('.', '').trim();
    switch (value) {
      case 'jpg':
      case 'jpeg':
        return 'jpg';
      case 'tif':
      case 'tiff':
        return 'tiff';
      case 'heic':
      case 'heif':
        return 'heic';
      case 'png':
      case 'webp':
      case 'gif':
      case 'bmp':
        return value;
      default:
        return null;
    }
  }

  /// Reads the image format from the first bytes of [bytes].
  static String? imageFormatFromSignature(Uint8List bytes) {
    if (bytes.length < 4) return null;

    int at(int index) => index < bytes.length ? bytes[index] : -1;

    // JPEG: FF D8 FF
    if (at(0) == 0xFF && at(1) == 0xD8 && at(2) == 0xFF) return 'jpg';

    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (at(0) == 0x89 &&
        at(1) == 0x50 &&
        at(2) == 0x4E &&
        at(3) == 0x47 &&
        at(4) == 0x0D &&
        at(5) == 0x0A &&
        at(6) == 0x1A &&
        at(7) == 0x0A) {
      return 'png';
    }

    // GIF87a / GIF89a
    if (at(0) == 0x47 && at(1) == 0x49 && at(2) == 0x46) return 'gif';

    // BMP: 'BM'
    if (at(0) == 0x42 && at(1) == 0x4D) return 'bmp';

    // TIFF: II*\0 or MM\0*
    if (at(0) == 0x49 && at(1) == 0x49 && at(2) == 0x2A && at(3) == 0x00) {
      return 'tiff';
    }
    if (at(0) == 0x4D && at(1) == 0x4D && at(2) == 0x00 && at(3) == 0x2A) {
      return 'tiff';
    }

    // RIFF....WEBP
    if (at(0) == 0x52 &&
        at(1) == 0x49 &&
        at(2) == 0x46 &&
        at(3) == 0x46 &&
        at(8) == 0x57 &&
        at(9) == 0x45 &&
        at(10) == 0x42 &&
        at(11) == 0x50) {
      return 'webp';
    }

    // ISO-BMFF: ....ftyp<brand> — HEIC/HEIF still images.
    if (at(4) == 0x66 &&
        at(5) == 0x74 &&
        at(6) == 0x79 &&
        at(7) == 0x70) {
      final brand = String.fromCharCodes(
        bytes.sublist(8, bytes.length < 12 ? bytes.length : 12),
      );
      const heifBrands = <String>{
        'heic',
        'heix',
        'hevc',
        'heim',
        'heis',
        'hevm',
        'hevs',
        'mif1',
        'msf1',
        'avif',
      };
      if (heifBrands.contains(brand)) return 'heic';
    }

    return null;
  }

  /// True when the given [bytes] start with the standard `%PDF-` signature.
  static bool looksLikePdf(Uint8List bytes) {
    final limit = bytes.length < 1024 ? bytes.length : 1024;
    for (var i = 0; i + 5 <= limit; i++) {
      if (bytes[i] == 0x25 &&
          bytes[i + 1] == 0x50 &&
          bytes[i + 2] == 0x44 &&
          bytes[i + 3] == 0x46 &&
          bytes[i + 4] == 0x2D) {
        return true;
      }
    }
    return false;
  }

  static bool _looksLikePdf(Uint8List bytes) => looksLikePdf(bytes);

  /// True when [bytes] has a recognized image header.
  static bool isSupportedImage(Uint8List bytes) =>
      imageFormatFromSignature(bytes) != null;

  /// Lower-case extension of [fileName] without the dot.
  static String extensionOf(String? fileName) {
    if (fileName == null) return '';
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  /// Human readable label for the file type badge.
  static String labelFor(DetectedFileType type) {
    if (type.isPdf) return 'PDF';
    switch (type.imageFormat) {
      case 'jpg':
        return 'JPG';
      case 'png':
        return 'PNG';
      case 'webp':
        return 'WEBP';
      case 'gif':
        return 'GIF';
      case 'bmp':
        return 'BMP';
      case 'tiff':
        return 'TIFF';
      case 'heic':
        return 'HEIC';
      default:
        return type.extension.isEmpty ? 'FILE' : type.extension.toUpperCase();
    }
  }

  /// MIME type for a known extension.
  static String mimeTypeFor(String? extension) {
    switch ((extension ?? '').toLowerCase().replaceFirst('.', '')) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      case 'tif':
      case 'tiff':
        return 'image/tiff';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  /// Groups extensions that share the same codec (`jpg`/`jpeg`).
  static String _codecOf(String canonicalExtension) =>
      canonicalExtension == 'jpg' ? 'jpeg' : canonicalExtension;

  static String _basename(String? path) {
    if (path == null) return '';
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    return slash >= 0 ? path.substring(slash + 1) : path;
  }
}
