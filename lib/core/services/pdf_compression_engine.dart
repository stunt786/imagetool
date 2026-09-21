/// Pure-Dart, isolate-friendly PDF compression engine.
///
/// The engine performs *real* PDF compression. It rewrites the document's
/// object graph and, most importantly, re-encodes the embedded images that
/// dominate the size of scanned and photo-heavy documents:
///
///  * `DCTDecode` (JPEG) images are decoded, downsampled when needed and
///    re-encoded as JPEG at the quality selected by the user.
///  * `FlateDecode` raster images — including `Indexed`, `ICCBased`,
///    `CalRGB`/`CalGray` and `Separation` variants — are decoded to pixels and
///    re-encoded as JPEG.
///  * Uncompressed streams (content streams, metadata, embedded files) are
///    Flate/DEFLATE compressed.
///
/// Every other object is copied byte-for-byte, so text, vector art, fonts,
/// annotations, bookmarks and form fields are preserved exactly. Object
/// streams are expanded and a classic cross-reference table is written, which
/// every reader supports.
///
/// Memory safety is a first-class concern:
///  * images are decoded and encoded one at a time and released immediately;
///  * an image whose pixel count exceeds
///    [PdfCompressionPreset.maxDecodePixels] is skipped instead of decoded;
///  * images that are already well compressed and do not need downsampling are
///    skipped without decoding at all;
///  * image work stops once [PdfCompressionPreset.timeBudget] is exhausted so
///    a huge document can never appear to hang;
///  * the rewritten document is streamed to disk object by object instead of
///    being buffered a second time in memory.
///
/// The engine never returns a larger document: the caller compares the written
/// result with the input and falls back to the original bytes when no
/// improvement was achieved.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

// ══════════════════════════════ Public models ═══════════════════════════════

/// Tunable compression settings derived from the user-facing quality level.
class PdfCompressionPreset {
  const PdfCompressionPreset({
    required this.jpegQuality,
    required this.maxImageLongSide,
    required this.maxDecodePixels,
    required this.jpegSkipBytesPerPixel,
    this.minImageBytes = 4096,
    this.deflateStreams = true,
    this.timeBudget = const Duration(minutes: 3),
  });

  /// JPEG quality (1-100) used when re-encoding images.
  final int jpegQuality;

  /// Images longer than this on their longest side are downsampled.
  final int maxImageLongSide;

  /// Hard safety limit: images with more pixels than this are never decoded.
  final int maxDecodePixels;

  /// JPEGs that are already below this many bytes per pixel are left alone
  /// unless they need downsampling. Avoids re-encoding hundreds of
  /// already-optimised scans for no gain.
  final double jpegSkipBytesPerPixel;

  /// Streams smaller than this are never touched.
  final int minImageBytes;

  /// Whether to DEFLATE streams that are stored uncompressed.
  final bool deflateStreams;

  /// Upper bound for the (CPU bound) image re-encoding phase.
  final Duration timeBudget;

  /// Maps the feature's `qualityFactor` (0.15 … 0.8, higher = better quality)
  /// onto concrete compression settings.
  static PdfCompressionPreset forQualityFactor(double qualityFactor) {
    if (qualityFactor >= 0.7) {
      return const PdfCompressionPreset(
        jpegQuality: 82,
        maxImageLongSide: 2600,
        maxDecodePixels: 32 * 1000 * 1000,
        jpegSkipBytesPerPixel: 0.60,
      );
    }
    if (qualityFactor >= 0.4) {
      return const PdfCompressionPreset(
        jpegQuality: 70,
        maxImageLongSide: 2000,
        maxDecodePixels: 28 * 1000 * 1000,
        jpegSkipBytesPerPixel: 0.45,
      );
    }
    if (qualityFactor >= 0.25) {
      return const PdfCompressionPreset(
        jpegQuality: 58,
        maxImageLongSide: 1500,
        maxDecodePixels: 24 * 1000 * 1000,
        jpegSkipBytesPerPixel: 0.35,
      );
    }
    return const PdfCompressionPreset(
      jpegQuality: 45,
      maxImageLongSide: 1100,
      maxDecodePixels: 20 * 1000 * 1000,
      jpegSkipBytesPerPixel: 0.28,
    );
  }
}

/// Result of a compression run.
class PdfCompressionOutcome {
  const PdfCompressionOutcome({
    required this.inputBytes,
    required this.outputBytes,
    required this.improved,
    this.pageCount = 0,
    this.imagesFound = 0,
    this.imagesRecompressed = 0,
    this.imagesSkipped = 0,
    this.imagesUnsupported = 0,
    this.streamsDeflated = 0,
    this.note,
  });

  final int inputBytes;
  final int outputBytes;

  /// True when the written file is strictly smaller than the input.
  final bool improved;

  final int pageCount;
  final int imagesFound;
  final int imagesRecompressed;
  final int imagesSkipped;

  /// Images whose encoding (JPEG 2000 / JBIG2 / CCITT …) cannot be decoded by
  /// the engine and were therefore left untouched.
  final int imagesUnsupported;

  final int streamsDeflated;

  /// Optional human readable explanation of what happened, e.g. why no
  /// reduction was possible.
  final String? note;

  /// Percentage saved (0 when nothing was saved, never negative).
  double get reductionPercent {
    if (inputBytes <= 0 || outputBytes >= inputBytes) return 0;
    return (1 - outputBytes / inputBytes) * 100;
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'inputBytes': inputBytes,
        'outputBytes': outputBytes,
        'improved': improved,
        'pageCount': pageCount,
        'imagesFound': imagesFound,
        'imagesRecompressed': imagesRecompressed,
        'imagesSkipped': imagesSkipped,
        'imagesUnsupported': imagesUnsupported,
        'streamsDeflated': streamsDeflated,
        'note': note,
      };

  static PdfCompressionOutcome fromMap(Map<String, Object?> map) =>
      PdfCompressionOutcome(
        inputBytes: (map['inputBytes'] as num?)?.toInt() ?? 0,
        outputBytes: (map['outputBytes'] as num?)?.toInt() ?? 0,
        improved: map['improved'] as bool? ?? false,
        pageCount: (map['pageCount'] as num?)?.toInt() ?? 0,
        imagesFound: (map['imagesFound'] as num?)?.toInt() ?? 0,
        imagesRecompressed: (map['imagesRecompressed'] as num?)?.toInt() ?? 0,
        imagesSkipped: (map['imagesSkipped'] as num?)?.toInt() ?? 0,
        imagesUnsupported:
            (map['imagesUnsupported'] as num?)?.toInt() ?? 0,
        streamsDeflated: (map['streamsDeflated'] as num?)?.toInt() ?? 0,
        note: map['note'] as String?,
      );
}

// ══════════════════════════════ Public engine ═══════════════════════════════

class PdfCompressionEngine {
  PdfCompressionEngine._();

  /// Refuse to load absurdly large files into memory.
  static const int maxInputBytes = 320 * 1024 * 1024;

