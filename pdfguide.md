Act as a Principal Flutter and Android Native Architect. I am building a high-performance PDF manipulation app (Compress, Merge, Split, Convert to Images) optimized for modern Android (Android 11 through 14+ Scoped Storage). 

### The Objective
Write a production-grade, highly stable Flutter architecture. To ensure 100% compatibility with standard PDF libraries, the app must follow a two-phase "Sandbox-to-Public" architecture:
1. **The Sandbox Phase:** Read and process files using standard Dart `File(path)` operations inside the app's secure, isolated temporary app directory (`/data/.../cache`), utilizing background threads to avoid freezing the UI.
2. **The Export Phase:** Manually stream the final processed file out to a public, user-defined custom directory (e.g., Downloads, Documents) using Android's native Storage Access Framework (SAF) to bypass Scoped Storage restrictions, followed by immediate background cache cleanup.

### Technical Requirements
1. **Local Processing I/O:** Use standard `file_picker` to fetch paths and manage internal file copies inside the application directory sandbox for low-latency editing.
2. **Manual SAF Export Bridge:** Use `saf_stream` (via `writeFileBytes`) combined with `FilePicker.platform.getDirectoryPath()` or `FilePicker.platform.saveFile()` to manually push the final bytes across the Scoped Storage boundary into the user-selected folder.
3. **Background Multi-Threading:** Every PDF modification task (Compress, Merge, Split, Image Rendering) must run inside a background Dart Isolate using `compute()` or `Isolate.run()` to keep the main UI fluid at 60/120 FPS.
4. **Memory & Cache Housekeeping:** Use `syncfusion_flutter_pdf` for structural operations and `pdfx` for image conversions. Ensure all PDF objects call `.dispose()` inside isolates. After exporting to the custom directory, immediately invoke `file.delete()` on all temporary sandbox copies to keep the app's disk footprint at 0 MB.

### Generate the Following Implementation Structures

Please write clean, production-ready, and fully documented Dart code for the following components:

#### 1. Pubspec Dependencies Block
Provide the clean `dependencies:` section for `pubspec.yaml` containing compatible versions of `file_picker`, `saf_stream`, `syncfusion_flutter_pdf`, and `pdfx`.

#### 2. The Private-To-Public Orchestrator (`PrivateToPublicPdfManager`)
Create a production wrapper class that implements the entire pipeline:
* It picks a file, copies it to the app sandbox cache, and executes a selected PDF action.
* It invokes the folder selector, extracts the bytes of the locally completed file, and exports them out to the public directory.
* It implements strict `try-catch-finally` blocks ensuring that sandbox cache files are deleted *even if the processing or export step fails*.

#### 3. Isolated Performance Workers (Static Isolate Methods)
Provide four heavily optimized, static isolate methods that receive file paths or raw bytes and return the processed output:
* **`_isolateCompressWorker`**: Reduces PDF size by downscaling images/vectors inside the local file sandbox.
* **`_isolateMergeWorker`**: Combines multiple local PDF files into one output file by stitching structural page templates.
* **`_isolateSplitWorker`**: Extracts specific page ranges out into standalone files within the cache directory.
* **`_isolateToImagesWorker`**: Renders PDF pages into independent, compressed JPEG/PNG `Uint8List` image lists page-by-page using `pdfx` / native renderer bounds.

#### 4. Architecture Safeguards Checklist
Add a concise Markdown summary listing why this dual-phase sandbox approach avoids raw URI library compatibility errors and why it eliminates the need for the dangerous `MANAGE_EXTERNAL_STORAGE` permission.

Write the implementation cleanly, with robust error handling and clear inline comments explaining how file lifecycles and cache directories are managed throughout the pipeline.