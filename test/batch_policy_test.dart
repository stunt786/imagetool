import 'package:flutter_test/flutter_test.dart';
import 'package:pixeltools/features/image_resize/models/batch_policy.dart';

void main() {
  group('BatchPolicy', () {
    test('only the resize tool processes the whole selection', () {
      // Crop and rotate must never run over the batch: doing so silently
      // ignored the crop and resized every selected image instead.
      expect(
        BatchPolicy.processesWholeBatch(isResizeTool: false, batchCount: 5),
        isFalse,
      );
      expect(
        BatchPolicy.processesWholeBatch(isResizeTool: true, batchCount: 5),
        isTrue,
      );
    });

    test('a single image is never a batch operation', () {
      expect(
        BatchPolicy.processesWholeBatch(isResizeTool: true, batchCount: 1),
        isFalse,
      );
      expect(
        BatchPolicy.processesWholeBatch(isResizeTool: true, batchCount: 0),
        isFalse,
      );
    });

    test('crop and rotate switch to the single-image stepper', () {
      expect(
        BatchPolicy.editsSingleImage(isResizeTool: false, batchCount: 3),
        isTrue,
      );
      expect(
        BatchPolicy.editsSingleImage(isResizeTool: false, batchCount: 1),
        isFalse,
      );
      expect(
        BatchPolicy.editsSingleImage(isResizeTool: true, batchCount: 3),
        isFalse,
      );
    });

    test('position labels are 1-based and clamp a missing index', () {
      expect(BatchPolicy.positionLabel(index: 0, batchCount: 5), '1 of 5');
      expect(BatchPolicy.positionLabel(index: 4, batchCount: 5), '5 of 5');
      expect(BatchPolicy.positionLabel(index: -1, batchCount: 5), '1 of 5');
    });
  });
}