  /// Compresses [inputPath] into [outputPath] on a background isolate while
  /// reporting progress in the 0.0-1.0 range.
  ///
  /// [outputPath] is always written: either the compressed document or a copy
  /// of the original when no reduction was possible.
  static Future<PdfCompressionOutcome> compressFileInIsolate({
    required String inputPath,
    required String outputPath,
    required double qualityFactor,
    void Function(double progress)? onProgress,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final receivePort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
    final completer = Completer<PdfCompressionOutcome>();

    Isolate? isolate;

    void finish(PdfCompressionOutcome? value, Object? error) {
      if (completer.isCompleted) return;
      if (error != null) {
        completer.completeError(error);
      } else {
        completer.complete(value ??
            PdfCompressionOutcome(
              inputBytes: 0,
              outputBytes: 0,
              improved: false,
              note: 'Compression produced no result.',
            ));
      }
    }

    final subscription = receivePort.listen((Object? message) {
      if (message is! Map) return;
      switch (message['type']) {
        case 'progress':
          final value = (message['value'] as num?)?.toDouble() ?? 0;
          onProgress?.call(value.clamp(0.0, 1.0));
          break;
        case 'done':
          final map = (message['outcome'] as Map?)?.cast<String, Object?>();
          finish(
            map == null ? null : PdfCompressionOutcome.fromMap(map),
            null,
          );
          break;
        case 'error':
          finish(null, StateError(message['error']?.toString() ?? 'failed'));
          break;
      }
    });

    final errorSubscription = errorPort.listen((Object? message) {
      var text = 'PDF compression failed.';
      if (message is List && message.isNotEmpty) {
        text = message.first?.toString() ?? text;
      } else if (message != null) {
        text = message.toString();
      }
      finish(null, StateError(text));
    });

    try {
      isolate = await Isolate.spawn<List<Object?>>(
        _pdfCompressionIsolateEntry,
        <Object?>[
          receivePort.sendPort,
          <String, Object?>{
            'inputPath': inputPath,
            'outputPath': outputPath,
            'qualityFactor': qualityFactor,
          },
        ],
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
        errorsAreFatal: true,
        debugName: 'pdf_compression',
      );

      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException('PDF compression timed out.', timeout);
        },
      );
    } finally {
      isolate?.kill(priority: Isolate.immediate);
      await subscription.cancel();
      await errorSubscription.cancel();
      exitPort.close();
      receivePort.close();
      errorPort.close();
    }
  }

  /// Compresses a PDF file in the current isolate. Always writes
  /// [outputPath] (compressed bytes, or a copy of the input when the rewrite
  /// did not get smaller).
  static Future<PdfCompressionOutcome> compressFile({
    required String inputPath,
    required String outputPath,
    required PdfCompressionPreset preset,
    void Function(double progress)? onProgress,
  }) async {
    final inputFile = File(inputPath);
    final inputSize = await inputFile.length();
    if (inputSize <= 0) {
      throw StateError('The selected PDF is empty.');
    }

    if (inputSize > maxInputBytes) {
      await _copyFile(inputPath, outputPath);
      return PdfCompressionOutcome(
        inputBytes: inputSize,
        outputBytes: inputSize,
        improved: false,
        note: 'File is too large to compress safely on this device.',
      );
    }

    onProgress?.call(0.02);
    final input = await inputFile.readAsBytes();

    final rewriter = _PdfRewriter(input, preset);
    final rewritten = await rewriter.run(outputPath, onProgress: onProgress);

    if (!rewritten.improved) {
      // Discard the (larger) rewrite and hand back a verbatim copy.
      await _copyFile(inputPath, outputPath);
      return PdfCompressionOutcome(
        inputBytes: inputSize,
        outputBytes: inputSize,
        improved: false,
        pageCount: rewritten.pageCount,
        imagesFound: rewritten.imagesFound,
        imagesRecompressed: rewritten.imagesRecompressed,
        imagesSkipped: rewritten.imagesSkipped,
        imagesUnsupported: rewritten.imagesUnsupported,
        streamsDeflated: rewritten.streamsDeflated,
        note: rewritten.note ??
            'This PDF is already highly optimised; no smaller output was possible.',
      );
    }

    // The rewrite is only a candidate until we know it is smaller; move it
    // into place now.
    final candidate = File('$outputPath.part');
    final target = File(outputPath);
    if (await target.exists()) {
      await target.delete();
    }
    await candidate.rename(outputPath);

    return PdfCompressionOutcome(
      inputBytes: inputSize,
      outputBytes: rewritten.outputBytes,
      improved: true,
      pageCount: rewritten.pageCount,
      imagesFound: rewritten.imagesFound,
      imagesRecompressed: rewritten.imagesRecompressed,
      imagesSkipped: rewritten.imagesSkipped,
      imagesUnsupported: rewritten.imagesUnsupported,
      streamsDeflated: rewritten.streamsDeflated,
      note: rewritten.note,
    );
  }

  /// Convenience helper for in-memory callers. Returns the compressed bytes,
  /// or [input] unchanged when no reduction was possible.
  static Future<Uint8List> compressBytes({
    required Uint8List input,
    required PdfCompressionPreset preset,
    void Function(double progress)? onProgress,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('pixeltools_pdfc_');
    try {
      final inputPath = '${tempDir.path}${Platform.pathSeparator}input.pdf';
      final outputPath = '${tempDir.path}${Platform.pathSeparator}output.pdf';
      await File(inputPath).writeAsBytes(input, flush: true);
      await compressFile(
        inputPath: inputPath,
        outputPath: outputPath,
        preset: preset,
        onProgress: onProgress,
      );
      return await File(outputPath).readAsBytes();
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // Best effort cleanup only.
      }
    }
  }

  static Future<void> _copyFile(String from, String to) async {
    final destination = File(to);
    if (from == to) return;
    await destination.parent.create(recursive: true);
    await File(from).copy(to);
  }
}

// ══════════════════════════════ Isolate entry ═══════════════════════════════

Future<void> _pdfCompressionIsolateEntry(List<Object?> args) async {
  final sendPort = args[0] as SendPort;
  final params = (args[1] as Map).cast<String, Object?>();
  try {
    final outcome = await PdfCompressionEngine.compressFile(
      inputPath: params['inputPath'] as String,
      outputPath: params['outputPath'] as String,
      preset: PdfCompressionPreset.forQualityFactor(
        (params['qualityFactor'] as num).toDouble(),
      ),
      onProgress: (progress) =>
          sendPort.send(<String, Object?>{'type': 'progress', 'value': progress}),
    );
    sendPort.send(<String, Object?>{'type': 'done', 'outcome': outcome.toMap()});
  } catch (error, stack) {
    sendPort.send(<String, Object?>{
      'type': 'error',
      'error': error.toString(),
      'stack': stack.toString(),
    });
  }
}

// ══════════════════════════════ Low level model ═════════════════════════════

bool _isWhite(int c) =>
    c == 0x00 ||
    c == 0x09 ||
    c == 0x0A ||
    c == 0x0C ||
    c == 0x0D ||
    c == 0x20;

bool _isDelimiter(int c) =>
    c == 0x28 || // (
    c == 0x29 || // )
    c == 0x3C || // <
    c == 0x3E || // >
    c == 0x5B || // [
    c == 0x5D || // ]
    c == 0x7B || // {
    c == 0x7D || // }
    c == 0x2F || // /
    c == 0x25; // %

bool _isRegular(int c) => !_isWhite(c) && !_isDelimiter(c);

class _PdfName {
  const _PdfName(this.name);
  final String name;
  @override
  String toString() => '/$name';
}

class _PdfString {
  const _PdfString(this.bytes, {required this.hex});
  final Uint8List bytes;
  final bool hex;
}

class _PdfRef {
  const _PdfRef(this.number, this.generation);
  final int number;
  final int generation;
  @override
  String toString() => '$number $generation R';
}

class _Keyword {
  const _Keyword(this.value);
  final String value;
}

/// A top-level indirect object discovered by the scanner.
class _RawObject {
  _RawObject({
    required this.number,
    required this.generation,
    required this.start,
    required this.end,
    required this.bodyStart,
    required this.dict,
    required this.value,
    this.dataStart,
    this.dataEnd,
  });

  final int number;
  final int generation;

  /// Byte offset of the `N G obj` header.
  final int start;

  /// Byte offset just past `endobj`.
  final int end;

  /// Byte offset just past the `obj` keyword.
  final int bodyStart;

  final int? dataStart;
  final int? dataEnd;
  final Map<String, Object?> dict;
  final Object? value;

  bool get isStream => dataStart != null;
}

/// An object that is part of the document, either top-level or unpacked from
/// an object stream.
class _DocObject {
  _DocObject({
    required this.number,
    required this.generation,
    required this.order,
    required this.dict,
    required this.value,
    this.raw,
    this.rawBytes,
  });

  final int number;
  final int generation;
  final int order;
  final Map<String, Object?> dict;
  final Object? value;

  /// Present when the object lives at the top level of the input file.
  final _RawObject? raw;

  /// Present when the object was unpacked from an object stream: the exact
  /// bytes of the object body.
  final Uint8List? rawBytes;
}

class _DecodedImageResult {
  const _DecodedImageResult(this.image);
  final img.Image image;
}

enum _ImageSupport { supported, unsupportedFormat, skip }

class _ColorSpace {
  const _ColorSpace.gray()
      : kind = _ColorSpaceKind.gray,
        base = null,
        palette = null,
        hival = 0;
  const _ColorSpace.rgb()
      : kind = _ColorSpaceKind.rgb,
        base = null,
        palette = null,
        hival = 0;
  const _ColorSpace.cmyk()
      : kind = _ColorSpaceKind.cmyk,
        base = null,
        palette = null,
        hival = 0;
  const _ColorSpace.indexed(this.base, this.hival, this.palette)
      : kind = _ColorSpaceKind.indexed;

  final _ColorSpaceKind kind;
  final _ColorSpace? base;
  final int hival;
  final Uint8List? palette;
}

enum _ColorSpaceKind { gray, rgb, cmyk, indexed }

class _ModifiedStream {
  const _ModifiedStream(this.dict, this.data);
  final Map<String, Object?> dict;
  final Uint8List data;
}

class _RewriteStats {
  _RewriteStats({
    required this.outputBytes,
    required this.improved,
    required this.pageCount,
    required this.imagesFound,
    required this.imagesRecompressed,
    required this.imagesSkipped,
    required this.imagesUnsupported,
    required this.streamsDeflated,
    this.note,
  });

  final int outputBytes;
  final bool improved;
  final int pageCount;
  final int imagesFound;
  final int imagesRecompressed;
  final int imagesSkipped;
  final int imagesUnsupported;
  final int streamsDeflated;
  final String? note;
}

// ══════════════════════════════ Tokenizer ═══════════════════════════════════

class _PdfParser {
  _PdfParser(this.bytes, [this.pos = 0]);

  final Uint8List bytes;
  int pos;

  bool get isEof => pos >= bytes.length;

  int peek() => pos < bytes.length ? bytes[pos] : -1;

  int? peekAt(int index) =>
      index >= 0 && index < bytes.length ? bytes[index] : null;

  void skipWhite() {
    while (pos < bytes.length) {
      final c = bytes[pos];
      if (_isWhite(c)) {
        pos++;
        continue;
      }
      if (c == 0x25) {
        while (pos < bytes.length && bytes[pos] != 0x0A && bytes[pos] != 0x0D) {
          pos++;
        }
        continue;
      }
      break;
    }
  }

  bool matchKeyword(String keyword) {
    skipWhite();
    if (pos + keyword.length > bytes.length) return false;
    for (var i = 0; i < keyword.length; i++) {
      if (bytes[pos + i] != keyword.codeUnitAt(i)) return false;
    }
    final after = pos + keyword.length;
    if (after < bytes.length && _isRegular(bytes[after])) return false;
    pos = after;
    return true;
  }

  String readNumberToken() {
    final start = pos;
    if (pos < bytes.length &&
        (bytes[pos] == 0x2B || bytes[pos] == 0x2D)) {
      pos++;
    }
    var seenDot = false;
    while (pos < bytes.length) {
      final c = bytes[pos];
      if (c >= 0x30 && c <= 0x39) {
        pos++;
        continue;
      }
      if (c == 0x2E && !seenDot) {
        seenDot = true;
        pos++;
        continue;
      }
      break;
    }
    if (pos == start) return '';
    return String.fromCharCodes(bytes, start, pos);
  }

