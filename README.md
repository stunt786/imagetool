# PixelTools ◈ Offline Image & PDF Toolkit

[![Flutter](https://img.shields.io/badge/Flutter-3.2%2B-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.2%2B-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Architecture](https://img.shields.io/badge/Architecture-Feature--First%20Clean-orange)](#-architecture--project-structure)
[![State Management](https://img.shields.io/badge/State%20Management-Riverpod%202.x-00E5FF)](https://riverpod.dev)
[![Privacy](https://img.shields.io/badge/Privacy-100%25%20Offline%20%26%20Private-success)](#-core-guarantees)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Desktop%20%7C%20Web-lightgrey)](#-getting-started)

**PixelTools** is a professional, privacy-first, on-device image and PDF processing toolkit built with Flutter. It delivers heavy-duty document and photo editing capabilities—ranging from **ML Kit Document Scanning** and **AI Magic Inpainting** to **PDF Compression**, **OCR Extraction**, and **Batch Conversion**—completely offline with zero server dependencies or telemetry.

---

## 🌟 Table of Contents

- [Core Guarantees](#-core-guarantees)
- [Feature Overview](#-feature-overview)
  - [Image Tools](#1-image-tools)
  - [PDF Tools](#2-pdf-tools)
  - [File Management & History](#3-file-management--edit-history)
  - [Customization & Settings](#4-customization--settings)
- [Tools Summary Matrix](#-tools-summary-matrix)
- [Architecture & Project Structure](#-architecture--project-structure)
- [Tech Stack & Dependencies](#-tech-stack--dependencies)
- [Getting Started](#-getting-started)
- [Running Tests](#-running-tests)
- [Permissions & Platform Setup](#-permissions--platform-setup)
- [Application Details](#-application-details)

---

## 🔒 Core Guarantees

* **100% Offline & Privacy-First:** No accounts, no cloud uploads, and zero tracking. Every byte is processed strictly on your device.
* **Isolate-Powered Performance:** Heavy operations (JPEG/PNG/WEBP encoding, projective homography perspective warping, ML Kit OCR, and PDF stream compression) execute inside background Dart Isolates (`Isolate.run` and `compute`), keeping the UI silky smooth at 60+ FPS.
* **Sandbox-to-Public Clean Storage:** Two-phase pipeline (`PrivateToPublicPdfManager` & `OutputSaver`) safely processes files in temporary sandbox caches before saving to user-designated public directories (Pictures, Downloads, Documents) with a guaranteed 0 MB orphaned cache cleanup.
* **Modern Material 3 Design:** Fully responsive interface supporting dynamic light and dark themes, gesture-driven controls, and fluid navigation.

---

## 🚀 Feature Overview

### 1. Image Tools

#### 📐 Image Resizer & Manipulation (`/images/resizer`)
- **Dimensions Mode:** Precise width and height adjustments with an aspect ratio lock/unlock toggle.
- **Percentage Mode:** Scale images smoothly from 1% to 500% with real-time numeric and slider inputs.
- **Social Media & Standard Presets:**
  - *Profiles:* Instagram/Facebook/Twitter (1080×1080), LinkedIn (400×400), YouTube (800×800).
  - *Banners & Headers:* Twitter Header (1500×500), Facebook Cover (820×312 desktop / 640×360 mobile), LinkedIn Banner (1584×396), YouTube Banner (2560×1440).
  - *Standard Displays:* Instagram Story (1080×1920), HD (1280×720), Full HD (1920×1080), 2K Square (2048×2048).
- **Smart Target File Size Compression:** Iterative binary search algorithm that downscales and optimizes quality to hit exact target sizes (100 KB, 200 KB, 500 KB, 1 MB, 2 MB).
- **Interactive Cropping:** Freeform and fixed aspect ratios (1:1, 4:3, 16:9, 9:16) with coordinate bounding boxes.
- **Transformations:** 90° clockwise/counter-clockwise step rotation, horizontal/vertical flipping, and free 360° continuous rotation.
- **Multi-Level Undo/Redo:** Non-destructive edit history allowing instant reversion.
- **Export Options:** Choose between JPG, PNG, and WEBP formats with a granular quality slider; option to *Save as New* or *Replace Original*.

#### 🖼️ Collage Builder (`/images/collage`)
- **9 Responsive Grid Layouts:** Single, 2-Horizontal Split, 2-Vertical Split, 2×2 Grid, Featured Top, Featured Left, 2×3 Grid, Mosaic, and T-Layout.
- **Customizable Canvas:** Adjustable inner/outer grid padding, corner radius slider for rounded tiles, and custom canvas background colors.
- **Per-Tile Controls:** Pan and zoom within individual image slots, toggle fit modes (Cover, Contain, Fill), or tap to swap and reorder photos.
- **Interactive Multi-Layer Text Engine:** Add multiple floating captions, drag anywhere across the canvas, pinch-to-scale and rotate, with custom font colors and typography styling.
- **High-Res Export:** Direct canvas rendering to JPG or PNG with optional branding watermark.

#### 🔄 Format Converter (`/images/convert`)
- **Batch Processing:** Convert dozens of images concurrently with real-time queue progress bars.
- **Wide Format Support:**
  - *Input:* JPG, JPEG, PNG, WEBP, BMP, TIFF, GIF, HEIC/HEIF.
  - *Output:* JPG, PNG, WEBP, PDF, BMP, TIFF.
- **Alpha & Transparency Handling:** Clean background color filling when converting translucent PNGs into non-alpha formats (e.g., JPG).
- **Quality & Size Sliders:** Fine-tune lossy compression parameters before saving.

#### 📑 Image to PDF Converter (`/images/to-pdf`)
- **Multi-Image Assembly:** Batch image import with drag-and-drop thumbnail reordering.
- **Page Layout Customization:**
  - *Standard Sizes:* A4, A3, US Letter, US Legal, or Match Image Dimensions.
  - *Orientation:* Portrait, Landscape, or Auto (detects each photo's native aspect ratio).
  - *Fitting Modes:* Fit (with margins), Fill (bleed to edges), Center, Stretch.
  - *Custom Margins:* Configurable top, bottom, left, and right spacing.
- **Quality Modes:** Optimized (compact file sizes for sharing/email) vs. High Quality (maximum fidelity for print).
- **In-App PDF Preview:** Inspect pages, zoom in, and verify layout before exporting.

---

### 2. PDF Tools

#### 📷 Document Scanner & Camera Suite (`/camera`)
- **ML Kit Scanner Integration:** Automated edge detection, boundary cropping, and document rectification powered by Google ML Kit Document Scanner with custom camera fallback.
- **Multi-Page Continuous Capture:** Rapid batch scanning with an interactive review carousel (`DocumentReviewScreen`).
- **16 Specialized Document Filters:**
  - `Magic Color` (vivid document enhancement)
  - `Binarization` (Otsu's adaptive thresholding for razor-sharp black-and-white text)
  - `Shadow Removal` (compensates for uneven lighting and hand shadows)
  - `Enhance`, `Lighten`, `No Shadow`, `Black & White`, `Eco/Draft`, `Grayscale`, `Invert`, `Sepia`, `Warm`, `Cool`, `Dramatic`, `High Contrast B&W`.
- **Keystone Perspective Correction (`PerspectiveCorrectionScreen`):** 4-point interactive quad pin manipulation with a Gaussian elimination linear solver calculating projective homography matrices.
- **AI Magic Remove / Inpainting (`MagicRemoveScreen`):** Interactive brush mask to erase fingers, stamps, stains, or unwanted artifacts using a confidence-based Fast Marching Method with gradient-aware propagation.
- **Direct Export:** Instant export to multi-page PDF or high-resolution images in My Files.

#### 🗜️ PDF Compressor (`/pdfs/compress`)
- **4 Compression Presets:**
  - *Low (0.8x):* Minimal compression, retains vector fidelity and high-res imagery.
  - *Medium (0.5x):* Balanced compression and visual clarity.
  - *High (0.3x):* Significant reduction ideal for email attachments and messaging limits.
  - *Extreme (0.15x):* Aggressive reduction for strict portal upload caps.
- **Isolate-Powered Engine:** Optimizes PDF stream dictionaries, deduplicates embedded fonts, and recompresses raster XObjects via `syncfusion_flutter_pdf`.
- **Metrics & Safety Fallback:** Live before/after file size comparison and percentage reduction; preserves original file if compressed output is larger.

#### 🔗 PDF Merger (`/pdfs/merge`)
- **Combine Multiple Documents:** Merge disparate PDF documents into a single unified file.
- **Drag-and-Drop Reordering:** Visual list displaying document names, page counts, and sizes with instant drag reordering.
- **Preserved Quality:** Retains original vector elements, bookmarks, orientations, and page dimensions.

#### ✂️ PDF Splitter (`/pdfs/split`)
- **4 Split Modes:**
  - *All Pages:* Slices every page into its own standalone single-page PDF.
  - *Page Range:* Extracts continuous or custom page intervals (e.g., pages 3–7) into a new document.
  - *Split by Pages:* Select specific pages from an interactive thumbnail strip rendered via `pdfx`.
  - *By Chunks:* Slices documents into equal batches of *N* pages (e.g., every 2, 5, or 10 pages).

#### 🔤 PDF Converter & OCR Engine (`/pdfs/convert`)
- **PDF to Image:** Extract pages as standalone JPG or PNG images with selectable resolutions: Low (72 DPI), Medium (150 DPI), High (300 DPI).
- **PDF to Plain Text (OCR):** On-device Optical Character Recognition powered by Google ML Kit Text Recognition to extract selectable text from scanned PDFs.
- **PDF to Microsoft Word (.docx):** Transforms PDFs into editable Word documents, utilizing layout bounding box detection to reconstruct paragraphs, headers, and tables into standard OpenXML (.docx) ZIP containers.

#### 📖 In-App PDF Viewer (`/pdf/viewer`)
- Deep-linkable full-screen viewer supporting smooth zooming, panning, jumping to specific pages, and system sharing.

---

### 3. File Management & Edit History

- **Centralized Hub (`/pdfs`):** View all processed images, collages, scanned documents, and PDFs in one unified place.
- **Smart Thumbnails:** Renders actual image previews and live first-page PDF renders instead of generic file icons.
- **Interactive Preview Gallery (`FilePreviewScreen`):** Full-screen viewer with `InteractiveViewer` zoom, pan, resolution & file-size metadata, and direct actions (**Save to Gallery**, **Share**, **Delete**).
- **Persistent Edit History (`/history`):** Complete log of operations, timestamps, file sizes, and tool names backed by `SharedPreferences`.

---

### 4. Customization & Settings

- **Custom Storage Destination:** Pick custom export directories across platform storage (Pictures, Downloads, Documents, or App Sandbox).
- **Global Watermark Engine:**
  - Master toggle to apply custom watermarks to all processed images and PDFs.
  - Configurable text (default: `◈ PixelTools`), color presets (White, Black, Red, Yellow, Blue), opacity slider (10%–100%), and 5 anchor positions (Top-Left, Top-Right, Center, Bottom-Left, Bottom-Right).
- **Privacy Controls:** Option to automatically strip EXIF metadata (GPS coordinates, camera model, timestamp) from output images.
- **One-Click Open Mode:** Option to automatically launch the system file picker immediately upon opening any tool screen.
- **Theme Modes:** System Default, Light Mode, and Dark Mode powered by Material 3 color schemes.

---

## 📊 Tools Summary Matrix

| Tool | Primary Route | Key Capabilities | Supported Inputs | Output Formats |
| :--- | :--- | :--- | :--- | :--- |
| **Image Resizer** | `/images/resizer` | Dimensions, %, Presets, Target Size, Crop, Rotate, Flip | JPG, PNG, WEBP, BMP, etc. | JPG, PNG, WEBP |
| **Collage Builder** | `/images/collage` | 9 Layouts, custom padding/radius, draggable text overlays | JPG, PNG, WEBP | JPG, PNG |
| **Format Converter** | `/images/convert` | Batch conversion, quality control, alpha channel handling | JPG, PNG, WEBP, BMP, TIFF, GIF, HEIC | JPG, PNG, WEBP, PDF, BMP, TIFF |
| **Image to PDF** | `/images/to-pdf` | Multi-image reordering, A4/A3/Letter/Legal, fit modes, margins | JPG, PNG, WEBP | PDF |
| **Document Scanner** | `/camera` | ML Kit edge detection, 16 filters, keystone correction, inpainting | Camera, Live Feed | PDF, JPG |
| **PDF Compressor** | `/pdfs/compress` | 4 Presets (Low to Extreme), isolate-based stream optimization | PDF | PDF |
| **PDF Merger** | `/pdfs/merge` | Combine multi-PDFs, drag-and-drop reorder, retain vector fidelity | Multiple PDFs | PDF |
| **PDF Splitter** | `/pdfs/split` | All pages, range extraction, visual page selection, chunk slicing | PDF | PDF(s) |
| **PDF Converter & OCR** | `/pdfs/convert` | PDF to JPG/PNG (72–300 DPI), OCR to TXT, PDF to DOCX | PDF | JPG, PNG, TXT, DOCX |
| **My Files** | `/pdfs` | Visual file browser, full-screen gallery zoom, share & export | Processed files | — |
| **Settings** | `/settings` | Storage directory, Material 3 theme, EXIF stripping, watermark | — | — |

---

## 🏗️ Architecture & Project Structure

The project adheres to a **Feature-First Clean Architecture** with **Flutter Riverpod 2.x** for reactive state management:

```
lib/
├── core/                         # Cross-cutting infrastructure & shared services
│   ├── app/                      # App root widget & MaterialApp configuration
│   ├── constants/                # App strings, identifiers, and configuration constants
│   ├── models/                   # Core models (OperationProgress, OperationFolder)
│   ├── progress/                 # Progress controller & background progress dialogs
│   ├── router/                   # GoRouter configuration & StatefulShellRoute
│   ├── services/                 # Background isolates, PDF engines, OCR, storage & permissions
│   ├── settings/                 # Global app settings notifier & preferences state
│   ├── theme/                    # Material 3 light/dark theme definitions
│   └── utils/                    # File type detector, size decoders, deferred cleanup
├── features/                     # Modular, feature-first business domains
│   ├── camera/                   # Scanner feed, review carousel, filters, perspective, magic remove
│   ├── collage_builder/          # 9 Grid layouts, canvas customizer, multi-text engine
│   ├── files/                    # File manager, edit history, preview gallery
│   ├── format_converter/         # Batch format conversion screens & controllers
│   ├── home/                     # Dashboard, search bar, tool categories, recent projects
│   ├── image_resize/             # Resize, crop, transforms, target file size compression
│   ├── image_to_pdf/             # Layout setup, page size, margins, reordering, PDF generation
│   ├── pdf_compress/             # Isolate-based PDF compression engine & presets
│   ├── pdf_convert/              # PDF to Image (72-300 DPI), OCR (TXT), and Word DOCX
│   ├── pdf_merge/                # Multi-document PDF combiner & reordering
│   ├── pdf_split/                # 4-Mode PDF splitter with visual thumbnail strip
│   ├── pdf_viewer/               # In-app PDF viewer screen
│   ├── settings/                 # App settings, watermark engine, privacy & about screens
│   └── shell/                    # Persistent bottom navigation shell (`AppShell`)
├── shared/                       # Reusable widgets, models, and shared utilities
│   ├── models/                   # PickedFile, EditHistoryItem
│   ├── notifiers/                # Shared edit state notifiers
│   ├── services/                 # File picker abstraction, watermark rendering helper
│   ├── utils/                    # Multi-platform image saver (IO / Web)
│   └── widgets/                  # Shared app bar, tool card, thumbnail widget, empty states
├── splash_screen.dart            # Native-feel animated splash screen
└── main.dart                     # App initialization and bootstrap
```

---

## 🛠️ Tech Stack & Dependencies

| Category | Package / Tool | Purpose |
| :--- | :--- | :--- |
| **Framework** | [Flutter 3.x](https://flutter.dev) & [Dart 3.x](https://dart.dev) | Cross-platform UI toolkit & programming language |
| **State Management** | [flutter_riverpod ^2.6.1](https://pub.dev/packages/flutter_riverpod) | Reactive, compile-safe dependency injection & state management |
| **Navigation** | [go_router ^17.2.2](https://pub.dev/packages/go_router) | Declarative routing with StatefulShellRoute support |
| **Image Processing** | [image ^4.10.1](https://pub.dev/packages/image) | Pure Dart image decoding, encoding, cropping, and filtering |
| **Image Compression**| [flutter_image_compress ^2.4.0](https://pub.dev/packages/flutter_image_compress) | Fast native image compression |
| **PDF Manipulation** | [syncfusion_flutter_pdf ^28.2.12](https://pub.dev/packages/syncfusion_flutter_pdf) | PDF compression, merging, splitting, and extraction |
| **PDF Generation**   | [pdf ^3.10.7](https://pub.dev/packages/pdf) | Generating PDF documents from images and layouts |
| **PDF Rendering**    | [pdfx ^2.8.0](https://pub.dev/packages/pdfx) | High-performance PDF page rendering and thumbnail generation |
| **On-Device Vision** | [google_mlkit_document_scanner ^0.4.1](https://pub.dev/packages/google_mlkit_document_scanner) | Document edge detection & automated scanning |
| **On-Device OCR**    | [google_mlkit_text_recognition ^0.15.0](https://pub.dev/packages/google_mlkit_text_recognition) | Optical Character Recognition for scanned PDFs and text extraction |
| **Camera & Media**   | [camera ^0.12.0+1](https://pub.dev/packages/camera), [wechat_assets_picker ^9.1.0](https://pub.dev/packages/wechat_assets_picker) | Direct camera feed & gallery selection |
| **Storage & I/O**    | [file_picker ^11.0.2](https://pub.dev/packages/file_picker), [path_provider ^2.1.5](https://pub.dev/packages/path_provider) | Native file selection and path resolution |
| **Platform Sharing** | [share_plus ^10.1.4](https://pub.dev/packages/share_plus) | System share sheet integration |
| **Archive / DOCX**   | [archive ^4.0.9](https://pub.dev/packages/archive) | ZIP container packaging for OpenXML (.docx) exports |

---

## 💻 Getting Started

### Prerequisites

Ensure you have the following installed on your machine:
- **Flutter SDK**: `>= 3.2.0`
- **Dart SDK**: `>= 3.2.0`
- **Android Studio / Xcode**: For Android and iOS builds
- Java 17+ (for Android builds)

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/bnbkio/pixeltools.git
   cd pixeltools
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run the application:**
   ```bash
   flutter run
   ```

### Building for Release

#### Android

```bash
# Build an APK
flutter build apk --release

# Build an Android App Bundle (AAB) for Google Play
flutter build appbundle --release
```

#### iOS

```bash
flutter build ipa --release
```

---

## 🧪 Running Tests

PixelTools includes a comprehensive test suite covering core infrastructure, image manipulation, PDF engines, geometry calculations, and UI widgets:

```bash
# Run all unit and widget tests
flutter test

# Run a specific test suite
flutter test test/core_infrastructure_test.dart
flutter test test/pdf_compression_engine_test.dart
flutter test test/crop_geometry_test.dart
```

To run static code analysis:

```bash
flutter analyze
```

---

## 📱 Permissions & Platform Setup

### Android (`android/app/src/main/AndroidManifest.xml`)

PixelTools utilizes scoped storage and standard Android permissions:
- `android.permission.CAMERA`: Required for live document scanning and photo capture.
- `android.permission.READ_EXTERNAL_STORAGE` / `READ_MEDIA_IMAGES`: Required to load images and PDFs for editing.
- `android.permission.WRITE_EXTERNAL_STORAGE` (API ≤ 28): For saving processed documents.

### iOS (`ios/Runner/Info.plist`)

Ensure the following usage descriptions are present:
- `NSCameraUsageDescription`: "PixelTools requires camera access to scan documents."
- `NSPhotoLibraryUsageDescription`: "PixelTools requires photo library access to import and edit images."
- `NSPhotoLibraryAddUsageDescription`: "PixelTools requires permission to save edited photos to your library."

---

## ℹ️ Application Details

- **App Name:** PixelTools
- **Package ID:** `com.bnbkio.pixeltools`
- **Developer / Publisher:** BNBKIO
- **Contact:** [contact@bnbkio.com](mailto:contact@bnbkio.com)
- **Google Play:** [PixelTools on Google Play Store](https://play.google.com/store/apps/details?id=com.bnbkio.pixeltools)

---

## 📄 License

This project is proprietary software developed by BNBKIO. All rights reserved.
