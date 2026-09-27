/// Decides when the Resize editor works on the whole selection and when it
/// works on a single image.
///
/// Crop and rotate are inherently single-image operations: applying them to
/// everything the user happened to select produced surprising results (the
/// crop was ignored and every image was resized instead). Only the Resize tool
/// is a batch operation.
abstract final class BatchPolicy {
  /// True when the active tool should process every selected image.
  static bool processesWholeBatch({
    required bool isResizeTool,
    required int batchCount,
  }) =>
      isResizeTool && batchCount > 1;

  /// True when the tool edits one image at a time, so the full batch grid is
  /// replaced by a compact "image X of N" stepper.
  static bool editsSingleImage({
    required bool isResizeTool,
    required int batchCount,
  }) =>
      !isResizeTool && batchCount > 1;

  /// Human readable position, e.g. `2 of 5`.
  static String positionLabel({
    required int index,
    required int batchCount,
  }) {
    final position = index < 0 ? 1 : index + 1;
    return '$position of $batchCount';
  }
}