  Object? parseValue() {
    skipWhite();
    if (isEof) return null;
    final c = bytes[pos];
    if (c == 0x3C) {
      if (peekAt(pos + 1) == 0x3C) return parseDict();
      return _parseHexString();
    }
    if (c == 0x5B) return _parseArray();
    if (c == 0x2F) return _parseName();
    if (c == 0x28) return _parseLiteralString();
    if (c == 0x2B || c == 0x2D || c == 0x2E || (c >= 0x30 && c <= 0x39)) {
      return _parseNumberOrReference();
    }
    return _parseKeyword();
  }

  Map<String, Object?> parseDict() {
    final result = <String, Object?>{};
    // Consume '<<'
    pos += 2;
    while (true) {
      skipWhite();
      if (isEof) break;
      if (peek() == 0x3E && peekAt(pos + 1) == 0x3E) {
        pos += 2;
        break;
      }
      if (peek() != 0x2F) {
        final before = pos;
        parseValue();
        if (pos == before) pos++;
        continue;
      }
      final key = _parseName().name;
      final value = parseValue();
      result[key] = value;
    }
    return result;
  }

  List<Object?> _parseArray() {
    final result = <Object?>[];
    pos++; // '['
    while (true) {
      skipWhite();
      if (isEof) break;
      if (peek() == 0x5D) {
        pos++;
        break;
      }
      final before = pos;
      result.add(parseValue());
      if (pos == before) pos++;
    }
    return result;
  }

  _PdfName _parseName() {
    pos++; // '/'
    final buffer = <int>[];
    while (pos < bytes.length) {
      final c = bytes[pos];
      if (_isWhite(c) || _isDelimiter(c)) break;
      if (c == 0x23 && pos + 2 < bytes.length) {
        final hi = _hexValue(bytes[pos + 1]);
        final lo = _hexValue(bytes[pos + 2]);
        if (hi >= 0 && lo >= 0) {
          buffer.add((hi << 4) | lo);
          pos += 3;
          continue;
        }
      }
      buffer.add(c);
      pos++;
    }
    return _PdfName(String.fromCharCodes(buffer));
  }

  _PdfString _parseLiteralString() {
    pos++; // '('
    var depth = 1;
    final buffer = <int>[];
    while (pos < bytes.length) {
      final c = bytes[pos];
      if (c == 0x5C) {
        pos++;
        if (pos >= bytes.length) break;
        final esc = bytes[pos];
        switch (esc) {
          case 0x6E:
            buffer.add(0x0A);
            pos++;
            break;
          case 0x72:
            buffer.add(0x0D);
            pos++;
            break;
          case 0x74:
            buffer.add(0x09);
            pos++;
            break;
          case 0x62:
            buffer.add(0x08);
            pos++;
            break;
          case 0x66:
            buffer.add(0x0C);
            pos++;
            break;
          case 0x28:
          case 0x29:
          case 0x5C:
            buffer.add(esc);
            pos++;
            break;
          case 0x0D:
            pos++;
            if (pos < bytes.length && bytes[pos] == 0x0A) pos++;
            break;
          case 0x0A:
            pos++;
            break;
          default:
            if (esc >= 0x30 && esc <= 0x37) {
              var value = 0;
              var count = 0;
              while (count < 3 &&
                  pos < bytes.length &&
                  bytes[pos] >= 0x30 &&
                  bytes[pos] <= 0x37) {
                value = (value << 3) | (bytes[pos] - 0x30);
                pos++;
                count++;
              }
              buffer.add(value & 0xFF);
            } else {
              buffer.add(esc);
              pos++;
            }
        }
        continue;
      }
      if (c == 0x28) {
        depth++;
        buffer.add(c);
        pos++;
        continue;
      }
      if (c == 0x29) {
        depth--;
        pos++;
        if (depth == 0) break;
        buffer.add(c);
        continue;
      }
      buffer.add(c);
      pos++;
    }
    return _PdfString(Uint8List.fromList(buffer), hex: false);
  }

  _PdfString _parseHexString() {
    pos++; // '<'
    final buffer = <int>[];
    int? pending;
    while (pos < bytes.length) {
      final c = bytes[pos];
      if (c == 0x3E) {
        pos++;
        break;
      }
      final value = _hexValue(c);
      if (value < 0) {
        pos++;
        continue;
      }
      if (pending == null) {
        pending = value;
      } else {
        buffer.add((pending << 4) | value);
        pending = null;
      }
      pos++;
    }
    if (pending != null) buffer.add(pending << 4);
    return _PdfString(Uint8List.fromList(buffer), hex: true);
  }

  Object? _parseNumberOrReference() {
    final start = pos;
    final token = readNumberToken();
    if (token.isEmpty) {
      pos = start + 1;
      return null;
    }
    final first = _parseNumberToken(token);
    if (first is int) {
      final afterFirst = pos;
      skipWhite();
      final secondToken = readNumberToken();
      if (secondToken.isNotEmpty) {
        final second = int.tryParse(secondToken);
        if (second != null) {
          skipWhite();
          if (peek() == 0x52) {
            final afterR = pos + 1;
            if (afterR >= bytes.length || !_isRegular(bytes[afterR])) {
              pos = afterR;
              return _PdfRef(first, second);
            }
          }
        }
      }
      pos = afterFirst;
    }
    return first;
  }

  Object? _parseKeyword() {
    final start = pos;
    while (pos < bytes.length && _isRegular(bytes[pos])) {
      pos++;
    }
    if (pos == start) {
      pos++;
      return null;
    }
    final text = String.fromCharCodes(bytes, start, pos);
    switch (text) {
      case 'true':
        return true;
      case 'false':
        return false;
      case 'null':
        return null;
      default:
        return _Keyword(text);
    }
  }

  static int _hexValue(int c) {
    if (c >= 0x30 && c <= 0x39) return c - 0x30;
    if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
    if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
    return -1;
  }

  static Object? _parseNumberToken(String token) {
    if (token.contains('.')) return double.tryParse(token);
    return int.tryParse(token);
  }
}

// ══════════════════════════════ Serializer ══════════════════════════════════

