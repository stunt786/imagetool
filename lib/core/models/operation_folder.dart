import 'package:flutter/foundation.dart';

/// The tool that produced an operation.
///
/// [folderName] is the on-disk directory name, so files stay discoverable
/// outside the app as well.
enum OperationKind {
  resize('Resize', 'Resize'),
  convert('Convert', 'Converter'),
  imageToPdf('Image to PDF', 'Image_to_PDF'),
  collage('Collage', 'Collage'),
  scan('Scan', 'Scanner'),
  pdfMerge('Merge PDF', 'PDF_Merge'),
  pdfSplit('Split PDF', 'PDF_Split'),
  pdfCompress('Compress PDF', 'PDF_Compress'),
  pdfConvert('PDF to Images', 'PDF_Convert'),
  imageEdit('Image Edit', 'Image_Edit'),
  other('Other', 'Other');

  const OperationKind(this.label, this.folderName);

  /// Human readable tool name, e.g. `Image to PDF`.
  final String label;

  /// Directory name used on disk, e.g. `Image_to_PDF`.
  final String folderName;

  static OperationKind fromName(String? name) {
    if (name == null) return OperationKind.other;
    for (final kind in OperationKind.values) {
      if (kind.name == name) return kind;
    }
    return OperationKind.other;
  }
}

/// Lifecycle of a multi-file operation.
///
/// An operation is only ever marked [completed] once every expected output has
/// been written and recorded.
enum OperationStatus {
  pending,
  processing,
  completed,
  failed,
  cancelled;

  static OperationStatus fromName(String? name) {
    if (name == null) return OperationStatus.pending;
    for (final status in OperationStatus.values) {
      if (status.name == name) return status;
    }
    return OperationStatus.pending;
  }
}

/// One output file produced by an [OperationFolder].
@immutable
class AppFileItem {
  const AppFileItem({
    required this.id,
    required this.operationId,
    required this.path,
    required this.fileName,
    required this.extension,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
    this.isPdf = false,
    this.isImage = false,
    this.thumbnailPath,
    this.pageCount,
  });

  final String id;
  final String operationId;
  final String path;
  final String fileName;

  /// Lower-case extension without the dot.
  final String extension;
  final String mimeType;
  final int sizeBytes;
  final DateTime createdAt;
  final bool isPdf;
  final bool isImage;

  /// Cached preview path; may be null until generated.
  final String? thumbnailPath;

  /// Number of pages/items when known (PDF page count, group size).
  final int? pageCount;

