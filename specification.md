# PixelTools — Technical Feature Guide

> **Flutter Image & PDF Toolkit** · Senior Developer Reference
> A complete technical breakdown of every feature, system, and architectural decision — without code, focused purely on how things work and why.

---

## Table of Contents

1. [Project Philosophy & Architecture Overview](#1-project-philosophy--architecture-overview)
2. [Technology Stack Decisions](#2-technology-stack-decisions)
3. [Core Infrastructure Systems](#3-core-infrastructure-systems)
4. [Feature A — Image Resizer](#4-feature-a--image-resizer)
5. [Feature B — Collage Builder](#5-feature-b--collage-builder)
6. [Feature C — Format Converter](#6-feature-c--format-converter)
7. [Feature D — PDF Compressor](#7-feature-d--pdf-compressor)
8. [Feature E — PDF Merger](#8-feature-e--pdf-merger)
9. [Feature F — PDF Splitter](#9-feature-f--pdf-splitter)
10. [Feature G — Image to PDF](#10-feature-g--image-to-pdf)
11. [Shared Widget System](#11-shared-widget-system)
12. [Shared Services Layer](#12-shared-services-layer)
13. [Isolate & Performance Strategy](#13-isolate--performance-strategy)
14. [Responsive Layout System](#14-responsive-layout-system)
15. [Platform-Specific Behaviour](#15-platform-specific-behaviour)
16. [State Management Pattern](#16-state-management-pattern)
17. [Data Persistence & History](#17-data-persistence--history)
18. [Export & File I/O Strategy](#18-export--file-io-strategy)
19. [Error Handling & Recovery](#19-error-handling--recovery)
20. [Testing & Quality Strategy](#20-testing--quality-strategy)
21. [Build Sequence & Delivery Roadmap](#21-build-sequence--delivery-roadmap)

---

## 1. Project Philosophy & Architecture Overview

### What PixelTools Is

PixelTools is a professional, fully offline image and PDF manipulation toolkit built with Flutter. It targets designers, content creators, developers, and everyday users who need fast, private, on-device file processing without depending on cloud services. Every single byte processed by PixelTools stays on the user's device.

### The Three Non-Negotiables

**Privacy by design.** No file is ever uploaded to any server, under any condition. All processing happens locally. This is a fundamental product promise, not a nice-to-have.

**60fps always.** Heavy computation — image decoding, PDF parsing, format conversion — always runs in a Dart Isolate, never on the UI thread. The user must be able to scroll and interact with the app smoothly while a batch of 50 images is being processed in the background.

**Feature isolation.** Each tool is a self-contained module. A developer working on the PDF Splitter should never need to touch the Image Resizer's code. This is enforced structurally through Clean Architecture, not just convention.

### Architecture Pattern: Feature-First Clean Architecture

The project uses Clean Architecture organized by feature rather than by layer. This means every feature folder (image_resize, pdf_merge, etc.) contains its own data layer, domain layer, and presentation layer. There are no cross-cutting "repositories" folders or shared "screens" folders.

**Data Layer** is responsible for all raw I/O: reading files from disk, calling native APIs, writing output bytes. It knows nothing about the UI.

**Domain Layer** contains the pure business logic: the use cases. A use case like ResizeUseCase takes a file and parameters, does the work in an Isolate, and returns a result. It knows nothing about Flutter widgets or Riverpod providers.

**Presentation Layer** is the UI: screens, widgets, and Riverpod notifiers. It calls use cases and displays results. It knows nothing about how the underlying processing works.

This separation means you can completely swap the image processing library (say, from the `image` package to a Rust FFI binding) without touching a single widget.

### Project Folder Philosophy

The `lib/core/` directory holds infrastructure that the whole app depends on: the router, the theme, the dependency injection wiring, the Isolate pool, and error types. Nothing in `lib/features/` should depend on anything in another feature folder — only on `lib/core/` and `lib/shared/`.

The `lib/shared/` directory holds widgets and services that are used by multiple features but are not specific to any single one: the DropZone widget, the ExportSheet, the FilePickerService. These are the building blocks that every feature composes.

---

## 2. Technology Stack Decisions

### State Management: Riverpod 2.x

Riverpod is chosen over Bloc, Provider, and GetX for three reasons: it has no BuildContext dependency (providers work anywhere, including in Isolates and services), its AsyncNotifier pattern maps perfectly to the async nature of file processing, and its compile-time safety catches errors that other solutions catch at runtime.

Every feature has one primary `AsyncNotifier` that holds the entire screen state: the list of loaded files, the processing task statuses, the current parameters, and any errors. The UI reactively rebuilds from this single source of truth.

### Navigation: GoRouter

GoRouter is chosen for its `ShellRoute` support, which is essential for maintaining the persistent sidebar and top bar while navigating between features. Deep linking is supported out of the box, which matters for the share sheet integration on mobile — when a user shares a PDF into PixelTools, the app opens directly to the correct tool screen.

### Image Processing: `image` package + `flutter_image_compress`

The pure Dart `image` package handles all image decoding, transformations (resize, crop, composite), and encoding for formats that don't require native codecs. It runs perfectly inside Dart Isolates because it has zero Flutter dependencies.

`flutter_image_compress` is used specifically for WebP encoding, because the native WebP codec (libwebp) produces dramatically better output than pure Dart WebP encoding — about 30–40% smaller files at equivalent quality. AVIF similarly requires a native binding via `flutter_avif`.

### PDF Stack: Three Libraries Working Together

**dart-pdf** (`pdf` package) handles PDF creation from scratch — building new documents, adding pages, embedding images, setting page size. It is used for Image-to-PDF conversion.

**syncfusion_flutter_pdf** (community license, free) handles low-level PDF manipulation — reading existing PDFs, extracting embedded image XObjects, replacing content, copying pages between documents, and saving modified documents. It is used for compression, merging, and splitting.

**pdfrx** handles PDF rendering — converting PDF pages into bitmap images for display. It is used only for generating the page thumbnail strips in the Merge and Split features.

These three libraries are intentionally separated by responsibility. Using one library for everything would create a fragile, overcoupled system.

### Storage: Hive CE

Hive is chosen over SQLite and shared_preferences for local persistence because it supports typed models (via adapters), is extremely fast for key-value access, and works identically on all platforms including web. It stores the operation history, user preferences, and custom presets.

### File I/O: `file_picker` + `saver_gallery` + `share_plus`

`file_picker` is the cross-platform standard for opening files. It supports filtering by extension, multi-select, and streaming file access (reading file contents as a stream rather than loading everything into memory at once — critical for large files).

`saver_gallery` handles saving to the device photo library on iOS and Android with the correct permission model for each OS version.

`share_plus` triggers the native OS share sheet, allowing users to send processed files to any app on their device.

### ZIP Export: `archive`

When batch operations produce multiple output files, they are bundled into a ZIP for easy download. The `archive` package is used because it supports streaming — files can be written into the ZIP one at a time without holding all output bytes in memory simultaneously.

---

## 3. Core Infrastructure Systems

### The Theme System

The theme is built on Material 3 with a dark-first design. Every feature has its own accent color, consistently applied across that feature's toolbar, active sidebar item, selected chips, and primary action buttons. This visual language helps users orient themselves — the purple/indigo tone means Image Resize, the teal means Collage, the coral means PDF Compress, and so on.

Colors are defined as a sealed set of constants. The `AppColors.forTool(ToolType)` method returns the correct accent for any tool, so accent color is always looked up from the tool type rather than hardcoded in individual widgets.

Text uses DM Sans for all UI text (weight 400/500/600/700) and DM Mono for all numeric values, file sizes, pixel dimensions, and code-like strings. The monospace font for numbers prevents layout shifting when values change — a `1.8 MB` value won't cause the chip width to jump when it becomes `18.4 MB`.

### The Isolate Pool

The Isolate Pool is the most important piece of infrastructure in the entire project. It is a custom worker pool that manages a fixed number of Dart Isolates — typically `min(CPU cores - 1, 4)` workers. The `- 1` is critical: it reserves one core for the Flutter UI thread.

When a feature submits a task (resize this image, compress this PDF), the pool either dispatches it immediately to an idle worker or queues it if all workers are busy. When a worker finishes, it picks up the next queued task automatically.

This means: if a user has 20 images to resize and the device has 4 cores, the pool will process 3 images simultaneously (3 workers), keeping the UI smooth on the 4th core, and automatically manage the queue of remaining 17 images.

The pool is provided as a Riverpod provider and disposed when the app is destroyed. All features share the same pool — there is no per-feature Isolate management.

### The Router

The router uses a ShellRoute that wraps all tool screens. The shell renders the persistent chrome (top bar on desktop, bottom nav on mobile, sidebar on tablet+desktop), and the child slot renders the currently active tool screen. This means navigating between tools does not rebuild the chrome — only the inner content changes, preserving any in-progress operations in the background (though in practice, navigating away from a screen while processing will cancel pending operations via AsyncNotifier disposal).

Each tool has a dedicated route path. These paths also double as deep link targets, so the share sheet on mobile can open the app directly to the PDF Compress tool when a PDF is shared into the app.

### Error Model

Errors are typed using a sealed `Failure` class hierarchy. There are specific failure types for file read errors, encoding errors, permission denied, out-of-memory, and unsupported format. This allows the UI to show specific, actionable error messages rather than generic "something went wrong" toasts.

All use cases catch exceptions at their boundary and convert them to typed Failures before returning. The UI layer never deals with raw exceptions.

---

## 4. Feature A — Image Resizer

### Purpose & Scope

The Image Resizer is the foundational feature of PixelTools. It accepts one or many images, applies dimension and format transformations, and outputs the results. It supports single-file and batch modes with identical controls, and it is the feature that validates the entire processing pipeline from file pick through Isolate processing to export.

### File Ingestion

Files can enter the resizer through three channels depending on the platform:

- **File picker dialog** (all platforms): Multi-select with filtering to image formats only
- **Drag-and-drop** (desktop): The DropZone widget accepts dragged files and validates their extensions
- **Share sheet** (mobile): When a user selects "Share" on an image in their photo library and picks PixelTools, the app receives the file via `receive_sharing_intent` and pre-loads it into the resizer

File reading uses streaming mode (`withReadStream: true` in file_picker). This means the file content is not loaded into memory at the moment of picking — only the file path is retrieved. The actual bytes are read only when processing begins. For a batch of 50 high-resolution images, this is the difference between the app running normally and immediately crashing from memory pressure at the pick step.

### Dimension Controls

**Width and Height inputs** accept pixel values directly. When aspect ratio lock is enabled, changing one dimension automatically recalculates the other based on the original image's aspect ratio. The lock can be toggled independently, and the calculation happens client-side in the UI — no processing needed until the user explicitly triggers export.

**Preset Selector** provides a dropdown of common dimensions including Full HD (1920×1080), 4K UHD (3840×2160), HD (1280×720), and 12 social media presets. Social presets include Instagram Post (1080×1080), Instagram Story (1080×1920), Twitter/X Header (1500×500), LinkedIn Banner (1584×396), YouTube Thumbnail (1280×720), and Facebook Cover (820×312). There are also Print presets: A4 at 300dpi (2480×3508) and US Letter at 300dpi (2550×3300). Custom presets created by the user are stored in Hive and appear at the top of the dropdown.

### Resize Modes

There are four distinct resize modes. Understanding the difference is critical for correct output:

**Fit** scales the image so it fits entirely within the target dimensions while maintaining its original aspect ratio. The result may have empty space (letterboxing or pillarboxing) if the aspect ratios don't match. This is the default. A 16:9 image fitted into a 1:1 box will appear full-width with black/white bars top and bottom.

**Fill** scales the image so it completely covers the target dimensions while maintaining aspect ratio, then crops the excess. No empty space is ever visible, but parts of the image may be cut off. The crop is always centered. This is what you want for social media thumbnails where the exact dimensions are mandatory.

**Stretch** scales the image to exactly the target dimensions with no regard for aspect ratio. The image will appear distorted if the aspect ratios differ. This is rarely what users want, but it is available for specific professional use cases.

**Pad** fits the image (same as Fit mode) then fills the surrounding empty space with a user-chosen solid color rather than leaving it transparent. This produces a perfectly rectangular output with no distortion and no transparency — ideal for JPEG output where transparency isn't supported.

### Interpolation

All resize operations use cubic (bicubic) interpolation by default. Cubic interpolation produces the highest visual quality — especially when downscaling — because it considers a 4×4 pixel neighborhood rather than just the nearest neighbor or a 2×2 neighborhood (bilinear). The tradeoff is processing time: cubic is approximately 3× slower than bilinear.

For very large batches or lower-power devices, an optional "Fast Mode" toggle switches to bilinear interpolation. The quality difference is barely perceptible for most use cases, but the speed difference can be significant for batches of 20+ images.

### Output Format & Quality

The output format selector offers JPG, PNG, WebP, and AVIF (platform-dependent). The format determines which encoding path is used:

- JPG uses the native JPEG encoder with a configurable quality slider (1–100). Quality 85 is the default — visually lossless for most content at roughly 60% of the original file size.
- PNG uses lossless compression. The compression level (0–9) controls how hard the encoder tries to reduce file size — higher compression takes longer but doesn't reduce image quality. Level 6 is the default balance.
- WebP uses the native libwebp codec via flutter_image_compress. It produces better quality at smaller sizes than JPG for the same quality setting, with broad support on modern platforms.
- AVIF requires the flutter_avif plugin. It offers the best compression of all formats but has the highest encoding time and requires iOS 16+/Android API 31+ for native support.

### Batch Processing

Batch mode works identically to single-file mode from the user's perspective — the same dimension and format settings apply to all files. Under the hood, files are processed in parallel via the Isolate Pool, with each file getting its own worker.

The UI shows a ProgressRail with one row per file. Each row transitions through states: pending (grey dot), processing (amber pulsing dot), done (green dot with output size + savings percentage), and error (red dot with error description). Processing can be cancelled per-file by tapping the X on an in-progress row.

### Export

Single-file output is offered through the ExportSheet: Save to Gallery, Save to Files, Share, or Copy to Clipboard (for images).

Multi-file batch output defaults to ZIP export. All processed files are packaged into a ZIP archive named `pixeltools_resized_[timestamp].zip` and offered via the ExportSheet. Individual files can also be exported one at a time by tapping a file chip in the results list.

Output filenames follow the pattern `[original_name]_resized.[format]`. Custom naming patterns can be set in Settings.

---

## 5. Feature B — Collage Builder

### Purpose & Scope

The Collage Builder composites multiple images onto a single canvas using a predefined grid layout. It produces a single high-resolution image output. The feature has the most complex UI of all tools — it requires a live canvas preview, drag-to-reorder image slots, a layout selector, and precise canvas configuration — and the most complex rendering pipeline.

### Grid Layout System

Layouts are defined declaratively as a set of grid cells, each with column span and row span values. The grid itself has a defined number of columns and rows. This is conceptually identical to CSS Grid.

The eight predefined layouts are:

**1×1** — Single full-canvas image. Useful when you want to resize + crop in one step without true compositing.

**1×2 (Side by Side)** — Two equal columns, one row. Classic before/after or comparison layout.

**2×2 (Grid)** — Four equal cells in a 2×2 arrangement. The most common collage format, ideal for product grids and social media carousels.

**2×3 (Gallery)** — Six equal cells. Instagram-style gallery grid with equal-weight images.

**3×3 (Mood Board)** — Nine equal cells. Dense grid for mood boards, inspiration collections.

**Featured** — Two-column layout where the left cell spans both rows (large/hero image) and the right column has two stacked smaller cells. Best for a focal image with supporting context.

**T-Layout** — A wide top cell spanning all columns (banner image) with three equal cells below it. Good for a scene-setting header with detail shots underneath.

**Mosaic** — Left cell takes 2/3 of the width across both rows; right column has two equal stacked cells. An asymmetric editorial layout that draws the eye to the dominant image.

Users cannot define custom layouts in v1.0. A custom layout editor is planned for v2.0.

### Live Preview vs. Full-Resolution Export

This is the most important architectural distinction in the Collage feature: the preview and the export use completely different rendering paths.

**The live preview** uses Flutter's `CustomPainter` to draw the collage at whatever size the preview widget occupies (typically 300–500px wide). It uses scaled-down thumbnail versions of the source images — each thumbnail is pre-scaled to approximately 200px on its longest edge. The painter computes cell positions and sizes, clips each cell to its bounds with optional corner rounding, and paints the thumbnail into it. This is fast and runs on the main thread without issue because the thumbnails are small.

Thumbnails are generated lazily: when an image is added to the collage, a background task scales it down and stores the resulting `ui.Image` in the notifier's state. The preview repaints automatically when thumbnails are ready.

**The full-resolution export** is a completely separate rendering path that runs in a Dart Isolate using the `image` package. It does not use Flutter's Canvas API at all (which is not available in Isolates). Instead, it creates an `img.Image` canvas at the target resolution, loads each source image at full resolution, crops and scales each one to fill its cell, and composites them onto the canvas pixel by pixel. The result is exported as PNG or JPEG.

This two-path approach is what allows the preview to remain responsive even while a 6-image, 2400×1600px collage is being rendered in the background.

### Drag-and-Drop Reordering

Each image slot in the preview grid is a draggable item. Long-pressing a slot initiates drag mode — the slot shows a semi-transparent ghost at 60% opacity. Other slots act as drop targets. When the ghost is released over a valid target, the two image assignments swap in the notifier's state list, and the preview repaints immediately.

Drag reordering works entirely in Flutter — no native drag APIs are involved. On desktop, regular drag (not long press) is used instead.

### Canvas Configuration

The output canvas is fully configurable:

**Dimensions** — Width and height in pixels. Independent controls; no aspect lock on the canvas itself. Common presets match social media sizes.

**Gap** — The spacing between grid cells in pixels. A gap of 0 creates seamless compositing; larger gaps create a framed look. The gap is applied uniformly between all cells but not around the canvas edges.

**Corner Radius** — Rounds the corners of each cell independently. At 0, cells have sharp corners. The corner rounding is applied as a clip mask during rendering — the composite render handles this correctly even at cell boundaries.

**Background Color** — The color shown in the gaps between cells and (if any) around the canvas border. Defaults to white. Can be set to any color including black for a dark-themed collage, or a custom brand color.

**Image Fit per Cell** — Each cell uses Cover mode by default (image fills the cell, cropping as needed). This can be changed per-cell to Contain (image fits inside the cell with potential empty space filled by the background color).

### Export

The Collage Builder exports a single file. The output format choices are PNG (lossless, best quality, larger file) and JPEG (lossy, configurable quality, smaller file). PNG is recommended when the source images have transparent areas and the gap is 0; JPEG is recommended for all other cases.

Export goes through the standard ExportSheet: Save to Gallery, Save to Files, Share.

---

## 6. Feature C — Format Converter

### Purpose & Scope

The Format Converter batch-converts images from any supported input format to a chosen output format. It handles the nuances of format conversion that many simpler tools miss: transparency flattening, EXIF metadata preservation or stripping, animated GIF handling, and platform-specific codec availability.

### Format Detection by Magic Bytes

The converter never trusts file extensions to determine format. A file named `.jpg` might actually be a PNG (this happens frequently when users rename files). Instead, the first 12 bytes of every file are read and compared against known file signatures (magic bytes):

- JPEG files always start with `FF D8`
- PNG files always start with `89 50 4E 47 0D 0A 1A 0A`
- GIF files start with `47 49 46 38`
- BMP files start with `42 4D`
- TIFF files start with either `49 49` (little-endian) or `4D 4D` (big-endian)
- WebP files start with `52 49 46 46` (RIFF) and have `57 45 42 50` at bytes 8–11
- HEIC/AVIF files have an `ftyp` box at bytes 4–7, with the brand name (heic, mif1, avif) at bytes 8–11

This detection runs synchronously before any processing begins, and any unrecognized format is rejected immediately with a clear error message.

### Supported Format Matrix

**Input formats:** JPEG, PNG, WebP, AVIF, GIF (including animated), BMP, TIFF, HEIC (iOS and macOS only; Android API 31+ with caveats)

**Output formats:** JPEG, PNG, WebP, AVIF, GIF, BMP

HEIC cannot be written by PixelTools — it requires an Apple-proprietary codec that is not available for encoding on Android. TIFF reading is supported (via the image package) but TIFF output is converted to PNG instead, as TIFF encoding in pure Dart produces very large files with limited compatibility.

### Transparency Handling — Critical Detail

This is where many converters silently produce corrupted output. When converting from a format that supports transparency (PNG, WebP, AVIF, GIF with alpha, HEIC) to a format that does not (JPEG, BMP), the alpha channel cannot simply be discarded — doing so produces black or corrupted areas where transparent pixels existed.

The correct approach is alpha flattening: before encoding, a new solid-color canvas is created at the same dimensions, the solid color is drawn first, and then the semi-transparent image is composited on top. The result is a fully opaque image where transparent areas now show the chosen background color (default: white).

The user can choose the flatten background color in the settings panel. For most use cases white is correct, but for images on dark backgrounds, black produces a more natural result.

This flattening happens automatically whenever the source format has alpha capability and the target format does not. It is not optional — there is no way to encode JPEG with transparent pixels.

### EXIF Metadata Handling

Every digital photo contains EXIF metadata embedded in the file: camera make and model, lens information, capture date and time, GPS coordinates of where the photo was taken, and exposure settings. This data is useful for photographers but can be a privacy concern when sharing images online.

The converter offers two modes:

**Preserve EXIF** copies the metadata block from the source file to the output file. This is important for professional photography workflows where metadata continuity matters. Note: EXIF embedding varies by format — JPEG uses the standard EXIF block, WebP stores EXIF in the VP8X container, PNG uses iTXt text chunks, and other formats may not support EXIF at all. If the target format doesn't support EXIF, it is silently dropped.

**Strip EXIF** removes all metadata before encoding. This is the privacy-safe option and the default for sharing use cases. GPS data in particular can reveal sensitive location information — where someone lives, works, or has been.

### Animated GIF Handling

Animated GIFs are decoded frame by frame. For conversion to a static format (JPEG, PNG), only the first frame is extracted. The user is shown a notice that the animation will not be preserved.

For conversion to animated WebP, all frames are re-encoded. Animated WebP typically produces files 40–60% smaller than equivalent GIF while supporting full 24-bit color (GIF is limited to 256 colors per frame). This is the recommended conversion for animated content.

### Platform Codec Availability

WebP encoding uses the native libwebp codec via flutter_image_compress, which is available on all platforms. AVIF encoding requires flutter_avif, which uses the native AV1 codec — available on iOS 16+, Android API 31+, and macOS 12+. On older platforms, AVIF is hidden from the format selector rather than attempting to use the slow pure-Dart fallback.

The codec availability check runs at app startup and updates the `CapabilityService`, which the format selector reads to show or hide options.

---

## 7. Feature D — PDF Compressor

### Purpose & Scope

The PDF Compressor reduces the file size of existing PDF documents without visibly degrading their content. It does this by resampling embedded images at lower resolution, removing non-essential metadata, optionally flattening annotations, and optimizing the PDF's internal object stream structure.

### How PDF Size Is Created

Understanding what makes PDFs large is essential to understanding what the compressor does. PDFs are containers that can embed multiple types of content:

**Embedded images** are the dominant size contributor in most PDFs. A PDF generated from scanned documents or presentations might contain dozens of full-resolution images encoded at 300–600dpi. These images are stored as raw XObject streams in the PDF structure.

**Metadata** includes document title, author, subject, creator application, modification dates, and custom properties. This is typically small (a few kilobytes) but stripping it is a best practice for sharing.

**Annotations** are interactive elements: comments, highlights, form fields, digital signatures. These can be substantial in heavily annotated documents. Flattening annotations merges their visual appearance into the page content and removes the interactive layer.

**Font embedding** contributes to size when a PDF embeds full font files rather than just the character subset used. The compressor does not currently manipulate fonts (this requires specialized font subsetting tools).

### Compression Presets

Three presets cover the most common use cases:

**Screen (72 dpi, quality 65%)** — Maximum size reduction. Images are downsampled to 72dpi, which is sufficient for comfortable reading on screen but completely unsuitable for printing. Typical reduction: 70–85% of original size. Use this for email attachments, web sharing, and documents that will only ever be viewed digitally.

**Print (150 dpi, quality 80%)** — Balanced quality and size. Images are downsampled to 150dpi, which produces acceptable printed output on standard office printers. Typical reduction: 50–70% of original size. This is the default and covers the vast majority of professional sharing use cases.

**Prepress (300 dpi, quality 95%)** — Minimal compression, maximum quality. Images are downsampled only if they exceed 300dpi (many scanned documents are at 600dpi). Appropriate for documents destined for professional offset printing. Typical reduction: 10–30%.

**Custom** — The user manually sets target DPI and JPEG quality. This is for power users with specific requirements.

### The Compression Pipeline

The process operates on the PDF's internal structure using syncfusion_flutter_pdf:

The compressor opens the PDF document and iterates through every page. For each page, it accesses the page's Resources dictionary, which lists all referenced XObjects. Each XObject of type Image is extracted, decoded into raw pixel data, analyzed for its current DPI setting, and resampled if the current DPI exceeds the target.

Resampling uses bilinear interpolation (not cubic) because the quality difference is minimal when downsampling and bilinear is significantly faster. The resampled image is re-encoded as JPEG at the preset quality setting and reinserted into the PDF structure, replacing the original XObject.

After all pages are processed, metadata is cleared if requested, annotations are flattened if requested, and the document is saved with cross-reference stream compression enabled, which provides an additional 10–15% size reduction at the structural level.

### Before/After Display

After compression completes, the UI shows a two-card comparison: original size and compressed size, with the reduction percentage prominently displayed. The user sees this result before downloading. If the compressed version is actually larger than the original (this can happen with already-compressed PDFs), the UI shows a warning and recommends downloading the original.

### Desktop Enhancement via Ghostscript

On macOS, Windows, and Linux, PixelTools can optionally delegate to Ghostscript for compression. Ghostscript is a mature, battle-tested PostScript/PDF interpreter that produces 15–40% better compression than pure programmatic approaches for the same quality level. It handles edge cases that the Dart-based approach does not, including font subsetting, object stream merging, and content stream optimization.

The Ghostscript binary is bundled with the desktop app (in the assets/gs/ folder) so users don't need to install it separately. On mobile, Ghostscript is not available — the Dart-based approach is used exclusively.

The compression strategy is abstracted behind an interface. The app detects the platform and automatically selects Ghostscript on desktop and Syncfusion on mobile. This is transparent to the user.

---

## 8. Feature E — PDF Merger

### Purpose & Scope

The PDF Merger combines multiple PDF documents into a single output PDF, preserving all visual content including text, vector graphics, images, and annotations. Users can select a custom page range per source document and reorder documents via drag-and-drop before merging. The output is a single PDF with all selected pages in the user-defined sequence.

### Multi-File Management

Files are displayed in a reorderable list, each showing the document name, page count, file size, and the currently selected page range. The list is draggable — long-press on mobile, regular drag on desktop — to reorder documents. The final merge will follow the list order top-to-bottom.

Each document has a "Page Range" field that opens a page selection UI (described below). The badge on each file shows either "All pages" or a summary like "3 pages selected". The total output page count is calculated and shown in a summary bar at the bottom of the list.

### Page Range Selection

Page range selection is a dedicated sub-screen for each source document. It has two input modes:

**Text input** accepts comma-separated ranges in the format `1-5, 8, 11-15`. This is parsed by a range parser that validates against the document's total page count, converts user-facing 1-based indices to zero-based internal indices, and produces a sorted, deduplicated list. Invalid ranges (e.g., page 200 of a 50-page document) are highlighted with inline validation errors and excluded.

**Visual thumbnail selector** shows a horizontal scrollable strip of page thumbnails at 120×170px. Thumbnails are rendered on demand using pdfrx as the user scrolls. Tapping a thumbnail toggles it between included (highlighted with accent border) and excluded (dimmed). Tapping and dragging selects a range of pages.

The two modes are kept in sync — selecting pages in the thumbnail strip updates the text input, and editing the text input updates the thumbnail highlights.

### Thumbnail Rendering Performance

Rendering page thumbnails is potentially expensive for large documents. The implementation uses lazy rendering: only pages that are currently visible in the scroll viewport are rendered, plus a small buffer of pages ahead of and behind the scroll position.

Rendered thumbnails are cached in memory keyed by file path hash + page index. If the user closes and reopens the page range UI for the same document, thumbnails are served from cache instantly. The cache is cleared when the feature screen is disposed.

A 500-page document is never fully rendered — the user will scroll through it and pages will render as they come into view, which is the standard pattern for document viewers.

### The Merge Algorithm

The merge runs in a Dart Isolate. All source document bytes are read from disk on the main thread first (file I/O shouldn't block the UI but shouldn't run in an Isolate either, as file handles are tied to the main thread in some platform contexts). Then the byte arrays are passed to the Isolate.

Inside the Isolate: a new empty PDF document is created. For each source in order, the source bytes are loaded, and each selected page is copied using the `createTemplate()` and `drawPdfTemplate()` approach. This approach faithfully reproduces page content including text rendering, vector paths, and embedded images. The source document is disposed after copying to free its memory before moving to the next source.

The output document is saved and the bytes are returned. The Isolate then terminates.

### Output

The merged output is named based on context: if all sources share a common filename prefix (e.g., "report-q1.pdf", "report-q2.pdf"), the output is named "[prefix]-merged.pdf". Otherwise, it defaults to "merged-[timestamp].pdf". The user can override the filename in a text field before exporting.

---

## 9. Feature F — PDF Splitter

### Purpose & Scope

The PDF Splitter extracts pages from a single source PDF into one or more output documents. It is the inverse operation of the merger. Because it always produces multiple files, the output is always bundled into a ZIP archive.

### Split Modes

**Every Page** — Each page becomes an independent single-page PDF. A 50-page document produces 50 PDFs. This is the most common use case: separating a scanned multi-page document into individual pages for separate filing.

**Custom Ranges** — The user defines a set of ranges. Each range becomes one output PDF. The range syntax is identical to the Merger's page range input: `1-5, 6-10, 11-20` would produce three PDFs. The ranges do not need to be contiguous or cover all pages — pages not included in any range are simply not exported.

**By File Size** — The document is automatically split so that each chunk stays under a user-specified file size limit. This is useful for email attachments with size limits. The split algorithm estimates page sizes based on the original document's total size and page count, then groups pages greedily until the chunk would exceed the limit, at which point a new chunk begins. This is an approximation — actual output file sizes may vary slightly because page content sizes are not uniform.

### Output File Naming

Every output file is named using a configurable pattern with token substitution. The default pattern is `{name}_p{range}`, producing names like `annual-report_p1-10.pdf`. Available tokens:

- `{name}` — original file name without extension
- `{range}` — page range, formatted as `p1` (single page) or `p1-10` (range)
- `{index}` — output file index (1, 2, 3...)
- `{total}` — total number of output files
- `{date}` — export date in YYYY-MM-DD format

The naming pattern is stored in user preferences so it persists between sessions.

### ZIP Streaming

The ZIP output is built using streaming to avoid holding all output bytes in memory simultaneously. Each split document is rendered, its bytes are immediately written into the ZIP archive stream, and the document object is then disposed. This means peak memory usage is limited to the size of one split chunk at a time, regardless of how many total splits are produced.

For "Every Page" mode on a large document, this is essential — a 500-page document split into 500 individual PDFs could produce hundreds of megabytes of output. Streaming prevents this from causing memory exhaustion.

### Visual Page Preview

The source document's pages are shown as a thumbnail grid in the central canvas area. Users can visually browse the document, set page ranges by clicking thumbnails, and get a sense of the content before splitting. Thumbnail generation uses the same lazy-loading approach as the Merger.

---

## 10. Feature G — Image to PDF

### Purpose & Scope

Image to PDF converts a sequence of image files into a single PDF document, with one image per page. It is built with dart-pdf (the `pdf` package), which requires no native dependencies and runs entirely in Dart. The feature handles page sizing, orientation, image fitting, margins, and output quality.

### Image Input

Images can be added from the file picker (any supported image format), from drag-and-drop (desktop), or from the share sheet (mobile). Once added, they appear as a reorderable thumbnail list — the order determines the page order in the output PDF. Images can be removed individually or cleared all at once.

The file picker filters to common image extensions, but the format detector runs on every file to ensure compatibility before processing begins.

### Page Layout Options

**Page Size** determines the physical dimensions of each page in the output PDF. Options are:
- A4 (210×297mm) — the international standard for documents
- A3 (297×420mm) — for large-format content
- US Letter (215.9×279.4mm) — the North American standard
- US Legal (215.9×355.6mm) — for legal documents
- Match Image — the page size is set to exactly the image's pixel dimensions (converted to points at 72dpi). This produces the most faithful reproduction but may result in non-standard page sizes.

**Orientation** can be set to Portrait, Landscape, or Auto. Auto mode inspects each image's own aspect ratio and sets the page orientation accordingly — landscape images get landscape pages, portrait images get portrait pages. This mode produces the best fit per-image in mixed-orientation batches.

**Fit Mode** controls how the image fills the page within its margin area:
- Fit (Contain) — scales the image to fit entirely within the page content area while preserving aspect ratio. The result may have empty space if the image and page aspect ratios differ.
- Fill (Cover) — scales the image to fill the entire content area, cropping the excess. No empty space, but some image content may be cut off.
- Center — places the image at its native size centered on the page. If the image is larger than the page, it will be clipped at the page boundaries.
- Stretch — scales the image to exactly fill the content area with no regard for aspect ratio. Produces distortion if aspect ratios differ.

**Margin** sets a uniform margin in millimeters on all four sides of each page. The image is scaled to fit within the remaining content area. A margin of 0 places the image edge-to-edge against the page boundary. A margin of 10mm (the default) provides a clean visual border.

### Quality Mode

**Optimized mode** (default) re-encodes all images as JPEG at 90% quality before embedding them in the PDF. This keeps the output PDF compact. For most photographic content, the quality difference from 90% JPEG is imperceptible.

**High Quality mode** embeds images at their original quality. PNG images with transparency are embedded as PNG (preserving transparency). JPEG images are embedded as-is without re-encoding. This produces the largest output files but the best fidelity.

### Transparency Handling

When a PNG or WebP image with transparency is processed in Optimized mode, the alpha channel is flattened onto a white background before JPEG encoding. This is identical to the Format Converter's alpha flattening behavior. In High Quality mode, the image is embedded as PNG so transparency is preserved, and the PDF page background (which defaults to white in most viewers) shows through the transparent areas.

### Output

The output is a single PDF file named `pixeltools_[timestamp].pdf` by default. The user can edit the filename before exporting. Export goes through the standard ExportSheet.

---

## 11. Shared Widget System

### DropZone

The DropZone widget is the entry point for files in every feature. It has two interaction modes depending on the platform:

On **desktop**, the DropZone wraps the `desktop_drop` library's DropTarget, making it a genuine drag-and-drop target. Files dragged from Finder/Explorer/Files Manager can be dropped directly onto it. The widget validates file extensions on drag-enter and shows a visual state change: idle (dashed accent border), hover with valid files (solid teal border, brightened background), hover with invalid files (red border, error color). On drop, valid files are passed to the feature and invalid files are shown a brief "unsupported format" indicator.

On **mobile**, the DropZone is a tappable area that triggers the file picker. The visual appearance matches the desktop version but without the drag affordance.

The widget accepts configuration for allowed extensions, whether multiple files can be selected, and the label and sublabel text. The inner content can be fully replaced with a custom child widget for features that need a different empty-state appearance.

### ProgressRail

The ProgressRail displays a scrollable list of processing tasks, one row per file. Each row shows a status indicator dot (color and animation encode the status), the file name, and contextual details that change based on status.

Status states and their visual representations:
- **Pending** — grey static dot. The file is queued and waiting for an Isolate worker.
- **Processing** — amber pulsing dot. The file is actively being processed. A thin linear progress bar appears below the filename when progress percentage data is available.
- **Done** — green static dot. The output file size and savings percentage appear below the filename.
- **Error** — red static dot. The error message appears below the filename with a retry option.
- **Cancelled** — grey static dot, filename shown with strikethrough.

The ProgressRail is driven by a `List<TaskProgress>` from the notifier's state. It is a purely reactive widget — it never manages its own state.

### FileChip

FileChip is a compact representation of a loaded file before processing. It shows a format-appropriate icon, the filename (truncated with ellipsis if too long, full name in a tooltip), the file size in human-readable format (KB/MB), and a remove button.

On mobile, the chip supports swipe-to-dismiss (swipe left reveals a red delete background). On desktop, a remove icon is always visible on the right. Removing a file from the chip list updates the notifier's state immediately.

File size is always displayed in DM Mono font to prevent layout jumping when numbers change width. Sizes above 1MB are shown as `x.x MB`; below 1MB as `xxx KB`.

### ExportSheet

The ExportSheet is a bottom sheet (modal) that provides export options for any processed file. It is called from every feature with the output bytes and filename. It offers:

- **Save to Gallery** — available on iOS and Android only; saves the file to the device's photo library. Requires appropriate permissions, which are requested inline if not yet granted.
- **Save to Files** — saves to the app's documents directory on mobile; opens a system save-as dialog on desktop.
- **Share** — triggers the native OS share sheet, allowing the file to be sent to any app.
- **Copy to Clipboard** — available for image outputs only; copies the image data to the clipboard for direct paste into other applications.

Options are shown or hidden based on platform and file type. The sheet also shows the output filename and file size at the top for confirmation before the user acts.

### FormatChipGroup

A horizontal wrap of pill-shaped buttons representing format options (JPG, PNG, WebP, AVIF, etc.). Only one chip can be active at a time. The active chip uses the feature's accent color for its background and border. Inactive chips use the surface color.

Each chip's width adjusts to its label text. Chips wrap to a new line if they don't all fit in a single row. This widget is used in the Resize, Convert, and Image-to-PDF settings panels.

### PageRangePicker

Used in the PDF Merger and Splitter features. Combines a text field for entering page range notation with a horizontal scrollable thumbnail strip for visual page selection. The two inputs are kept in sync bidirectionally. Validation runs on every keystroke in the text field and is debounced to avoid excessive processing.

---

## 12. Shared Services Layer

### FilePickerService

A thin wrapper around the `file_picker` library that provides typed, opinionated methods for common picking scenarios: `pickImages()`, `pickPdfs()`, and `pickAny()`. All methods return `List<XFile>` with streaming access (file contents are not pre-loaded into memory).

The service encapsulates the allowed extensions list for each file type, the `withReadStream: true` option (critical for memory efficiency), and the `withData: false` option. Features consume this service rather than calling file_picker directly, ensuring consistent behavior across all picking operations.

### ExportService

Provides a unified export API across all platforms with three primary methods:

`saveToGallery()` uses saver_gallery on mobile. It handles the Android MediaStore API (with the correct relative path for visibility in the Photos app) and iOS PHPhotoLibrary (with the album name).

`saveToFiles()` uses path_provider to get the documents directory on mobile and presents a native save-as dialog on desktop via file_picker's save dialog.

`share()` creates a temporary file in the cache directory, writes the bytes to it, then passes it to share_plus. The temp file is cleaned up after the share sheet dismisses.

`saveZip()` is a higher-level method that accepts a list of named byte arrays, creates a ZIP archive in memory using the archive package, and delegates to `saveToFiles()` for the resulting ZIP.

### PermissionService

Handles the platform-specific permission model for file access:

On **Android**, the permission model changed substantially at API 33. Below API 33, `READ_EXTERNAL_STORAGE` and `WRITE_EXTERNAL_STORAGE` are required. From API 33+, granular permissions `READ_MEDIA_IMAGES` and `READ_MEDIA_VIDEO` are used instead. The service detects the Android version and requests the appropriate permissions.

On **iOS**, `NSPhotoLibraryAddUsageDescription` is required for saving to the photo library, and `NSPhotoLibraryUsageDescription` for reading. iOS 14+ also has a "Limited Photos" access mode where users grant access to a specific subset of photos — the service handles this by using `PHPickerViewController` rather than `UIImagePickerController` where appropriate.

On **desktop**, no permissions are required — file access is governed by the OS file system permissions that apply to all apps.

### HistoryService

Manages a ring buffer of the last 50 processing operations, stored in Hive. Each history entry records: a unique ID, the operation type (resize/collage/convert/etc.), the input file name, the original file size in bytes, the output file size in bytes, the timestamp of the operation, and optionally the output file path if the file was saved locally.

The ring buffer behavior: when a new entry is added and the store already has 50 entries, the oldest entry is deleted before the new one is inserted. This keeps storage bounded.

The History screen reads all entries sorted by timestamp descending (newest first) and displays them as a timeline. Each entry shows the operation type with its accent color, the file name, the savings achieved, and the relative time ("2 hours ago"). Tapping an entry offers re-download if the output path is still valid, or re-processing with the same parameters if the original file is still accessible.

---

## 13. Isolate & Performance Strategy

### Why Isolates Are Mandatory

Dart is single-threaded by default. Long-running synchronous operations on the main thread block the entire UI — the app freezes, animations stop, the user cannot interact. Image decoding, PDF parsing, and format conversion are all operations that can take hundreds of milliseconds to several seconds depending on file size.

Dart Isolates are separate threads of execution with their own memory space. The UI thread and Isolate threads run concurrently. By running all heavy processing in Isolates, the UI remains at 60fps regardless of what's happening in the background.

The constraint: Isolates cannot share objects directly. All data passed between the main thread and an Isolate must be serialized (for primitive types and typed data like Uint8List, this is a zero-copy pass by ownership transfer). This means Flutter-specific objects — widgets, BuildContext, ui.Canvas, ui.Image — cannot be used inside Isolates. Only pure Dart objects and packages with no Flutter dependency can run in Isolates.

### The IsolatePool Design

`Isolate.run()` creates a new Isolate for each call, runs the task, and destroys the Isolate when done. This is simple and safe, but creating Isolates has overhead — approximately 50ms of startup time. For batch processing with many small tasks, this overhead accumulates.

The IsolatePool addresses this by maintaining persistent long-lived Isolate workers. Workers are created at pool initialization and kept alive, receiving tasks via `SendPort` and returning results via `ReceivePort`. Tasks are dispatched to idle workers; when all workers are busy, tasks queue up. When a worker finishes, it signals availability and the next queued task is dispatched.

Worker count is set to `min(Platform.numberOfProcessors - 1, 4)` — leaving one core for the UI, and capping at 4 regardless of how many cores the device has (diminishing returns beyond 4 for typical image processing workloads, and excessive memory pressure from too many concurrent decoded images).

### Memory Pressure Management

Each decoded full-resolution image occupies substantial RAM. A 12-megapixel JPEG, when decoded to raw pixels for processing, requires approximately 48MB of RAM (12M pixels × 4 bytes RGBA). A batch of 10 such images decoded simultaneously would require 480MB, which exceeds the available memory on many mobile devices.

The IsolatePool naturally limits concurrency, which limits peak simultaneous memory usage. Beyond this, each Isolate task explicitly nullifies its reference to the decoded image immediately after encoding — before returning the result bytes. This allows the garbage collector to reclaim the memory before the next task starts.

For PDF operations, each PdfDocument object is explicitly disposed after use (via `document.dispose()`). Syncfusion's PDF library allocates substantial native memory for open documents — failing to dispose causes memory leaks.

On receiving a low-memory notification from the OS (via Flutter's `WidgetsBinding.instance.handleLowMemory()` callback), the thumbnail cache is cleared immediately and the IsolatePool worker count is reduced to 1 to minimize memory pressure.

### Progress Reporting

Processing progress is communicated from Isolates back to the UI via Riverpod state updates. The notifier loops through the task list sequentially (or parallel in the pool), updating each task's status as it transitions. Because Riverpod's AsyncNotifier updates propagate immediately to the UI, the ProgressRail reflects state changes in real time.

For long single-file operations (large PDF compression, high-resolution collage rendering), progress within the operation can be reported using a callback-based approach where the Isolate sends intermediate progress values through a SendPort. This drives the per-task linear progress bar in the ProgressRail.

---

## 14. Responsive Layout System

### Three Distinct Layouts

The app presents three fundamentally different layouts at three screen width breakpoints:

**Mobile (width < 600px)** — Single column. The tool sidebar is replaced by a bottom navigation bar with tool categories (Image and PDF as tabs). Within each category, a horizontal scrollable chip strip at the top selects the specific tool. Settings for the active tool are presented in a bottom sheet, triggered by a settings button in the top bar. The canvas area takes the full screen width.

**Tablet (600–1024px)** — Two columns. A permanent left sidebar (220px wide) shows all tool categories and items. The main canvas area takes the remaining width. Tool settings are presented as a draggable bottom sheet or a persistent panel that slides in from the right when content is selected or processing begins.

**Desktop (> 1024px)** — Three columns. Permanent left sidebar (220px), central canvas area (flexible), and permanent right settings panel (260px). All three panels are always visible simultaneously. This is the primary design target for the app — the layout shown in the UI mockup.

### Layout Detection and Switching

Layout detection uses Flutter's `LayoutBuilder` or `MediaQuery.of(context).size.width` at the AppShell level. The shell renders the correct layout variant based on the current width. When the user resizes a desktop window across a breakpoint, the layout switches smoothly via `AnimatedSwitcher`.

The GoRouter ShellRoute ensures that the app's routing state is preserved across layout changes — if the user is on the PDF Merge screen and resizes the window from mobile to desktop width, they remain on PDF Merge.

### Navigation Consistency

Across all layout sizes, the same 10 destinations exist (8 tools + History + Settings). Only the navigation chrome changes: bottom nav tabs on mobile, a persistent sidebar on tablet and desktop. The currently active tool is always visually indicated regardless of layout.

The sidebar groups tools into two sections: Image and PDF. Each item has its feature-specific accent color icon, a label, and optionally a badge (for "NEW" or file count indicators). The active item shows a colored left-edge accent bar matching the feature's accent color.

---

## 15. Platform-Specific Behaviour

### iOS-Specific

The share sheet integration receives files via UIDocumentPickerViewController. When a PDF is shared into PixelTools from another app, the router immediately navigates to the PDF tools section with the file pre-loaded.

HEIC format reading is native on iOS — the system provides codec support transparently. HEIC files are decoded automatically by the image loading path.

Photo library saves use PHPhotoLibrary. The app requests add-only permission where possible (a less invasive permission that allows writing to the library without reading other photos).

File system access is sandboxed. The app can read and write its own container, temporary directory, and files explicitly selected by the user. It cannot read arbitrary file system paths.

### Android-Specific

The share intent filter in AndroidManifest allows the app to receive both images and PDFs via the Android share system. The app handles `ACTION_SEND` (single file) and `ACTION_SEND_MULTIPLE` (multiple files).

MediaStore is used for saving outputs to the device gallery, following the scoped storage model required for Android 10+. Files are saved to `Pictures/PixelTools/` in the public media store.

Legacy external storage access (`android:requestLegacyExternalStorage="true"`) is declared for backward compatibility with Android 9 and below, where the MediaStore model was not yet enforced.

### macOS-Specific

The app sandbox entitlements must explicitly grant access to user-selected files and the Downloads directory. Without these entitlements, file picker results are inaccessible even after the user selects a file.

Ghostscript is bundled in the app bundle under `Contents/Resources/gs/`. The compression feature detects this binary at runtime and uses it when available.

Menu bar support is planned for v1.1 — File > Open, File > Export, and tool-specific actions will be accessible from the macOS menu bar.

### Windows-Specific

File association registration (in the MSIX manifest) allows users to right-click a PDF or image in Explorer and open it directly in PixelTools. The app handles the command-line argument containing the file path at launch.

Ghostscript is bundled in the Windows installer. The installer also registers the PATH entry so the gs binary can be found.

### Linux-Specific

GTK-native file dialogs are used via file_picker. The app requires GTK 3.x or later. Ghostscript is not bundled — users who have `gs` in their system PATH get the enhanced compression; others fall back to the Dart-based approach.

---

## 16. State Management Pattern

### Per-Feature AsyncNotifier

Each feature has exactly one `AsyncNotifier` subclass that holds the complete screen state. Screen state is defined as a `@freezed` immutable data class containing all the information the screen needs to render: the list of loaded files, the list of task progress objects (one per file), the current processing parameters, and a flag indicating whether processing is currently running.

The notifier exposes methods that the screen calls in response to user actions: `addFiles()`, `removeFile()`, `updateParams()`, `processAll()`, `cancelTask()`, `clearAll()`. Each method mutates the state by creating a new state object (via freezed's `copyWith`) and updating `this.state`.

The `processAll()` method is the core of each feature. It iterates through the file list, dispatches each to the IsolatePool, and updates the corresponding task's status in the state as each completes. Because state is immutable and updates are atomic, the UI always reflects a consistent snapshot.

### Why Not Bloc

Bloc (Business Logic Component) enforces a more strict event→state pipeline with explicit event classes for every user action. For PixelTools, this would require defining 8–10 event classes per feature. The AsyncNotifier pattern achieves the same result with less boilerplate, and the explicit method calls (`notifier.addFiles(...)`) are more readable than dispatching typed events. Riverpod's architecture review tools (the Riverpod lint package) provide the same static analysis benefits.

### Provider Scope and Lifetime

Feature notifiers use `autoDispose` — when the feature screen is no longer in the widget tree, the notifier is automatically disposed and its state is garbage collected. This means navigating away from the Resize screen clears its file list and processing state. This is intentional: tool screens start fresh each visit.

The exception is the IsolatePool, HistoryService, and CapabilityService, which are created at app startup and live for the entire app lifecycle. These are provided without `autoDispose`.

---

## 17. Data Persistence & History

### What Is Persisted

Hive stores three categories of data:

**Operation History** — The last 50 operations, as described in the HistoryService section. This is a ring buffer keyed by operation ID.

**User Preferences** — Dark/light mode override, default output format per tool, default quality setting, default naming pattern for splits, and whether GPS stripping is enabled for the converter. Stored as a simple key-value map in a dedicated Hive box.

**Custom Presets** — User-defined dimension presets for the Resizer. Each preset has a name, width, and height. Stored as a typed list in a dedicated Hive box. Custom presets appear above the built-in presets in the preset dropdown.

### What Is NOT Persisted

Processed file bytes are never stored permanently. After export, the bytes are discarded. If the user wants to re-access a processed file, they must re-process from the original. The history entry records the output file path (if the user chose "Save to Files"), but the bytes themselves are not retained. This keeps the app's storage footprint minimal.

### Hive Schema Versioning

Hive type adapters are generated at build time. The type ID numbers for each model class are fixed and must never be changed or reused. When a model's schema changes (adding or removing a field), the existing adapter handles migration via default values for new fields. If a breaking schema change is needed, a new type ID is used and a migration path is written in the box initialization.

---

## 18. Export & File I/O Strategy

### The Two-Phase File Access Pattern

All features follow a two-phase approach to file access:

**Phase 1 (Main Thread)** — File paths are collected from the picker or drop zone. File metadata (name, size) is read from the path. Actual file bytes are read from disk. This phase happens on the main thread but uses async I/O (non-blocking).

**Phase 2 (Isolate)** — The bytes collected in Phase 1 are passed to the Isolate. The Isolate processes the bytes and returns the result bytes. No file I/O happens inside the Isolate — only computation.

This two-phase separation is important because file handles and OS-level I/O are not safe to use from within Isolates on all platforms. By reading all input bytes before spawning the Isolate, and having the Isolate return pure data, platform I/O issues are avoided entirely.

### Output Naming Convention

Output filenames follow predictable patterns that users can customize:
- Resize: `{original_name}_resized.{format}`
- Collage: `collage_{timestamp}.{format}`
- Convert: `{original_name}.{target_format}`
- PDF Compress: `{original_name}_compressed.pdf`
- PDF Merge: `merged_{timestamp}.pdf`
- PDF Split (ZIP): `{original_name}_split_{timestamp}.zip`
- Image to PDF: `images_{timestamp}.pdf`

Custom naming patterns can be set in Settings using the same token system described in the Splitter feature.

### Temporary File Management

The export flow for Share creates temporary files in the OS's temp directory. These are cleaned up after the share action completes (the share_plus library handles this). For features that allow multiple exports of the same result, the temp file is cached for the session and cleaned up when the app goes to background or the feature screen is disposed.

---

## 19. Error Handling & Recovery

### Error Type Hierarchy

Errors are typed using a sealed `Failure` class. The specific subtypes are:

**FileReadFailure** — The input file could not be read. Possible causes: file was moved/deleted after selection, permission denied, file is locked by another process. Recovery: prompt to re-select the file.

**DecodeFailure** — The file bytes could not be decoded as the expected image or PDF format. Possible causes: corrupted file, unsupported codec variant (e.g., a WebP using a feature the decoder doesn't support), format mismatch detected by magic bytes. Recovery: show specific format details, suggest trying a different source file.

**EncodeFailure** — The processed data could not be encoded to the target format. Possible causes: out of memory during encoding (very large images), unsupported conversion path. Recovery: suggest reducing output dimensions or using a different target format.

**OutOfMemoryFailure** — Detected when the Isolate throws an `OutOfMemoryError`. Recovery: clear the processing queue, suggest processing fewer files simultaneously or reducing input image dimensions.

**PermissionFailure** — Storage or photos permission was denied. Recovery: show an inline prompt to open the Settings app and grant permission.

**UnsupportedFormatFailure** — The requested conversion is not supported on the current platform (e.g., HEIC on Android API <31, AVIF on iOS <16). Recovery: suggest an alternative format.

### Error Display in the UI

Errors at the per-file level are shown inline in the ProgressRail as red status dots with the error message below the filename. A retry button appears for retryable errors (FileReadFailure, EncodeFailure). Non-retryable errors (UnsupportedFormatFailure) show an explanation and a "Remove" button.

Errors at the operation level (e.g., unable to read the PDF structure during merge) are shown as a banner at the top of the screen with a descriptive message and a dismiss action.

No errors produce uncaught exceptions that crash the app. Every use case is wrapped in try/catch at the boundary.

---

## 20. Testing & Quality Strategy

### Unit Testing — Use Cases

Every use case has dedicated unit tests that verify:
- Correct output dimensions for resize operations
- Correct aspect ratio preservation in Fit mode
- Correct cropping behavior in Fill mode
- Alpha flattening produces opaque output when converting transparent formats to JPEG
- Page range parser produces correct zero-indexed output for various input strings
- The ZIP encoder produces a valid ZIP with the expected number of files

Tests use real (small) fixture image files and PDFs stored in `test/fixtures/`. They do not mock the processing libraries — the tests verify the actual output quality, not just that a method was called.

### Widget Testing — Shared Widgets

The DropZone, ProgressRail, FileChip, and FormatChipGroup widgets each have widget tests that verify:
- Correct initial state rendering
- State transitions (hover, error, success) render the correct visual
- Tap callbacks are invoked correctly
- Text content matches the provided labels

### Integration Testing

Integration tests run the full app on a real device (or emulator) and verify end-to-end flows:
- Add a file → configure settings → process → verify output is available for export
- Navigate between tools without errors
- Share a PDF into the app → verify correct tool is opened with file pre-loaded

### Static Analysis

The project uses the `riverpod_lint` and `flutter_lints` analysis packages. These catch: missing `ref.watch` vs `ref.read` usage errors, unreachable providers, widget rebuild issues, and general Dart best practices.

All analysis warnings are treated as errors in CI. No code is merged to main with analysis warnings.

### Code Generation

The project uses build_runner to generate: `@freezed` immutable data classes (with `copyWith`, equality, `toString`), Riverpod `@riverpod` annotations (generating providers from notifier classes), JSON serialization, and Hive type adapters. Code generation must be run after any model change and the generated files are committed to the repository (not gitignored) to avoid requiring every developer to run the generator after checkout.

---

## 21. Build Sequence & Delivery Roadmap

### Why This Specific Sequence

The build sequence is designed so that each phase produces working, testable, shippable software. No phase is "infrastructure only with nothing to show." Each phase adds a complete user-facing feature while also advancing the shared infrastructure.

The Resize feature is built first because it exercises the entire stack: file picking, Isolate processing, format encoding, and export. Getting Resize working correctly proves that every layer of the architecture works. Every subsequent feature is a variation on this proven pattern.

### Phase 1 — Foundation (Weeks 1–2)

Set up the complete project scaffold: folder structure, pubspec.yaml, core infrastructure (router, theme, DI providers, IsolatePool), shared widgets (DropZone, ProgressRail, FileChip, ExportSheet), and shared services (FilePickerService, ExportService, PermissionService, HistoryService). No feature processing logic. The app at this point shows the UI shell with empty screens and functional navigation.

**Definition of done:** App runs on iOS, Android, macOS, and Windows. Navigation works between all screens. File picker can be opened and closed. No processing yet.

### Phase 2 — Image Resizer (Week 3)

Full implementation of the Image Resizer feature. All four resize modes, quality control, batch processing with the IsolatePool, ProgressRail integration, and export via ExportSheet. Custom presets. Preset dimensions.

**Definition of done:** A batch of 20 4K images can be resized to HD in under 10 seconds with no UI jank. Output quality is visually correct for all four resize modes. Export works on all target platforms.

### Phase 3 — Format Converter & Image Compress (Week 4)

Format Converter with full format matrix, magic byte detection, alpha flattening, EXIF handling, and animated GIF support. Image Compress (same pipeline as Resize but focused on quality reduction with no dimension change). These reuse ~80% of the Phase 2 infrastructure.

**Definition of done:** All format conversions in the matrix work correctly. Alpha-to-opaque conversion produces correct results. EXIF stripping removes GPS data from output files.

### Phase 4 — PDF Compress & Image to PDF (Weeks 5–6)

Introduction of the PDF library stack. PDF Compressor with all three presets, before/after size comparison, metadata removal, and (on desktop) Ghostscript integration. Image to PDF with all page size and orientation options.

**Definition of done:** A 20MB scanned PDF compresses to under 6MB in Print preset. 10 images convert to a PDF with correct page sizing in under 5 seconds.

### Phase 5 — PDF Merge & Split (Weeks 7–8)

PDF Merger with page thumbnail rendering, range selection, drag reordering, and merge algorithm. PDF Splitter with all three split modes, naming pattern tokens, and ZIP streaming export.

**Definition of done:** A 5-document merge with custom page ranges completes correctly. A 200-page document can be split into individual pages as a ZIP without memory exhaustion.

### Phase 6 — Collage Builder (Weeks 9–10)

Most complex feature. Grid layout system, live CustomPainter preview with lazy thumbnail loading, drag-to-reorder image slots, canvas configuration, and the image package-based full-resolution composite renderer in Isolate.

**Definition of done:** A 6-image 2400×1600px collage renders in under 5 seconds. The live preview remains responsive while rendering. All 8 grid layouts produce geometrically correct output.

### Phase 7 — Polish & Store Submission (Weeks 11–12)

History drawer with operation log and re-download capability. Batch queue UX improvements: global cancel, retry-all-errors button. Responsive layout testing at all breakpoints on physical devices. Onboarding screens for first launch. App icons for all platforms. Store screenshots. Privacy policy. Terms of service.

**Definition of done:** App passes App Store and Google Play review. App is submitted to the Mac App Store and Microsoft Store. All four platform builds are tested on physical devices.

---

## Appendix — Feature Summary Reference

| Feature | Input | Output | Key Processing | Isolate |
|---|---|---|---|---|
| Image Resizer | 1–50 images | Resized images | Decode → Transform → Encode | Yes |
| Collage Builder | 2–9 images | Single composite | Decode → Composite → Encode | Yes |
| Format Converter | 1–50 images | Converted images | Detect → Flatten → Re-encode | Yes |
| Image Compress | 1–50 images | Compressed images | Decode → Lower quality → Encode | Yes |
| PDF Compressor | 1 PDF | Compressed PDF | Parse → Resample images → Rewrite | Yes |
| PDF Merger | 2–20 PDFs | Single PDF | Parse → Copy pages → Save | Yes |
| PDF Splitter | 1 PDF | ZIP of PDFs | Parse → Split pages → ZIP | Yes |
| Image to PDF | 1–50 images | Single PDF | Decode → Embed → Save | Yes |

---

> Every feature in PixelTools follows the same architectural pattern: domain entities define the data contract, use cases contain the isolated logic, notifiers manage reactive state, and screens compose shared widgets. Master one feature fully and you understand the entire codebase.