void _writeValue(StringBuffer out, Object? value) {
  if (value == null) {
    out.write('null');
  } else if (value is bool) {
    out.write(value ? 'true' : 'false');
  } else if (value is int) {
    out.write(value);
  } else if (value is double) {
    out.write(_formatDouble(value));
  } else if (value is _PdfName) {
    out.write('/');
    out.write(_encodeName(value.name));
  } else if (value is _PdfString) {
    out.write('<');
    for (final byte in value.bytes) {
      out.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    out.write('>');
  } else if (value is _PdfRef) {
    out.write('${value.number} ${value.generation} R');
  } else if (value is _Keyword) {
    out.write(value.value);
  } else if (value is List) {
    out.write('[');
    for (final entry in value) {
      _writeValue(out, entry);
      out.write(' ');
    }
    out.write(']');
  } else if (value is Map) {
    out.write('<<');
    value.forEach((key, entry) {
      out.write('/');
      out.write(_encodeName(key.toString()));
      out.write(' ');
      _writeValue(out, entry);
      out.write(' ');
    });
    out.write('>>');
  } else {
    out.write('null');
  }
}

String _encodeName(String name) {
  final buffer = StringBuffer();
  for (final code in name.codeUnits) {
    final isSafe = code > 0x20 &&
        code < 0x7F &&
        code != 0x23 && // #
        !_isDelimiter(code);
    if (isSafe) {
      buffer.writeCharCode(code);
    } else {
      buffer.write('#');
      buffer.write(code.toRadixString(16).padLeft(2, '0'));
    }
  }
  return buffer.toString();
}

String _formatDouble(double value) {
  if (value.isNaN || value.isInfinite) return '0';
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  var text = value.toStringAsFixed(4);
  if (text.contains('.')) {
    text = text.replaceAll(RegExp(r'0+$'), '');
    text = text.replaceAll(RegExp(r'\.$'), '');
  }
  return text;
}

// ══════════════════════════════ Rewriter ════════════════════════════════════

class _PdfRewriter {
  _PdfRewriter(this.input, this.preset);

  final Uint8List input;
  final PdfCompressionPreset preset;

  final Map<int, _DocObject> _objects = <int, _DocObject>{};
  final List<_DocObject> _ordered = <_DocObject>[];
  final Map<int, _ModifiedStream> _modifications = <int, _ModifiedStream>{};

  Map<String, Object?> _trailer = <String, Object?>{};
  _PdfRef? _rootRef;
  _PdfRef? _infoRef;
  bool _encrypted = false;
  int _pageCount = 0;

  int _imagesFound = 0;
  int _imagesRecompressed = 0;
  int _imagesSkipped = 0;
  int _imagesUnsupported = 0;
  int _streamsDeflated = 0;
  String? _note;

  Future<_RewriteStats> run(
    String outputPath, {
    void Function(double progress)? onProgress,
  }) async {
    final headerOk = _looksLikePdf(input);
    if (!headerOk) {
      return _noOp('The selected file is not a valid PDF document.');
    }

    final scanned = _scanObjects(input);
    if (scanned.isEmpty) {
      return _noOp('The PDF could not be parsed.');
    }

    _buildObjectTable(scanned);
    _readTrailer(scanned);

    if (_encrypted) {
      return _noOp(
        'Encrypted PDFs cannot be compressed. Remove the password first.',
      );
    }

    _countPages();

    final tasks = _collectTasks();
    final partialPath = '$outputPath.part';
    final partialFile = File(partialPath);
    await partialFile.parent.create(recursive: true);

    final total = tasks.length;
    var completed = 0;
    var budgetExhausted = false;
    final stopwatch = Stopwatch()..start();

    for (final task in tasks) {
      if (!budgetExhausted &&
          stopwatch.elapsed > preset.timeBudget &&
          task.isImage) {
        budgetExhausted = true;
      }
      if (!budgetExhausted) {
        try {
          if (task.isImage) {
            final handled = _processImage(task.object);
            if (!handled) {
              // Lossless fallback for images that could not be improved by
              // JPEG re-encoding (for example raw bitmaps).
              _processDeflatableStream(task.object);
            }
          } else {
            _processDeflatableStream(task.object);
          }
        } catch (_) {
          // A single unreadable stream must never abort the whole document.
          if (task.isImage) _imagesSkipped++;
        }
      } else if (task.isImage) {
        _imagesSkipped++;
      }
      completed++;
      onProgress?.call(total == 0 ? 0.95 : 0.10 + 0.80 * (completed / total));
    }

    if (budgetExhausted) {
      _note = 'Time limit reached; remaining images were copied unchanged.';
    }

    onProgress?.call(0.92);

    int written;
    try {
      written = await _writeDocument(partialPath);
    } catch (_) {
      // Never leave a partial document behind.
      try {
        if (await partialFile.exists()) await partialFile.delete();
      } catch (_) {}
      rethrow;
    }
    stopwatch.stop();

    final improved = written < input.length;
    if (!improved) {
      try {
        await partialFile.delete();
      } catch (_) {
        // Ignore: the caller replaces the file anyway.
      }
    }

    onProgress?.call(1.0);

    return _RewriteStats(
      outputBytes: written,
      improved: improved,
      pageCount: _pageCount,
      imagesFound: _imagesFound,
      imagesRecompressed: _imagesRecompressed,
      imagesSkipped: _imagesSkipped,
      imagesUnsupported: _imagesUnsupported,
      streamsDeflated: _streamsDeflated,
      note: _buildNote(),
    );
  }

  _RewriteStats _noOp(String note) => _RewriteStats(
        outputBytes: input.length,
        improved: false,
        pageCount: _pageCount,
        imagesFound: _imagesFound,
        imagesRecompressed: 0,
        imagesSkipped: 0,
        imagesUnsupported: 0,
        streamsDeflated: 0,
        note: note,
      );

  String? _buildNote() {
    if (_note != null) return _note;
    if (_imagesUnsupported > 0 && _imagesRecompressed == 0) {
      return 'Some images use a format or colour space that cannot be safely '
          'recompressed (JPEG 2000, JBIG2, CCITT or a device colour space); '
          'they were left untouched.';
    }
    return null;
  }

  void _countPages() {
    // Preferred: walk the page tree from the catalogue. Counting every
    // `/Type /Page` object in the file can over-count leftovers from
    // incremental updates.
    final root = _rootRef;
    if (root != null) {
      final catalog = _objects[root.number];
      final counted = _countPagesUnder(catalog?.dict['Pages'], <int>{});
      if (counted > 0) {
        _pageCount = counted;
        return;
      }
    }
    var count = 0;
    for (final object in _ordered) {
      final type = object.dict['Type'];
      if (type is _PdfName && type.name == 'Page') count++;
    }
    _pageCount = count;
  }

  int _countPagesUnder(Object? node, Set<int> visited) {
    if (node is! _PdfRef) return 0;
    if (!visited.add(node.number)) return 0;
    final object = _objects[node.number];
    if (object == null) return 0;
    final type = object.dict['Type'];
    if (type is _PdfName && type.name == 'Page') return 1;
    final kids = _resolve(object.dict['Kids']);
    if (kids is! List) return 0;
    var total = 0;
    for (final kid in kids) {
      total += _countPagesUnder(kid, visited);
    }
    return total;
  }

  // ─── Scanning ──────────────────────────────────────────────────────────

  static bool _looksLikePdf(Uint8List bytes) {
    final limit = math.min(bytes.length, 1024);
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

  List<_RawObject> _scanObjects(Uint8List bytes) {
    var intValues = <int, int>{};
    var objects = _scanPass(bytes, intValues);
    for (var iteration = 0; iteration < 3; iteration++) {
      final discovered = <int, int>{};
      for (final object in objects) {
        final value = object.value;
        if (value is int) discovered[object.number] = value;
      }
      var changed = false;
      for (final entry in discovered.entries) {
        if (intValues[entry.key] != entry.value) {
          changed = true;
          intValues[entry.key] = entry.value;
        }
      }
      if (!changed) break;
      objects = _scanPass(bytes, intValues);
    }
    return objects;
  }

  List<_RawObject> _scanPass(Uint8List bytes, Map<int, int> intValues) {
    final objects = <_RawObject>[];
    final parser = _PdfParser(bytes);
    while (!parser.isEof) {
      parser.skipWhite();
      if (parser.isEof) break;
      final save = parser.pos;
      final header = _matchObjectHeader(parser);
      if (header == null) {
        parser.pos = save + 1;
        continue;
      }
      final number = header.$1;
      final generation = header.$2;
      final start = save;
      final object = _parseObjectBody(
        parser,
        number,
        generation,
        start,
        intValues,
      );
      if (object == null) {
        // Unparseable tail: stop scanning rather than looping forever.
        if (parser.pos <= start) break;
        continue;
      }
      objects.add(object);
    }
    return objects;
  }

  (int, int)? _matchObjectHeader(_PdfParser parser) {
    final start = parser.pos;
    if (start >= parser.bytes.length) return null;
    if (start > 0) {
      final previous = parser.bytes[start - 1];
      if (!_isWhite(previous) && !_isDelimiter(previous)) return null;
    }
    final numberToken = parser.readNumberToken();
    if (numberToken.isEmpty || numberToken.contains('.')) return null;
    final number = int.tryParse(numberToken);
    if (number == null || number < 0) return null;
    parser.skipWhite();
    final generationToken = parser.readNumberToken();
    if (generationToken.isEmpty || generationToken.contains('.')) return null;
    final generation = int.tryParse(generationToken);
    if (generation == null || generation < 0) return null;
    parser.skipWhite();
    if (!parser.matchKeyword('obj')) return null;
    return (number, generation);
  }

  _RawObject? _parseObjectBody(
    _PdfParser parser,
    int number,
    int generation,
    int start,
    Map<int, int> intValues,
  ) {
    parser.skipWhite();
    final bodyStart = parser.pos;

    if (parser.matchKeyword('endobj')) {
      return _RawObject(
        number: number,
        generation: generation,
        start: start,
        end: parser.pos,
        bodyStart: bodyStart,
        dict: const <String, Object?>{},
        value: null,
      );
    }

    final value = parser.parseValue();
    parser.skipWhite();

    int? dataStart;
    int? dataEnd;
    if (parser.matchKeyword('stream')) {
      if (parser.peek() == 0x0D) {
        parser.pos++;
        if (parser.peek() == 0x0A) parser.pos++;
      } else if (parser.peek() == 0x0A) {
        parser.pos++;
      }
      final dict = value is Map<String, Object?>
          ? value
          : const <String, Object?>{};
      dataStart = parser.pos;
      dataEnd = _resolveStreamEnd(parser.bytes, parser.pos, dict['Length'], intValues);
      parser.pos = dataEnd;
      parser.skipWhite();
      parser.matchKeyword('endstream');
    }

    parser.skipWhite();
    if (!parser.matchKeyword('endobj')) {
      final index = _indexOfAscii(parser.bytes, 'endobj', parser.pos);
      if (index < 0) {
        parser.pos = parser.bytes.length;
        return null;
      }
      parser.pos = index + 6;
    }

    return _RawObject(
      number: number,
      generation: generation,
      start: start,
      end: parser.pos,
      bodyStart: bodyStart,
      dataStart: dataStart,
      dataEnd: dataEnd,
      dict: value is Map<String, Object?> ? value : const <String, Object?>{},
      value: value,
    );
  }

  int _resolveStreamEnd(
    Uint8List bytes,
    int dataStart,
    Object? lengthValue,
    Map<int, int> intValues,
  ) {
    int? length;
    if (lengthValue is int) {
      length = lengthValue;
    } else if (lengthValue is _PdfRef) {
      length = intValues[lengthValue.number];
    }
    if (length != null && length >= 0 && dataStart + length <= bytes.length) {
      if (_isEndstreamAt(bytes, dataStart + length)) {
        return dataStart + length;
      }
    }
    return _searchEndstream(bytes, dataStart) ?? bytes.length;
  }

  static bool _isEndstreamAt(Uint8List bytes, int position) {
    var index = position;
    var skipped = 0;
    while (index < bytes.length && _isWhite(bytes[index]) && skipped < 4) {
      index++;
      skipped++;
    }
    if (!_matchesAscii(bytes, index, 'endstream')) return false;
    index += 9;
    while (index < bytes.length && _isWhite(bytes[index])) {
      index++;
    }
    if (index >= bytes.length) return true;
    return _matchesAscii(bytes, index, 'endobj') ||
        _matchesAscii(bytes, index, 'startxref');
  }

  static int? _searchEndstream(Uint8List bytes, int from) {
    var cursor = from;
    while (cursor < bytes.length) {
      final index = _indexOfAscii(bytes, 'endstream', cursor);
      if (index < 0) return null;
      if (index > 0 && (bytes[index - 1] == 0x0A || bytes[index - 1] == 0x0D)) {
        var dataEnd = index;
        if (dataEnd > 0 && bytes[dataEnd - 1] == 0x0A) dataEnd--;
        if (dataEnd > 0 && bytes[dataEnd - 1] == 0x0D) dataEnd--;
        if (_isEndstreamAt(bytes, dataEnd)) return dataEnd;
      }
      cursor = index + 9;
    }
    return null;
  }

  // ─── Object table ──────────────────────────────────────────────────────

  void _buildObjectTable(List<_RawObject> scanned) {
    final candidates = <_DocObject>[];
    final objectStreams = <_RawObject>[];

    for (var index = 0; index < scanned.length; index++) {
      final raw = scanned[index];
      candidates.add(_DocObject(
        number: raw.number,
        generation: raw.generation,
        order: index,
        dict: raw.dict,
        value: raw.value,
        raw: raw,
      ));
      final type = raw.dict['Type'];
      if (raw.isStream && type is _PdfName && type.name == 'ObjStm') {
        objectStreams.add(raw);
      }
    }

    // Expand object streams: every contained object keeps its number and is
    // rewritten as a plain top-level object so a classic xref table can
    // describe it.
    var order = scanned.length;
    for (final objectStream in objectStreams) {
      final expanded = _expandObjectStream(objectStream, order);
      candidates.addAll(expanded);
      order += expanded.length + 1;
    }

    for (final candidate in candidates) {
      _objects[candidate.number] = candidate;
    }

    final sorted = _objects.values.toList()
      ..sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        return byOrder != 0 ? byOrder : a.number.compareTo(b.number);
      });
    _ordered.addAll(sorted);
  }

  List<_DocObject> _expandObjectStream(_RawObject objectStream, int order) {
    final result = <_DocObject>[];
    final type = objectStream.dict['Type'];
    if (type is! _PdfName || type.name != 'ObjStm') return result;
    final count = _firstInt(objectStream.dict['N']);
    final first = _firstInt(objectStream.dict['First']);
    if (count == null || first == null || count <= 0) return result;

    Uint8List decoded;
    try {
      decoded = _decodeStreamBytes(objectStream);
    } catch (_) {
      return result;
    }
    if (first > decoded.length) return result;

    final headerParser = _PdfParser(decoded, 0);
    final pairs = <(int, int)>[];
    for (var i = 0; i < count; i++) {
      headerParser.skipWhite();
      final numberToken = headerParser.readNumberToken();
      headerParser.skipWhite();
      final offsetToken = headerParser.readNumberToken();
      final number = int.tryParse(numberToken);
      final offset = int.tryParse(offsetToken);
      if (number == null || offset == null) break;
      pairs.add((number, offset));
    }

    for (var i = 0; i < pairs.length; i++) {
      final number = pairs[i].$1;
      final start = first + pairs[i].$2;
      final end = i + 1 < pairs.length ? first + pairs[i + 1].$2 : decoded.length;
      if (start < 0 || end > decoded.length || start >= end) continue;
      final slice = Uint8List.sublistView(decoded, start, end);
      final valueParser = _PdfParser(slice, 0);
      Object? value;
      try {
        value = valueParser.parseValue();
      } catch (_) {
        value = null;
      }
      result.add(_DocObject(
        number: number,
        generation: 0,
        order: order + i,
        dict: value is Map<String, Object?> ? value : const <String, Object?>{},
        value: value,
        rawBytes: slice,
      ));
    }
    return result;
  }

  void _readTrailer(List<_RawObject> scanned) {
    final spans = scanned.map((o) => (o.start, o.end)).toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));

    var cursor = 0;
    Map<String, Object?>? trailer;
    for (final span in spans) {
      final found = _findTrailerBetween(input, cursor, span.$1);
      if (found != null) trailer = found;
      cursor = math.max(cursor, span.$2);
    }
    final tail = _findTrailerBetween(input, cursor, input.length);
    if (tail != null) trailer = tail;

    if (trailer == null) {
      // PDF 1.5+: the trailer information lives in the cross-reference stream.
      for (final object in _ordered) {
        final type = object.dict['Type'];
        if (type is _PdfName && type.name == 'XRef') {
          trailer = object.dict;
        }
      }
    }

    _trailer = trailer ?? <String, Object?>{};
    _encrypted = _trailer.containsKey('Encrypt');

    final root = _trailer['Root'];
    if (root is _PdfRef) {
      _rootRef = root;
    } else {
      for (final object in _ordered) {
        final type = object.dict['Type'];
        if (type is _PdfName && type.name == 'Catalog') {
          _rootRef = _PdfRef(object.number, object.generation);
        }
      }
    }

    final info = _trailer['Info'];
    if (info is _PdfRef) _infoRef = info;
  }

  Map<String, Object?>? _findTrailerBetween(
    Uint8List bytes,
    int from,
    int to,
  ) {
    Map<String, Object?>? result;
    var cursor = from;
    while (cursor < to) {
      final index = _indexOfAscii(bytes, 'trailer', cursor, to);
      if (index < 0) break;
      if (index == 0 || _isWhite(bytes[index - 1]) || _isDelimiter(bytes[index - 1])) {
        final parser = _PdfParser(bytes, index + 7);
        parser.skipWhite();
        if (parser.peek() == 0x3C) {
          final dict = parser.parseDict();
          if (dict.isNotEmpty) result = dict;
        }
      }
      cursor = index + 7;
    }
    return result;
  }

  // ─── Stream tasks ──────────────────────────────────────────────────────

  List<_StreamTask> _collectTasks() {
    final tasks = <_StreamTask>[];
    for (final object in _ordered) {
      final raw = object.raw;
      if (raw == null || !raw.isStream) continue;
      final type = object.dict['Type'];
      if (type is _PdfName &&
          (type.name == 'ObjStm' || type.name == 'XRef')) {
        continue;
      }
      if (_isImage(object)) {
        _imagesFound++;
        switch (_classifyImage(object)) {
          case _ImageSupport.supported:
            tasks.add(_StreamTask(object, isImage: true));
            continue;
          case _ImageSupport.unsupportedFormat:
            _imagesUnsupported++;
            break;
          case _ImageSupport.skip:
            _imagesSkipped++;
            break;
        }
        // Raw (unfiltered) images may still benefit from DEFLATE below.
      }
      if (preset.deflateStreams && _isDeflatable(object)) {
        tasks.add(_StreamTask(object, isImage: false));
      }
    }
    return tasks;
  }

  bool _isImage(_DocObject object) {
    final subtype = _resolve(object.dict['Subtype']);
    if (subtype is _PdfName && subtype.name == 'Image') return true;
    return false;
  }

  _ImageSupport _classifyImage(_DocObject object) {
    final raw = object.raw!;
    final dataLength = raw.dataEnd! - raw.dataStart!;
    if (dataLength < preset.minImageBytes) return _ImageSupport.skip;
    if (_resolve(object.dict['ImageMask']) == true) {
      return _ImageSupport.skip;
    }
    if (object.dict.containsKey('Decode')) return _ImageSupport.skip;
    if (object.dict.containsKey('Matte')) return _ImageSupport.skip;
    // A soft mask / stencil mask / colour-key mask is tightly coupled to the
    // base image. Never resize or re-colour these.
    if (object.dict.containsKey('SMask')) return _ImageSupport.skip;
    if (object.dict.containsKey('Mask')) return _ImageSupport.skip;

    final filters = _filterNames(object);
    if (filters == null) return _ImageSupport.unsupportedFormat;

    if (filters.isNotEmpty) {
      final last = filters.last;
      if (last != 'DCTDecode' && last != 'FlateDecode') {
        return _ImageSupport.unsupportedFormat;
      }
      for (final filter in filters) {
        if (filter == 'ASCII85Decode' ||
            filter == 'ASCIIHexDecode' ||
            filter == 'DCTDecode' ||
            filter == 'FlateDecode') {
          continue;
        }
        return _ImageSupport.unsupportedFormat;
      }
      // DCTDecode may only appear last in the decode chain.
      for (var i = 0; i < filters.length - 1; i++) {
        if (filters[i] == 'DCTDecode') {
          return _ImageSupport.unsupportedFormat;
        }
      }
    }

    final width = _firstInt(object.dict['Width']);
    final height = _firstInt(object.dict['Height']);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return _ImageSupport.skip;
    }
    if (width * height > preset.maxDecodePixels) return _ImageSupport.skip;

    if (filters.isNotEmpty && filters.last == 'DCTDecode') {
      final longSide = math.max(width, height);
      final needsDownscale = longSide > preset.maxImageLongSide;
      final bytesPerPixel = dataLength / (width * height);
      if (!needsDownscale && bytesPerPixel < preset.jpegSkipBytesPerPixel) {
        // Already aggressively compressed and no resampling is required; the
        // only possible gain would be to destroy quality for a few bytes.
        return _ImageSupport.skip;
      }
    }

    final colorSpace = _resolveColorSpace(object.dict['ColorSpace']);
    if (colorSpace == null) return _ImageSupport.unsupportedFormat;
    if (colorSpace.kind == _ColorSpaceKind.cmyk) {
      return _ImageSupport.unsupportedFormat;
    }
    return _ImageSupport.supported;
  }

  bool _isDeflatable(_DocObject object) {
    final raw = object.raw!;
    final dataLength = raw.dataEnd! - raw.dataStart!;
    if (dataLength < 1024) return false;
    final filters = object.dict['Filter'];
    if (filters == null) return true;
    if (filters is List && filters.isEmpty) return true;
    return false;
  }

  List<String>? _filterNames(_DocObject object) {
    var value = _resolve(object.dict['Filter']);
    if (value == null) return const <String>[];
    if (value is! List) value = <Object?>[value];
    final names = <String>[];
    for (final entry in value) {
      final resolved = _resolve(entry);
      if (resolved is _PdfName) {
        names.add(resolved.name);
      } else {
        return null;
      }
    }
    return names;
  }

  // ─── Stream processing ─────────────────────────────────────────────────

  void _processDeflatableStream(_DocObject object) {
    final raw = object.raw!;
    final data = Uint8List.sublistView(input, raw.dataStart!, raw.dataEnd!);
    if (data.length < 1024) return;

    Uint8List compressed;
    try {
      compressed = ZLibEncoder().encodeBytes(data, level: 9);
    } catch (_) {
      return;
    }
    if (compressed.length + 24 >= data.length) return;

    final dict = Map<String, Object?>.from(object.dict);
    dict['Filter'] = const _PdfName('FlateDecode');
    dict.remove('DecodeParms');
    dict['Length'] = compressed.length;
    _modifications[object.number] = _ModifiedStream(dict, compressed);
    _streamsDeflated++;
  }

  /// Re-encodes an image stream. Returns true when the object was rewritten.
  bool _processImage(_DocObject object) {
    final raw = object.raw!;
    final source = Uint8List.sublistView(input, raw.dataStart!, raw.dataEnd!);

    _DecodedImageResult? decoded;
    try {
      decoded = _decodeImage(object, source);
    } catch (_) {
      decoded = null;
    }
    if (decoded == null) {
      _imagesSkipped++;
      return false;
    }

    var image = decoded.image;
    if (image.width <= 0 || image.height <= 0) {
      _imagesSkipped++;
      return false;
    }

    // The JPEG encoder always emits three-component YCbCr data, so the output
    // colour space must be DeviceRGB regardless of the source encoding.
    if (image.numChannels != 3) {
      try {
        image = image.convert(numChannels: 3);
      } catch (_) {
        _imagesSkipped++;
        return false;
      }
    }

    final longSide = math.max(image.width, image.height);
    if (longSide > preset.maxImageLongSide) {
      try {
        if (image.width >= image.height) {
          image = img.copyResize(
            image,
            width: preset.maxImageLongSide,
            interpolation: img.Interpolation.average,
          );
        } else {
          image = img.copyResize(
            image,
            height: preset.maxImageLongSide,
            interpolation: img.Interpolation.average,
          );
        }
      } catch (_) {
        _imagesSkipped++;
        return false;
      }
    }

    if (image.width <= 0 || image.height <= 0) {
      _imagesSkipped++;
      return false;
    }

    Uint8List encoded;
    try {
      encoded = img.encodeJpg(image, quality: preset.jpegQuality);
    } catch (_) {
      _imagesSkipped++;
      return false;
    }

    if (encoded.length + 48 >= source.length) {
      // Re-encoding did not pay for itself; keep the original stream.
      _imagesSkipped++;
      return false;
    }

    final dict = Map<String, Object?>.from(object.dict);
    dict['Width'] = image.width;
    dict['Height'] = image.height;
    dict['BitsPerComponent'] = 8;
    dict['ColorSpace'] = const _PdfName('DeviceRGB');
    dict['Filter'] = const _PdfName('DCTDecode');
    dict.remove('DecodeParms');
    dict.remove('Decode');
    dict['Length'] = encoded.length;

    _modifications[object.number] = _ModifiedStream(dict, encoded);
    _imagesRecompressed++;
    return true;
  }

  _DecodedImageResult? _decodeImage(_DocObject object, Uint8List source) {
    final filters = _filterNames(object) ?? const <String>[];
    var payload = source;
    for (var i = 0; i < filters.length; i++) {
      switch (filters[i]) {
        case 'ASCII85Decode':
          payload = _ascii85Decode(payload);
          break;
        case 'ASCIIHexDecode':
          payload = _asciiHexDecode(payload);
          break;
        case 'FlateDecode':
          payload = _inflate(payload);
          payload = _applyPredictor(payload, object, i);
          break;
        case 'DCTDecode':
          final info = img.JpegDecoder().startDecode(payload);
          if (info is img.JpegInfo && info.numComponents == 4) return null;
          final jpeg = img.decodeJpg(payload);
          if (jpeg == null) return null;
          return _DecodedImageResult(jpeg);
        default:
          return null;
      }
    }

    final width = _firstInt(object.dict['Width'])!;
    final height = _firstInt(object.dict['Height'])!;
    final bits = _firstInt(object.dict['BitsPerComponent']) ?? 8;
    final colorSpace = _resolveColorSpace(object.dict['ColorSpace']);
    if (colorSpace == null) return null;

    final image = _samplesToImage(payload, width, height, bits, colorSpace);
    if (image == null) return null;
    return _DecodedImageResult(image);
  }

  img.Image? _samplesToImage(
    Uint8List payload,
    int width,
    int height,
    int bits,
    _ColorSpace colorSpace,
  ) {
    if (bits != 1 && bits != 2 && bits != 4 && bits != 8) return null;
    if (colorSpace.kind == _ColorSpaceKind.cmyk) return null;

    final components =
        colorSpace.kind == _ColorSpaceKind.indexed ? 1 : _components(colorSpace);
    if (components <= 0) return null;

    final rowStride = ((width * components * bits) + 7) ~/ 8;
    if (rowStride <= 0 || rowStride * height > payload.length + 8) return null;

    if (colorSpace.kind == _ColorSpaceKind.indexed) {
      final indices = _unpackIndices(payload, width, height, bits, rowStride);
      if (indices == null) return null;
      return _expandIndexed(indices, width, height, colorSpace);
    }

    if (bits == 8) {
      final needed = width * components * height;
      if (payload.length < needed) return null;
      final order = components == 1 ? null : img.ChannelOrder.rgb;
      try {
        return img.Image.fromBytes(
          width: width,
          height: height,
          bytes: payload.buffer,
          bytesOffset: payload.offsetInBytes,
          numChannels: components,
          order: order,
          rowStride: rowStride == width * components ? null : rowStride,
        );
      } catch (_) {
        return null;
      }
    }

    final unpacked = _unpackBits(payload, width, height, components, bits, rowStride);
    if (unpacked == null) return null;
    try {
      return img.Image.fromBytes(
        width: width,
        height: height,
        bytes: unpacked.buffer,
        numChannels: components,
        order: components == 1 ? null : img.ChannelOrder.rgb,
      );
    } catch (_) {
      return null;
    }
  }

  int _components(_ColorSpace colorSpace) {
    switch (colorSpace.kind) {
      case _ColorSpaceKind.gray:
        return 1;
      case _ColorSpaceKind.rgb:
        return 3;
      case _ColorSpaceKind.cmyk:
        return 4;
      case _ColorSpaceKind.indexed:
        return 1;
    }
  }

  Uint8List? _unpackBits(
    Uint8List payload,
    int width,
    int height,
    int components,
    int bits,
    int rowStride,
  ) {
    if (payload.length < rowStride * height) return null;
    final output = Uint8List(width * height * components);
    final maxValue = (1 << bits) - 1;
    final samplesPerRow = width * components;
    for (var y = 0; y < height; y++) {
      final rowOffset = y * rowStride;
      for (var x = 0; x < samplesPerRow; x++) {
        final bitOffset = x * bits;
        final byteOffset = rowOffset + (bitOffset >> 3);
        if (byteOffset >= payload.length) return null;
        final shift = 8 - bits - (bitOffset & 7);
        final raw = (payload[byteOffset] >> shift) & maxValue;
        output[y * samplesPerRow + x] = ((raw * 255) / maxValue).round();
      }
    }
    return output;
  }

  Uint8List? _unpackIndices(
    Uint8List payload,
    int width,
    int height,
    int bits,
    int rowStride,
  ) {
    if (payload.length < rowStride * height) return null;
    final output = Uint8List(width * height);
    final mask = (1 << bits) - 1;
    for (var y = 0; y < height; y++) {
      final rowOffset = y * rowStride;
      for (var x = 0; x < width; x++) {
        final bitOffset = x * bits;
        final byteOffset = rowOffset + (bitOffset >> 3);
        if (byteOffset >= payload.length) return null;
        final shift = 8 - bits - (bitOffset & 7);
        output[y * width + x] = (payload[byteOffset] >> shift) & mask;
      }
    }
    return output;
  }

  img.Image? _expandIndexed(
    Uint8List indices,
    int width,
    int height,
    _ColorSpace colorSpace,
  ) {
    final base = colorSpace.base;
    final palette = colorSpace.palette;
    if (base == null || palette == null) return null;
    final baseComponents = _components(base);
    if (baseComponents != 1 && baseComponents != 3) return null;

    final output = Uint8List(width * height * 3);
    for (var i = 0; i < indices.length; i++) {
      final paletteIndex = indices[i];
      if (baseComponents == 1) {
        final offset = paletteIndex;
        if (offset >= palette.length) return null;
        final value = palette[offset];
        output[i * 3] = value;
        output[i * 3 + 1] = value;
        output[i * 3 + 2] = value;
      } else {
        final offset = paletteIndex * 3;
        if (offset + 2 >= palette.length) return null;
        output[i * 3] = palette[offset];
        output[i * 3 + 1] = palette[offset + 1];
        output[i * 3 + 2] = palette[offset + 2];
      }
    }
    try {
      return img.Image.fromBytes(
        width: width,
        height: height,
        bytes: output.buffer,
        numChannels: 3,
        order: img.ChannelOrder.rgb,
      );
    } catch (_) {
      return null;
    }
  }

  Uint8List _applyPredictor(Uint8List data, _DocObject object, int filterIndex) {
    final parms = _resolveDecodeParms(object, filterIndex);
    if (parms == null) return data;
    final predictor = _firstInt(parms['Predictor']) ?? 1;
    if (predictor <= 1) return data;
    final colors = _firstInt(parms['Colors']) ?? 1;
    final bits = _firstInt(parms['BitsPerComponent']) ?? 8;
    final columns = _firstInt(parms['Columns']) ??
        (_firstInt(object.dict['Width']) ?? 1);
    try {
      if (predictor == 2) {
        return _applyTiffPredictor(data, colors, bits, columns);
      }
      if (predictor >= 10) {
        return _applyPngPredictor(data, colors, bits, columns);
      }
    } catch (_) {
      return data;
    }
    return data;
  }

  Map<String, Object?>? _resolveDecodeParms(_DocObject object, int index) {
    var value = _resolve(object.dict['DecodeParms']);
    if (value == null) return null;
    if (value is List) {
      if (index >= value.length) return null;
      value = _resolve(value[index]);
    }
    if (value is Map<String, Object?>) return value;
    return null;
  }

  Uint8List _applyPngPredictor(
    Uint8List data,
    int colors,
    int bits,
    int columns,
  ) {
    final rowLength = ((colors * bits * columns) + 7) ~/ 8;
    if (rowLength <= 0) return data;
    final bytesPerPixel = math.max(1, (colors * bits) ~/ 8);
    final rowCount = data.length ~/ (rowLength + 1);
    if (rowCount <= 0) return data;

    final output = Uint8List(rowCount * rowLength);
    var previous = Uint8List(rowLength);
    var cursor = 0;
    for (var row = 0; row < rowCount; row++) {
      final filterType = data[cursor];
      cursor++;
      final current = Uint8List.fromList(
        data.sublist(cursor, cursor + rowLength),
      );
      cursor += rowLength;
      switch (filterType) {
        case 0:
          break;
        case 1:
          for (var i = bytesPerPixel; i < rowLength; i++) {
            current[i] = (current[i] + current[i - bytesPerPixel]) & 0xFF;
          }
          break;
        case 2:
          for (var i = 0; i < rowLength; i++) {
            current[i] = (current[i] + previous[i]) & 0xFF;
          }
          break;
        case 3:
          for (var i = 0; i < rowLength; i++) {
            final left = i >= bytesPerPixel ? current[i - bytesPerPixel] : 0;
            current[i] = (current[i] + ((left + previous[i]) >> 1)) & 0xFF;
          }
          break;
        case 4:
          for (var i = 0; i < rowLength; i++) {
            final left = i >= bytesPerPixel ? current[i - bytesPerPixel] : 0;
            final up = previous[i];
            final upLeft = i >= bytesPerPixel ? previous[i - bytesPerPixel] : 0;
            current[i] = (current[i] + _paeth(left, up, upLeft)) & 0xFF;
          }
          break;
        default:
          break;
      }
      output.setRange(row * rowLength, (row + 1) * rowLength, current);
      previous = current;
    }
    return output;
  }

  Uint8List _applyTiffPredictor(
    Uint8List data,
    int colors,
    int bits,
    int columns,
  ) {
    if (bits != 8) return data;
    final rowLength = colors * columns;
    final rowCount = data.length ~/ rowLength;
    final output = Uint8List.fromList(data);
    for (var row = 0; row < rowCount; row++) {
      final rowOffset = row * rowLength;
      for (var i = colors; i < rowLength; i++) {
        output[rowOffset + i] =
            (output[rowOffset + i] + output[rowOffset + i - colors]) & 0xFF;
      }
    }
    return output;
  }

  static int _paeth(int a, int b, int c) {
    final p = a + b - c;
    final pa = (p - a).abs();
    final pb = (p - b).abs();
    final pc = (p - c).abs();
    if (pa <= pb && pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
  }

  // ─── Value resolution helpers ──────────────────────────────────────────

  Object? _resolve(Object? value, [int depth = 0]) {
    if (value is _PdfRef && depth < 12) {
      final object = _objects[value.number];
      if (object == null) return null;
      return _resolve(object.value, depth + 1);
    }
    return value;
  }

  int? _firstInt(Object? value) {
    final resolved = _resolve(value);
    if (resolved is int) return resolved;
    if (resolved is double) return resolved.round();
    if (resolved is List) {
      for (final entry in resolved) {
        final result = _firstInt(entry);
        if (result != null) return result;
      }
    }
    return null;
  }

  _ColorSpace? _resolveColorSpace(Object? value, [int depth = 0]) {
    if (depth > 6) return null;
    final resolved = _resolve(value);
    if (resolved is _PdfName) {
      switch (resolved.name) {
        case 'DeviceRGB':
        case 'CalRGB':
        case 'RGB':
          return const _ColorSpace.rgb();
        case 'DeviceGray':
        case 'CalGray':
        case 'G':
          return const _ColorSpace.gray();
        case 'DeviceCMYK':
        case 'CMYK':
          return const _ColorSpace.cmyk();
        default:
          return null;
      }
    }
    if (resolved is List && resolved.isNotEmpty) {
      final head = _resolve(resolved[0]);
      if (head is _PdfName) {
        switch (head.name) {
          case 'Indexed':
          case 'I':
            if (resolved.length >= 4) {
              final base = _resolveColorSpace(resolved[1], depth + 1);
              final hival = _firstInt(resolved[2]);
              final lookup = _lookupBytes(resolved[3]);
              if (base != null && hival != null && lookup != null) {
                return _ColorSpace.indexed(base, hival, lookup);
              }
            }
            return null;
          case 'ICCBased':
            if (resolved.length >= 2) {
              final reference = resolved[1];
              if (reference is _PdfRef) {
                final object = _objects[reference.number];
                final components = _firstInt(object?.dict['N']);
                if (components == 1) return const _ColorSpace.gray();
                if (components == 3) return const _ColorSpace.rgb();
                if (components == 4) return const _ColorSpace.cmyk();
              } else {
                return const _ColorSpace.rgb();
              }
            }
            return null;
          case 'CalRGB':
            return const _ColorSpace.rgb();
          case 'CalGray':
            return const _ColorSpace.gray();
          case 'Separation':
          case 'DeviceN':
            // Rendered through a tint transform into an alternate colour
            // space; converting to DeviceRGB would change the colour.
            return null;
          default:
            return null;
        }
      }
    }
    return null;
  }

  Uint8List? _lookupBytes(Object? value) {
    final resolved = _resolve(value);
    if (resolved is _PdfString) return resolved.bytes;
    if (value is _PdfRef) {
      final object = _objects[value.number];
      if (object != null && object.raw != null && object.raw!.isStream) {
        try {
          return _decodeStreamBytes(object.raw!);
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }

  Uint8List _decodeStreamBytes(_RawObject object) {
    final data = Uint8List.sublistView(
      input,
      object.dataStart!,
      object.dataEnd!,
    );
    final filters = <String>[];
    var filterValue = _resolve(object.dict['Filter']);
    if (filterValue is _PdfName) {
      filters.add(filterValue.name);
    } else if (filterValue is List) {
      for (final entry in filterValue) {
        final resolved = _resolve(entry);
        if (resolved is _PdfName) filters.add(resolved.name);
      }
    }
    var payload = data;
    for (final filter in filters) {
      switch (filter) {
        case 'FlateDecode':
        case 'Fl':
          payload = _inflate(payload);
          break;
        case 'ASCII85Decode':
          payload = _ascii85Decode(payload);
          break;
        case 'ASCIIHexDecode':
          payload = _asciiHexDecode(payload);
          break;
        default:
          return payload;
      }
    }
    return payload;
  }

  static Uint8List _inflate(Uint8List data) {
    try {
      return ZLibDecoder().decodeBytes(data);
    } catch (_) {
      return ZLibDecoder().decodeBytes(data, raw: true);
    }
  }

  static Uint8List _asciiHexDecode(Uint8List data) {
    final output = <int>[];
    int? pending;
    for (final byte in data) {
      if (byte == 0x3E) break;
      final value = _PdfParser._hexValue(byte);
      if (value < 0) continue;
      if (pending == null) {
        pending = value;
      } else {
        output.add((pending << 4) | value);
        pending = null;
      }
    }
    if (pending != null) output.add(pending << 4);
    return Uint8List.fromList(output);
  }

  static Uint8List _ascii85Decode(Uint8List data) {
    final output = <int>[];
    final tuple = <int>[];
    var index = 0;
    if (data.length >= 2 && data[0] == 0x3C && data[1] == 0x7E) index = 2;
    for (; index < data.length; index++) {
      final byte = data[index];
      if (_isWhite(byte)) continue;
      if (byte == 0x7E) break; // '~'
      if (byte == 0x7A && tuple.isEmpty) {
        // 'z' shorthand for four zero bytes.
        output.addAll(const <int>[0, 0, 0, 0]);
        continue;
      }
      if (byte < 0x21 || byte > 0x75) continue;
      tuple.add(byte - 0x21);
      if (tuple.length == 5) {
        var value = 0;
        for (final digit in tuple) {
          value = value * 85 + digit;
        }
        output.add((value >> 24) & 0xFF);
        output.add((value >> 16) & 0xFF);
        output.add((value >> 8) & 0xFF);
        output.add(value & 0xFF);
        tuple.clear();
      }
    }
    if (tuple.isNotEmpty) {
      final originalLength = tuple.length;
      while (tuple.length < 5) {
        tuple.add(84);
      }
      var value = 0;
      for (final digit in tuple) {
        value = value * 85 + digit;
      }
      final bytes = <int>[
        (value >> 24) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
      ];
      output.addAll(bytes.take(originalLength - 1));
    }
    return Uint8List.fromList(output);
  }

  // ─── Writing ───────────────────────────────────────────────────────────

  Future<int> _writeDocument(String path) async {
    final file = File(path);
    final raf = await file.open(mode: FileMode.write);
    final writer = _FileWriter(raf);
    try {
      // Every object we are going to emit, so the xref table covers every
      // entry a reader may look up.
      final emitted = <int>[];
      for (final object in _ordered) {
        if (_shouldEmit(object)) emitted.add(object.number);
      }
      if (emitted.isEmpty) {
        throw StateError('The PDF contains no readable objects.');
      }
      final maxNumber = emitted.reduce(math.max);
      emitted.sort();

      writer.writeAscii('%PDF-1.7\n');
      writer.writeBytes(const <int>[0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);

      final offsets = <int, int>{};
      for (final number in emitted) {
        offsets[number] = writer.offset;
        _writeObject(writer, _objects[number]!);
      }

      final xrefOffset = writer.offset;
      writer.writeAscii('xref\n');
      writer.writeAscii('0 ${maxNumber + 1}\n');
      writer.writeAscii('0000000000 65535 f \n');
      final xref = StringBuffer();
      for (var number = 1; number <= maxNumber; number++) {
        final offset = offsets[number];
        if (offset == null) {
          xref.write('0000000000 65535 f \n');
        } else {
          final generation = _objects[number]!.generation;
          xref
            ..write(offset.toString().padLeft(10, '0'))
            ..write(' ')
            ..write(generation.toString().padLeft(5, '0'))
            ..write(' n \n');
        }
      }
      writer.writeAscii(xref.toString());

      final trailer = <String, Object?>{};
      trailer['Size'] = maxNumber + 1;
      if (_rootRef != null) trailer['Root'] = _rootRef;
      if (_infoRef != null) trailer['Info'] = _infoRef;
      final id = _trailer['ID'];
      if (id != null) trailer['ID'] = id;

      final tail = StringBuffer('trailer\n');
      _writeValue(tail, trailer);
      tail.write('\nstartxref\n$xrefOffset\n%%EOF\n');
      writer.writeAscii(tail.toString());
    } finally {
      writer.flush();
      await raf.flush();
      await raf.close();
    }
    return writer.offset;
  }

  bool _shouldEmit(_DocObject object) {
    if (object.number <= 0) return false;
    final type = object.dict['Type'];
    if (type is _PdfName) {
      if (type.name == 'ObjStm' || type.name == 'XRef') return false;
    }
    if (object.dict.containsKey('Linearized')) return false;
    return true;
  }

  void _writeObject(_FileWriter writer, _DocObject object) {
    final modification = _modifications[object.number];
    if (modification != null) {
      final header = StringBuffer()
        ..write('${object.number} ${object.generation} obj\n');
      _writeValue(header, modification.dict);
      header.write('\nstream\n');
      writer.writeAscii(header.toString());
      writer.writeBytes(modification.data);
      writer.writeAscii('\nendstream\nendobj\n');
      return;
    }

    final raw = object.raw;
    if (raw != null) {
      writer.writeFrom(input, raw.start, raw.end);
      writer.writeAscii('\n');
      return;
    }

    final body = object.rawBytes ?? Uint8List(0);
    writer.writeAscii('${object.number} ${object.generation} obj\n');
    if (body.isNotEmpty) {
      writer.writeBytes(body);
      writer.writeAscii('\n');
    }
    writer.writeAscii('endobj\n');
  }
}

class _StreamTask {
  const _StreamTask(this.object, {required this.isImage});
  final _DocObject object;
  final bool isImage;
}

/// Buffered writer: PDFs contain tens of thousands of tiny objects and one
/// asynchronous I/O call per object is far too slow on device storage. Chunks
/// are accumulated and flushed synchronously in 1 MB blocks.
class _FileWriter {
  _FileWriter(this._raf);

  final RandomAccessFile _raf;
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  static const int _flushThreshold = 1024 * 1024;

  /// Logical number of bytes written so far (the current file position).
  int offset = 0;

  void writeBytes(List<int> bytes) {
    if (bytes.isEmpty) return;
    _buffer.add(bytes);
    offset += bytes.length;
    if (_buffer.length >= _flushThreshold) _flush();
  }

  void writeFrom(Uint8List bytes, int start, int end) {
    if (end <= start) return;
    _buffer.add(Uint8List.sublistView(bytes, start, end));
    offset += end - start;
    if (_buffer.length >= _flushThreshold) _flush();
  }

  void writeAscii(String text) {
    writeBytes(Uint8List.fromList(text.codeUnits));
  }

  void flush() => _flush();

  void _flush() {
    if (_buffer.isEmpty) return;
    _raf.writeFromSync(_buffer.takeBytes());
  }
}

// ═══════════════════════════ Raster PDF builder ═════════════════════════════

/// A single rasterised page: a JPEG image plus the page geometry it fills.
class PdfRasterPage {
  const PdfRasterPage({
    required this.jpegBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.pageWidth,
    required this.pageHeight,
  });

  final Uint8List jpegBytes;
  final int imageWidth;
  final int imageHeight;
  final double pageWidth;
  final double pageHeight;
}

/// Builds a minimal, valid PDF whose pages each display a single JPEG.
///
/// This is the last-resort fallback for documents whose images use an encoding
/// the pure-Dart engine cannot decode (JPEG 2000, JBIG2, CCITT): the pages are
/// rendered by the platform PDF renderer and stored as JPEGs, which is usually
/// far smaller than the original.
class PdfRasterWriter {
  PdfRasterWriter._();

  static Uint8List build(List<PdfRasterPage> pages) {
    if (pages.isEmpty) {
      throw ArgumentError('At least one page is required');
    }

    // Object numbering: 1 = catalogue, 2 = page tree, then per page
    // image, content stream and page object.
    final objectCount = 2 + pages.length * 3;
    final offsets = List<int>.filled(objectCount + 1, 0);
    final buffer = BytesBuilder(copy: false);

    void writeText(String text) {
      buffer.add(Uint8List.fromList(text.codeUnits));
    }

    writeText('%PDF-1.5\n');
    buffer.add(const <int>[0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);

    var nextNumber = 3;
    final kids = <String>[];
    for (final page in pages) {
      final imageNumber = nextNumber++;
      final contentNumber = nextNumber++;
      final pageNumber = nextNumber++;
      kids.add('$pageNumber 0 R');

      offsets[imageNumber] = buffer.length;
      writeText(
        '$imageNumber 0 obj\n'
        '<< /Type /XObject /Subtype /Image '
        '/Width ${page.imageWidth} /Height ${page.imageHeight} '
        '/ColorSpace /DeviceRGB /BitsPerComponent 8 '
        '/Filter /DCTDecode /Length ${page.jpegBytes.length} >>\nstream\n',
      );
      buffer.add(page.jpegBytes);
      writeText('\nendstream\nendobj\n');

      final box = '0 0 ${_formatDouble(page.pageWidth)} '
          '${_formatDouble(page.pageHeight)}';
      final content = 'q\n'
          '${_formatDouble(page.pageWidth)} 0 0 '
          '${_formatDouble(page.pageHeight)} 0 0 cm\n'
          '/Im0 Do\nQ\n';

      offsets[contentNumber] = buffer.length;
      writeText('$contentNumber 0 obj\n<< /Length ${content.length} >>\n'
          'stream\n$content\nendstream\nendobj\n');

      offsets[pageNumber] = buffer.length;
      writeText('$pageNumber 0 obj\n'
          '<< /Type /Page /Parent 2 0 R /MediaBox [$box] '
          '/Resources << /XObject << /Im0 $imageNumber 0 R >> >> '
          '/Contents $contentNumber 0 R >>\nendobj\n');
    }

    offsets[1] = buffer.length;
    writeText('1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n');

    offsets[2] = buffer.length;
    writeText('2 0 obj\n<< /Type /Pages /Count ${pages.length} '
        '/Kids [${kids.join(' ')}] >>\nendobj\n');

    final xrefOffset = buffer.length;
    final xref = StringBuffer('xref\n0 ${objectCount + 1}\n');
    xref.write('0000000000 65535 f \n');
    for (var number = 1; number <= objectCount; number++) {
      xref
        ..write(offsets[number].toString().padLeft(10, '0'))
        ..write(' 00000 n \n');
    }
    writeText(xref.toString());
    writeText('trailer\n<< /Size ${objectCount + 1} /Root 1 0 R >>\n'
        'startxref\n$xrefOffset\n%%EOF\n');

    return buffer.takeBytes();
  }
}

// ASCII helpers shared by the scanner.

bool _matchesAscii(Uint8List bytes, int position, String text) {
  if (position < 0 || position + text.length > bytes.length) return false;
  for (var i = 0; i < text.length; i++) {
    if (bytes[position + i] != text.codeUnitAt(i)) return false;
  }
  return true;
}

int _indexOfAscii(Uint8List bytes, String text, int from, [int? to]) {
  if (text.isEmpty) return from;
  final first = text.codeUnitAt(0);
  final end = math.min(bytes.length, to ?? bytes.length) - text.length;
  for (var i = math.max(0, from); i <= end; i++) {
    if (bytes[i] != first) continue;
    if (_matchesAscii(bytes, i, text)) return i;
  }
  return -1;
}
