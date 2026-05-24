# Role & Context
You are an expert Flutter developer and systems architect specializing in high-performance mobile imaging, document processing, and native device storage management. 

I am building a Flutter application with an advanced image/PDF editing feature. I need your guidance to design and implement a robust, production-ready "Multi-Image Document Scanner" module. Keep in mind to keep existing features.

---

# Technical Requirements & Features to Implement

### 1. Camera Capture & UX
- Live camera stream tracking using a custom UI overlay.
- Real-time computer vision processing to detect document contours/quadrangles.
- Auto-capture functionality: automatically snap the frame when a stable document boundary is detected for more than 1.5 seconds.
- Flash automation based on ambient light metrics.

### 2. Image Processing Pipeline (Local/On-Device)
- Perspective Correction / Dewarping: Transform the detected skewed quadrangle into a clean, flat, 4-corner rectangular image.
- Image Filtering Suite: Implement algorithms/shaders for:
  - Magic Color / Enhancement (high contrast, vivid text).
  - Binarization (stark black-and-white thresholding for text crispness).
  - Shadow Removal (uniform background lighting).
- Rotational adjustments (90-degree manual crop/rotation updates per page).

### 3. Internal Batch/Directory Architecture
- Temporary Storage Management: Before saving anything to public device storage, save captured images into the app's secure internal storage (`ApplicationDocumentsDirectory`).
- Directory Layout: Group images into "Batch Directories" representing a single multi-page document sequence (e.g., `temp_scans/batch_uuid/page_0.jpg`, `page_1.jpg`).
- State Management: Provide a clean architecture (using Bloc, Riverpod, or ChangeNotifier) to track, add, delete, and support drag-and-drop reordering of pages within a batch.

### 4. Inteligent Export Processing
- On-Device OCR: Use local text recognition to extract document text. Use this text to suggest a smart file name based on headings or dates found on page 1.
- Searchable PDF Generation: Compile the images sequentially into a single PDF, overlaying the invisible OCR text layer perfectly over the graphics to make the output document searchable.
- PDF Compression Pipeline: Compress imagery dynamically (downsampling resolution and adjusting JPEG quality factors) to ensure multi-page PDFs remain small enough for email attachments.

---

# Implementation Strategy Guidelines

To ensure the codebase scales cleanly and maintains high performance, your recommendations must strictly adhere to the following architectural patterns:

1. **Performance over Convenience:** Image manipulation and real-time processing must be written with performance in mind. Offload heavy transformations (Dewarping, Filtering, PDF compilation) to background isolates to completely eliminate UI stuttering.
2. **Clean Separation of Concerns:** Separate the Camera View UI from the Computer Vision Controller, the Local File Repository, and the PDF Generator Engine.
3. **Optimized Package Ecosystem:** Favor robust, reliable ecosystem packages (such as `camera` or `camerawesome`, `google_mlkit_text_recognition`, `pdf`, `path_provider`, and high-performance native bridges or C++ plugins like `opencv_dart` where performance demands it).

---

# Execution Protocol

Do not write the entire application all at once. We will tackle this systematically, module by module. 

To kick things off, please analyze this specification and provide a high-level **System Architecture Design Document**. Include an overview of the recommended file/folder structure for this feature, a state diagram explaining the lifecycle of a document batch from capture to final PDF export, and a breakdown of the packages you recommend using. Hold off on writing deep code blocks until we sign off on this core layout.