  String get baseName {
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  AppFileItem copyWith({
    String? path,
    String? fileName,
    String? extension,
    String? mimeType,
    int? sizeBytes,
    String? thumbnailPath,
    int? pageCount,
  }) {
    return AppFileItem(
      id: id,
      operationId: operationId,
      path: path ?? this.path,
      fileName: fileName ?? this.fileName,
      extension: extension ?? this.extension,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      createdAt: createdAt,
      isPdf: isPdf,
      isImage: isImage,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      pageCount: pageCount ?? this.pageCount,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'operationId': operationId,
        'path': path,
        'fileName': fileName,
        'extension': extension,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'createdAt': createdAt.toIso8601String(),
        'isPdf': isPdf,
        'isImage': isImage,
        'thumbnailPath': thumbnailPath,
        'pageCount': pageCount,
      };

  static AppFileItem? fromJson(Map<String, Object?> json) {
    final path = json['path'] as String?;
    final id = json['id'] as String?;
    if (path == null || id == null) return null;
    return AppFileItem(
      id: id,
      operationId: json['operationId'] as String? ?? '',
      path: path,
      fileName: json['fileName'] as String? ?? path.split('/').last,
      extension: json['extension'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      isPdf: json['isPdf'] as bool? ?? false,
      isImage: json['isImage'] as bool? ?? false,
      thumbnailPath: json['thumbnailPath'] as String?,
      pageCount: (json['pageCount'] as num?)?.toInt(),
    );
  }
}

/// A single logical operation: one run of a tool that may produce many files.
@immutable
class OperationFolder {
  const OperationFolder({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.directoryPath,
    required this.createdAt,
    required this.modifiedAt,
    this.itemCount = 0,
    this.thumbnailPath,
    this.status = OperationStatus.pending,
    this.expectedItems = 0,
    this.tags = const <String>[],
    this.errorMessage,
  });

  final String id;
  final OperationKind kind;
  final List<String> tags;

  /// Editable, human friendly name, e.g. `Resize — 27 Sep 2026, 7:15 PM`.
  final String displayName;

  final String directoryPath;
  final DateTime createdAt;
  final DateTime modifiedAt;

  /// Number of files actually recorded.
  final int itemCount;

  /// Number of files the operation intended to produce.
  final int expectedItems;

  final String? thumbnailPath;
  final OperationStatus status;
  final String? errorMessage;

  bool get isComplete => status == OperationStatus.completed;
  bool get isIncomplete =>
      status == OperationStatus.failed ||
      status == OperationStatus.cancelled ||
      status == OperationStatus.processing ||
      status == OperationStatus.pending;

  /// `Resize — 27 Sep 2026, 7:15 PM`
  static String buildDisplayName(OperationKind kind, DateTime at) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final period = at.hour < 12 ? 'AM' : 'PM';
    final minute = at.minute.toString().padLeft(2, '0');
    return '${kind.label} — ${at.day} ${months[at.month - 1]} ${at.year}, '
        '$hour12:$minute $period';
  }

  OperationFolder copyWith({
    String? displayName,
    DateTime? modifiedAt,
    int? itemCount,
    int? expectedItems,
    String? thumbnailPath,
    OperationStatus? status,
    List<String>? tags,
    String? errorMessage,
    bool clearError = false,
  }) {
    return OperationFolder(
      id: id,
      kind: kind,
      displayName: displayName ?? this.displayName,
      directoryPath: directoryPath,
      createdAt: createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      itemCount: itemCount ?? this.itemCount,
      expectedItems: expectedItems ?? this.expectedItems,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      status: status ?? this.status,
      tags: tags ?? this.tags,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'kind': kind.name,
        'displayName': displayName,
        'directoryPath': directoryPath,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'itemCount': itemCount,
        'expectedItems': expectedItems,
        'thumbnailPath': thumbnailPath,
        'status': status.name,
        'tags': tags,
        'errorMessage': errorMessage,
      };

  static OperationFolder? fromJson(Map<String, Object?> json) {
    final id = json['id'] as String?;
    final directoryPath = json['directoryPath'] as String?;
    if (id == null || directoryPath == null) return null;
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.now();
    final kind = OperationKind.fromName(json['kind'] as String?);
    return OperationFolder(
      id: id,
      kind: kind,
      displayName: json['displayName'] as String? ??
          buildDisplayName(kind, createdAt),
      directoryPath: directoryPath,
      createdAt: createdAt,
      modifiedAt: DateTime.tryParse(json['modifiedAt'] as String? ?? '') ??
          createdAt,
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      expectedItems: (json['expectedItems'] as num?)?.toInt() ?? 0,
      thumbnailPath: json['thumbnailPath'] as String?,
      status: OperationStatus.fromName(json['status'] as String?),
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          const <String>[],
      errorMessage: json['errorMessage'] as String?,
    );
  }
}

/// Sort orders offered by Files and History.
enum FileSortOrder {
  newestFirst('Newest'),
  oldestFirst('Oldest'),
  nameAsc('Name A–Z'),
  nameDesc('Name Z–A'),
  sizeDesc('Largest'),
  sizeAsc('Smallest');

  const FileSortOrder(this.label);

  final String label;
}

/// Filter chip used by Files.
enum FileFilter {
  all('All'),
  images('Images'),
  pdfs('PDFs'),
  recent('Recent');

  const FileFilter(this.label);

  final String label;
}
