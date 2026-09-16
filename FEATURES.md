# PixelTools — Feature Specification & Inventory

> **PixelTools: Image & PDF Editor**
> *Professional, privacy-first, fully offline on-device image and document processing toolkit built with Flutter.*

---

## 📋 Table of Contents

1. [Architectural Overview & Core Guarantees](#1-architectural-overview--core-guarantees)
2. [Application Navigation & Shell](#2-application-navigation--shell)
3. [Image Tools](#3-image-tools)
   - [3.1 Image Resizer & Manipulation](#31-image-resizer--manipulation)
   - [3.2 Collage Builder](#32-collage-builder)
   - [3.3 Format Converter](#33-format-converter)
   - [3.4 Image to PDF Converter](#34-image-to-pdf-converter)
4. [PDF Tools](#4-pdf-tools)
   - [4.1 Document Camera & Scanner](#41-document-camera--scanner)
   - [4.2 PDF Compressor](#42-pdf-compressor)
   - [4.3 PDF Merger](#43-pdf-merger)
   - [4.4 PDF Splitter](#44-pdf-splitter)
   - [4.5 PDF Converter & OCR Engine](#45-pdf-converter--ocr-engine)
5. [File Management & History](#5-file-management--history)
6. [Settings & Customization](#6-settings--customization)
7. [Shared Services & Cross-Cutting Capabilities](#7-shared-services--cross-cutting-capabilities)
8. [Summary Matrix of Tools](#8-summary-matrix-of-tools)

---

## 1. Architectural Overview & Core Guarantees

* **100% Offline & Private:** Zero server dependencies. Every byte is processed strictly on-device without network calls, telemetry leaks, or cloud uploads.
* **Isolate-Powered Performance:** Long-running, computationally heavy operations (JPEG/PNG/WEBP encoding, homography perspective warping, ML Kit OCR, and PDF parsing) execute inside background Dart Isolates (`compute` and `Isolate.run`), keeping the UI thread running smoothly at 60 FPS.
* **Feature-First Architecture:** Modular separation where each tool maintains its own models, notifiers, presentation screens, and helper services.
* **Reactive State Management:** Powered by Flutter Riverpod 2.x using `Notifier` and `AsyncNotifier` patterns for clean separation of UI and business logic.
* **Scoped Storage & Sandbox Compliance:** Implements a two-phase "Sandbox-to-Public" pipeline (`PrivateToPublicPdfManager`) that isolates working files in temporary caches before exporting to user-designated public directories (Downloads, Documents, Pictures).

---

## 2. Application Navigation & Shell

* **Stateful Shell Route (`AppShell`):**
  * Persistent bottom navigation bar across primary sections without resetting tab states.
  * Adaptive layout handling top/bottom safe areas and ambient lighting accents.
* **Primary Navigation Tabs:**
  1. **Home (`/tools`):**
     * Dynamic header with live search bar to quickly find tools and past edits.
     * Categorized quick-action grid for Image Tools and PDF Tools.
     * Recent Projects carousel with thumbnails and direct file opening.
  2. **Camera (`/camera`):**
     * Instant document scanning launch powered by Google ML Kit with custom camera fallback.
  3. **Files (`/pdfs`):**
     * Centralized file manager displaying all processed exports with item counts and bulk clearing.
  4. **Settings (`/settings`):**
     * Storage paths, theme preferences, privacy options, and global watermark configuration.
* **Onboarding Experience (`/onboarding`):**
  * 3-step walkthrough introducing Privacy-First processing, the All-in-One Toolkit, and Fast workflows.
  * Remembers completion status using `SharedPreferences`.

---

## 3. Image Tools

### 3.1 Image Resizer & Manipulation
*Route: `/images/resizer`*

* **Resize Modes:**
  * **Dimensions Mode:** Precise Width and Height input with a toggle to lock or unlock the original aspect ratio.
  * **Percentage Mode:** Scale images from 1% up to 500% with real-time slider and numeric input.
  * **Social Media & Standard Presets:**
    * *Profile Pictures:* Instagram/Facebook/Twitter (1080×1080), LinkedIn (400×400), YouTube (800×800).
    * *Banners & Covers:* Twitter Header (1500×500), Facebook Cover (820×312 desktop / 640×360 mobile), LinkedIn Banner (1584×396), YouTube Banner (2560×1440).
    * *Standard Displays:* Instagram Story (1080×1920), HD (1280×720), Full HD (1920×1080), 2K Square (2048×2048).
    * Automatic center-crop and aspect-fit handling for presets.
  * **Best Fit Mode:** Fit within a maximum bounding box without distorting aspect ratios.
  * **Smart Compression (Target File Size):**
    * Iterative binary search algorithm targeting exact file sizes (100 KB, 200 KB, 500 KB, 1 MB, 2 MB).
    * Dynamic quality reduction and downscaling to meet target constraints without infinite loops.
* **Interactive Cropping:**
  * Preset aspect ratio bounding: Freeform, 1:1 Square, 4:3 Landscape, 16:9 Widescreen, 9:16 Portrait.
  * Manual coordinate boxes (X, Y, Width, Height) with full-screen interactive preview.
* **Transformations (Rotate & Flip):**
  * Step rotation: 90° Clockwise and 90° Counter-Clockwise.
  * Mirroring: Horizontal flip and Vertical flip.
  * Free continuous rotation slider (0° to 360°).
* **Format & Quality Export:**
  * Encoders for JPG, PNG, and WEBP.
  * Quality level selector: 100% (Best), 90% (High), 80% (Balanced), 70% (Medium), 60% (Small).
  * Choice to **Save as New** or **Replace Original**.
  * Multi-level Undo/Redo stack for non-destructive edits.

---

### 3.2 Collage Builder
*Route: `/images/collage`*

* **Smart Grid Layouts:**
  * Pre-built responsive layouts:
    * Single Image
    * 2 Horizontal Split
    * 2 Vertical Split
    * 2×2 Grid (4 images)
    * Featured Top (1 large top + 2 bottom)
    * Featured Left (1 large left + 2 right)
    * 2×3 Grid (6 images)
    * Mosaic (5 images)
    * T-Layout (1 wide top + 3 bottom)
  * Auto-selects optimal layout based on the number of imported photos.
* **Canvas Customization:**
  * Adjustable inner and outer gap spacing.
  * Corner radius slider for rounded image tiles.
  * Canvas background color selection.
* **Image Tile Controls:**
  * Pan and zoom within individual grid slots.
  * Fit modes: Cover, Contain, Fill.
  * Tap to swap images between slots or remove individual photos.
* **Interactive Multi-Text Engine:**
  * Add multiple floating text captions.
  * Drag to position freely anywhere on the canvas.
  * Pinch-to-scale and rotate gestures for each text layer.
  * Custom font families, typography size, and color picker.
* **Export:**
  * High-resolution canvas rendering to JPG/PNG with optional watermark.

---

### 3.3 Format Converter
*Route: `/images/convert`*

* **Batch Conversion:** Process multiple files in a single pass.
* **Supported Formats:**
  * *Input Formats:* JPG, JPEG, PNG, WEBP, BMP, TIFF, GIF, HEIC/HEIF.
  * *Output Formats:* JPG, PNG, WEBP, PDF, BMP, TIFF.
* **Options & Controls:**
  * Compression quality slider for lossy formats.
  * Alpha channel / transparency handling when converting to non-alpha formats (e.g., PNG to JPG).
  * Real-time progress bar for batch queues.
  * Save all converted files at once or save individual files.
  * Direct file sharing via system share sheet.

---

### 3.4 Image to PDF Converter
*Route: `/images/to-pdf`*

* **Multi-Image Assembly:**
  * Batch image import with drag-and-drop or tap-to-reorder thumbnail strip.
  * Individual page rotation, replacement, or deletion.
* **Document Layout Settings:**
  * *Standard Page Sizes:* A4, A3, US Letter, US Legal, or Match Image Dimensions.
  * *Orientation:* Portrait, Landscape, or Auto (detects each image's native orientation).
  * *Image Fitting:* Fit (contain with margins), Fill (bleed to edges), Center, Stretch.
  * *Margins:* Customizable Top, Bottom, Left, and Right margin distances.
* **Quality Modes:**
  * *Optimized:* Compresses images for compact file sizes suitable for email/web sharing.
  * *High Quality:* Preserves maximum image detail for printing.
* **Preview & Export:**
  * Integrated PDF rendering to inspect the generated document before saving.
  * Save directly to public device storage or share.

---

## 4. PDF Tools

### 4.1 Document Camera & Scanner
*Route: `/camera`*

* **Scanner Integration:**
  * Google ML Kit Document Scanner integration providing automated edge detection and boundary cropping.
  * Fallback camera viewfinder with alignment guide overlays and flash/camera toggle.
  * Multi-page continuous batch capture mode.
* **Document Review & Processing Suite (`DocumentReviewScreen`):**
  * Visual page carousel with quick navigation and page status.
  * Add additional pages, retake flawed shots, or reorder.
* **16 Specialized Document Filters:**
  * `Magic Color`: Balances contrast, saturation, and exposure for vivid documents.
  * `Binarization`: Otsu's adaptive thresholding algorithm creating sharp, high-contrast black-and-white text.
  * `Shadow Removal`: Compensates for uneven ambient lighting and hand shadows.
  * `Enhance`, `Lighten`, `No Shadow`, `Black & White`, `Eco/Draft`, `Grayscale`, `Invert`, `Sepia`, `Warm`, `Cool`, `Dramatic`, `High Contrast B&W`.
* **Perspective Correction (Keystone Rectification):**
  * 4-point interactive quad pin manipulation.
  * Gaussian elimination linear system solver calculating projective homography matrix.
  * Warps perspective-skewed photos into flat rectangular documents.
* **Magic Remove / Inpainting Tool:**
  * Removes unwanted artifacts, fingers, stamps, or smudges from scanned pages.
  * Interactive brush mask painting with adjustable radius and undo support.
  * Confidence-based Fast Marching Method with gradient-aware propagation and bilateral edge smoothing running in a background isolate.
* **Export Workflows:**
  * Seamless one-tap export to PDF (pipes directly into the Image to PDF engine) or saves as image files in My Files.

---

### 4.2 PDF Compressor
*Route: `/pdfs/compress`*

* **4 Compression Presets:**
  * *Low (0.8 factor):* Minimal compression, highest visual and vector fidelity.
  * *Medium (0.5 factor):* Balanced compression and visual quality.
  * *High (0.3 factor):* Strong compression, ideal for email and messaging limits.
  * *Extreme (0.15 factor):* Maximum reduction for strict portal upload requirements.
* **Processing Architecture:**
  * Background isolate execution using `syncfusion_flutter_pdf`.
  * Optimizes PDF stream dictionaries, deduplicates fonts, and recompresses embedded raster XObjects.
  * Displays percentage size reduction and before/after file metrics.
  * Safety fallback: if compressed output exceeds input size, preserves original file.

---

### 4.3 PDF Merger
*Route: `/pdfs/merge`*

* **Document Combination:**
  * Combine multiple separate PDF documents into a single cohesive file.
  * Visual list displaying document names, individual page counts, and file sizes.
  * Drag-and-drop or button-based file reordering.
  * High-speed merge retaining original page sizes, orientations, and vector graphics.

---

### 4.4 PDF Splitter
*Route: `/pdfs/split`*

* **4 Split Modes:**
  * *All Pages:* Splits every individual page into its own distinct single-page PDF.
  * *Page Range:* Extracts a continuous or custom range of pages into a single new PDF document.
  * *Split by Pages:* Select specific pages from a visual thumbnail grid to extract each as a standalone file.
  * *By Chunks:* Automatically slices documents into batches of N pages (e.g., 2, 5, or 10 pages per file).
* **Interactive Page Picker:**
  * Thumbnail strip rendered via `pdfx` for fast page identification.
  * One-tap "Select All" and "Clear Selection" options.

---

### 4.5 PDF Converter & OCR Engine
*Route: `/pdfs/convert`*

* **PDF to Image Conversion:**
  * Extracts pages as standalone high-resolution JPG or PNG images.
  * Resolution / DPI selection: Low (72 DPI), Medium (150 DPI), High (300 DPI).
  * Range controls: Convert all pages, first N pages, or a custom page range.
* **PDF to Plain Text (OCR):**
  * Optical Character Recognition powered on-device by Google ML Kit Text Recognition.
  * Converts scanned documents and non-selectable PDFs into clean, selectable `.txt` files.
* **PDF to Microsoft Word (DOCX):**
  * Converts PDF documents into editable `.docx` files.
  * ML Kit bounding box analysis detecting text paragraphs, headers, and tabular structures.
  * Directly packages generated XML into standard OpenXML (.docx) ZIP containers.

---

## 5. File Management & History

*Route: `/pdfs` (Files tab) and Home recent section*

* **Edit History Tracking:**
  * Automatically records all exported items with tool name, timestamp, output path, and file size.
  * Persisted across app restarts via `shared_preferences`.
* **Visual File Browser:**
  * Renders real image thumbnails and PDF first-page previews instead of generic icons.
  * File count badge and quick-clear history action.
* **Full-Screen Preview Gallery (`FilePreviewScreen`):**
  * Swipeable horizontal page view through processed files.
  * Interactive zoom and pan (`InteractiveViewer`) for detailed inspection.
  * Header with file details, resolution, and timestamp.
  * Direct action buttons: **Save to Gallery**, **Share**, and **Delete**.

---

## 6. Settings & Customization

*Route: `/settings`*

* **Storage Management:**
  * Custom save folder picker allowing users to redirect output directories.
  * Handles platform storage directories (`Pictures/PixelTools`, `Downloads/PixelTools`, and iOS app documents).
* **Appearance & Theme:**
  * System Default, Light Mode, and Dark Mode with dynamic Material 3 color schemes.
* **General Preferences:**
  * **One-Click Open:** Automatically launches the file picker immediately upon opening any tool screen.
  * **Strip EXIF Data:** Security feature that strips GPS coordinates, camera models, and capture metadata from output images.
  * Help, Contact Us, Rate App, and Share App dialogs.
* **Global Watermark Engine:**
  * Master switch to automatically apply custom watermarking to all generated images and PDFs.
  * Custom text input (default: `◈ PixelTools`).
  * Color presets (White, Black, Red, Yellow, Blue).
  * Watermark opacity slider (10% to 100%).
  * 5 Placement positions: Top-Left, Top-Right, Center, Bottom-Left, Bottom-Right.
  * Automatically renders brand diamond emblem, text, and translucent backdrop pill.

---

## 7. Shared Services & Cross-Cutting Capabilities

* **Private-to-Public PDF Manager (`PrivateToPublicPdfManager`):**
  * Manages temporary sandbox files and safely promotes them to public storage via Storage Access Framework.
  * Strict cleanup guarantee ensuring 0 MB left in cache after sessions.
* **Native Image Saver (`ImageSaver`):**
  * Cross-platform file writer handling Android Scoped Storage (`Pictures` directory), iOS photo library/documents, and web downloads.
* **Watermark Helper (`WatermarkHelper`):**
  * Shared canvas drawing utility applying watermark logos and typography directly onto pixel buffers before compression.
* **AdMob Monetization & Capping (`AdService` & `InterstitialTracker`):**
  * Integrated Google Mobile Ads for Banner and Interstitial formats.
  * Smart frequency tracker preventing disruptive ads during active user workflows.
* **Premium & Pro Architecture (`PremiumScreen`):**
  * Pre-configured UI comparison table for Pro subscriptions (unlimited processing, ad removal, full EXIF tools) with Yearly and Lifetime purchase options.

---

## 8. Summary Matrix of Tools

| Tool | Primary Route | Key Features | Supported Input | Supported Output |
| :--- | :--- | :--- | :--- | :--- |
| **Image Resizer** | `/images/resizer` | Dimensions, %, Presets, Best Fit, Smart Compression, Crop, Rotate, Flip | JPG, PNG, WEBP, BMP, etc. | JPG, PNG, WEBP |
| **Collage Builder** | `/images/collage` | 9 Layout grids, gap/radius, multi-text layers with rotation/scale | JPG, PNG, WEBP | JPG, PNG |
| **Format Converter** | `/images/convert` | Batch conversion, quality slider, alpha handling | JPG, PNG, WEBP, BMP, TIFF, GIF, HEIC | JPG, PNG, WEBP, PDF, BMP, TIFF |
| **Image to PDF** | `/images/to-pdf` | A4/A3/Letter/Legal, margins, orientation, fit modes, drag reorder | JPG, PNG, WEBP | PDF |
| **Document Scanner** | `/camera` | ML Kit edge detection, 16 filters, keystone perspective warp, magic remove inpainting | Camera, Live Feed | PDF, JPG |
| **PDF Compressor** | `/pdfs/compress` | 4 compression levels (Low, Medium, High, Extreme), isolate-based | PDF | PDF |
| **PDF Merger** | `/pdfs/merge` | Combine multi-document PDFs, drag reordering, retain vector quality | Multiple PDFs | PDF |
| **PDF Splitter** | `/pdfs/split` | All pages, page range, select specific pages, split into chunks of N | PDF | PDF(s) |
| **PDF Converter & OCR** | `/pdfs/convert` | PDF to JPG/PNG (72-300 DPI), PDF to TXT (OCR), PDF to DOCX (tables & text) | PDF | JPG, PNG, TXT, DOCX |
| **My Files** | `/pdfs` | Thumbnail preview, full-screen gallery, zoom/pan, share, delete, history | All generated files | — |
| **Settings** | `/settings` | Custom save folder, Light/Dark theme, EXIF stripper, global watermark | — | — |
