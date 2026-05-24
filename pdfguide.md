Act as a Principal Flutter and Android Native Architect. I am building a high-performance PDF manipulation app (Compress, Merge, Split, Convert to Images) that must handle heavy files smoothly on modern Android (including Android 11 through 14+ Scoped Storage rules).

### The Objective
Write a production-grade, highly optimized Flutter architecture. It must completely avoid copying selected files into the app's internal `/data/` directory or bloating device RAM. The implementation must read files using zero-copy pipelines, offload heavy calculations to background threads to keep the UI fluid, and save files directly into user-selected public directories using Android's Storage Access Framework (SAF).

### Technical Requirements
1. **Zero-Copy File I/O:** Use `saf_util` (for native SAF dialog picking) combined with `saf_stream` (for streaming bytes directly from a virtual URI bridge) instead of standard path-based file pickers.
2. **Background Multi-Threading:** Every PDF modification task (Compress, Merge, Split, Image Rendering) must execute inside a background Dart Isolate using `compute()` or `Isolate.run()` to keep the main UI running smoothly at 60/120 FPS.
3. **Memory Integrity:** Use `syncfusion_flutter_pdf` for structural operations (Merge, Split, Compress) and `pdfx` for raster operations (Convert to Images). Ensure that every PDF object, template, page, and document stream explicitly calls `.dispose()` inside the isolate workers to instantly free native C/C++ heap memory and prevent out-of-memory (OOM) crashes.

### Generate the Following Implementation Structures

Please write clean, documented Dart code for the following components:

#### 1. Pubspec Dependencies Block
Provide the clean `dependencies:` section for `pubspec.yaml` containing the latest compatible versions of `saf_util`, `saf_stream`, `syncfusion_flutter_pdf`, and `pdfx`.

#### 2. The Native Bridge Wrapper (`PdfWorkflowManager`)
Create a production class that implements:
* `Future<void> executePipeline(PdfOperationType operation)`: Invokes `saf_util` to pick the source file and target destination directory URI. It reads the file bytes directly via `saf_stream`, passes them into an isolate worker, and dumps the output payload straight to the chosen directory.

#### 3. Isolated Performance Workers (Static Isolate Methods)
Provide four heavily optimized, static isolate methods that receive `Uint8List` or `List<Uint8List>` payloads and return ready-to-save byte arrays:
* **`_isolateCompressWorker`**: Reduces PDF size by downscaling images or vector layouts, using explicit manual resource cleanup.
* **`_isolateMergeWorker`**: Joins multiple PDF streams into one file by copying structural references page-by-page (rather than loading full documents into memory).
* **`_isolateSplitWorker`**: Extract specific pages out into independent standalone files.
* **`_isolateToImagesWorker`**: Render PDF document pages into independent, compressed JPEG/PNG `Uint8List` image lists page-by-page using `pdfx` / native renderer bounds.

#### 4. Architecture Safeguards Checklist
Add a concise Markdown summary listing the critical performance patterns implemented (e.g., how the code prevents RAM spikes during PDF rendering, and why it doesn't need the risky `MANAGE_EXTERNAL_STORAGE` permission).

Write the implementation cleanly, with robust error handling and clear inline comments explaining how memory is managed throughout the pipeline.