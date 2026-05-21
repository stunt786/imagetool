Act as a Senior Flutter Developer & UI/UX Designer. Create a robust, production-ready Image Utility Module for a Flutter app (Android & iOS). This module focuses exclusively on Image Manipulation: Resize, Crop, Rotate, and Smart Compression.

🔹 CORE FEATURES:

1. 🖼️ Interactive Image Editor Screen:
   - A unified screen that loads an image from the device.
   - Central Canvas: Displays the image with smooth zoom/pan capabilities (using `InteractiveViewer`).
   - Bottom Tool Sheet: Tabs or segmented control to switch between [Crop], [Rotate], [Resize/Compress].
   - Top App Bar: "Cancel" (discard changes) and "Save" (apply all changes).

2. ✂️ Crop Feature:
   - Use `image_cropper` package for the UI interaction (drag handles, aspect ratio locking).
   - Preset Aspect Ratios: Freeform, 1:1 (Square), 4:3, 16:9, 9:16.
   - Real-time preview of the crop area.
   - Logic: When applied, return the cropped image data without saving to disk yet (keep in memory/state).

3. 🔄 Rotate & Flip Feature:
   - Buttons: Rotate Left (90°), Rotate Right (90°).
   - Slider: Free rotation (0-360°) with snap-to-90° options.
   - Flip: Horizontal and Vertical flip buttons.
   - Logic: Apply transformations using the `image` package (dart:image) in a background isolate. Handle EXIF orientation correctly.

4. 📏 Advanced Resize & Smart Compression Feature (NEW):
   
   A. Target File Size Compression (Smart Resize):
      - Input: User selects a target file size: [100 KB, 200 KB, 500 KB, 1 MB, 2 MB].
      - Logic: Implement an iterative binary search algorithm or step-down approach:
        1. Start with original quality (100%).
        2. Compress to JPEG/WebP.
        3. Check file size. If > Target, reduce quality by 10% or reduce dimensions by 10%.
        4. Repeat until file size is <= Target OR minimum quality (10%) is reached.
      - UI: Show a slider for "Target Size" with labels (100KB - 2MB). Display estimated final size in real-time if possible, or show a "Processing..." indicator during the iterative compression.

   B. Social Media Presets (Dimensions & Aspect Ratios):
      - Dropdown Category: "Profile Picture" vs "Banner/Cover".
      - Profile Picture Presets:
        • Instagram/FB/Twitter Profile: 1080x1080 (1:1)
        • LinkedIn Profile: 400x400 (1:1)
        • YouTube Profile: 800x800 (1:1)
      - Banner/Cover Presets:
        • Twitter Header: 1500x500 (3:1)
        • Facebook Cover: 820x312 (Desktop) / 640x360 (Mobile)
        • LinkedIn Banner: 1584x396 (4:1)
        • YouTube Banner: 2560x1440 (16:9) - Note: Safe area centering.
      - Logic: When a preset is selected, automatically resize and crop (center-crop) the image to match these exact dimensions.

   C. Manual Resize:
      - Input fields for Width/Height with "Lock Aspect Ratio" toggle.
      - Output format selection: JPG, PNG, WebP.
      - Quality Slider: For JPG/WebP (1-100%).

🔹 STORAGE & PERMISSIONS:
- Permissions: Use `permission_handler` for `photos` (iOS) and `storage/images` (Android 13+).
- Saving Strategy:
  - Save final file to: `getApplicationDocumentsDirectory()/<dir>/`.
  - Generate unique filenames: `img_YYYYMMDD_HHMMSS.ext`.
  - After saving, show a SnackBar with:
    • Original Size vs. New Size (e.g., "5.2MB → 98KB").
    • Button: "View in Gallery" or "Share".

🔹 UI/UX DESIGN:

- Dark/Light mode support.
- Loading States: Show a circular progress indicator with percentage during heavy processing (especially for Target Size Compression which may take multiple iterations).
- Error Handling: 
  - If image > 50MB, warn user.
  - If target size is impossible (e.g., trying to compress a complex 4K image to 10KB without losing all detail), show a warning: "Minimum quality reached. Final size: X KB."

🔹 ARCHITECTURE & TECH STACK:
- Flutter 3.x, Dart 3.x (Null-safe)
- State Management: Riverpod (use `AsyncNotifier` for processing states).
- Packages:
  - `image_picker`: For selecting source image.
  - `image_cropper`: For crop UI.
  - `image`: For backend pixel manipulation (resize/rotate/flip/compress).
  - `path_provider`: For storage paths.
  - `permission_handler`: For permissions.
  - `flutter_image_compress`: Optional, but `image` package is sufficient for JPEG compression logic.
- Structure:
  - `features/image_editor/`:
    - `image_editor_screen.dart` (UI)
    - `image_processor_service.dart` (Logic/Isolates)
    - `models/social_presets.dart` (Constants for dimensions)
    - `state/image_editor_state.dart` (Riverpod state)
  - `core/services/storage_service.dart` (Shared file saving logic)

🔹 DELIVERABLES:
1. `pubspec.yaml` dependencies.
2. `social_presets.dart`: A map/list of constants for social media dimensions.
3. `image_processor_service.dart`: 
   - Method `compressToTargetSize(Uint8List bytes, int targetBytes)` implementing the iterative compression logic.
   - Method `resizeToPreset(Uint8List bytes, String presetName)` handling center-crop and resize.
   - Standard resize/rotate methods using `compute()`.
4. `image_editor_screen.dart`: The main UI integrating all features.
5. `storage_service.dart`: Method to save `Uint8List` to app directory.
6. `main.dart` snippet showing navigation.

Write clean, modular code. Ensure heavy image processing is offloaded to isolates (`compute`) to keep the UI at 60fps. Specifically optimize the `compressToTargetSize` function to avoid infinite loops.