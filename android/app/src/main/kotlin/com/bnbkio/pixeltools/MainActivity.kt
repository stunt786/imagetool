package com.bnbkio.pixeltools

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.net.URLDecoder

/**
 * Scoped-storage friendly save pipeline.
 *
 * Shared-storage writes go through MediaStore (Android 10+) or the legacy
 * public directories (Android 6-9, guarded by WRITE_EXTERNAL_STORAGE), and
 * user-chosen folders go through a persisted Storage Access Framework tree.
 * This replaces the previous raw `/storage/emulated/0/...` writes that only
 * worked with MANAGE_EXTERNAL_STORAGE.
 */
class MainActivity : FlutterActivity() {
    private var pendingTreeResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                METHOD_SAVE_BYTES -> {
                    val bytes = call.argument<ByteArray>("bytes")
                        ?: throw IllegalArgumentException("bytes is required")
                    val fileName = call.argument<String>("displayName")
                        ?: throw IllegalArgumentException("displayName is required")
                    result.success(
                        saveToPublicStorage(
                            bytes = bytes,
                            sourcePath = null,
                            fileName = fileName,
                            kind = call.argument<String>("kind") ?: KIND_DOCUMENT,
                            treeUri = call.argument<String>("treeUri"),
                            subPath = call.argument<String>("subPath"),
                        )
                    )
                }
                METHOD_SAVE_FILE -> {
                    val sourcePath = call.argument<String>("sourcePath")
                        ?: throw IllegalArgumentException("sourcePath is required")
                    val fileName = call.argument<String>("displayName")
                        ?: throw IllegalArgumentException("displayName is required")
                    result.success(
                        saveToPublicStorage(
                            bytes = null,
                            sourcePath = sourcePath,
                            fileName = fileName,
                            kind = call.argument<String>("kind") ?: KIND_DOCUMENT,
                            treeUri = call.argument<String>("treeUri"),
                            subPath = call.argument<String>("subPath"),
                        )
                    )
                }
                METHOD_PICK_TREE -> pickTree(result)
                METHOD_DESCRIBE_TREE -> {
                    val uri = call.argument<String>("uri")
                        ?: throw IllegalArgumentException("uri is required")
                    result.success(describeTree(uri))
                }
                METHOD_RELEASE_TREE -> {
                    val uri = call.argument<String>("uri")
                        ?: throw IllegalArgumentException("uri is required")
                    releaseTree(uri)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            result.error(ERROR_PERMISSION, e.message ?: "Storage permission required", null)
        } catch (e: Exception) {
            result.error(ERROR_SAVE, e.message ?: "Saving the file failed", null)
        }
    }

    private fun saveToPublicStorage(
        bytes: ByteArray?,
        sourcePath: String?,
        fileName: String,
        kind: String,
        treeUri: String?,
        subPath: String?,
    ): String {
        val mime = mimeFor(fileName, kind)
        if (treeUri != null) {
            return saveToTree(treeUri, fileName, bytes, sourcePath, mime)
        }
        val isImage = kind == KIND_IMAGE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return saveViaMediaStore(isImage, fileName, mime, bytes, sourcePath, subPath)
        }
        return saveViaLegacyPublicDir(isImage, fileName, mime, bytes, sourcePath, subPath)
    }

    /** Android 10+ (scoped storage): permissionless MediaStore insert. */
    private fun saveViaMediaStore(
        isImage: Boolean,
        fileName: String,
        mime: String,
        bytes: ByteArray?,
        sourcePath: String?,
        subPath: String?,
    ): String {
        val collection =
            if (isImage) MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            else MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val rootDir =
            if (isImage) Environment.DIRECTORY_PICTURES
            else Environment.DIRECTORY_DOWNLOADS
        val subDirectory = if (isImage) DEFAULT_IMAGE_SUBDIR else (subPath ?: DEFAULT_DOCUMENT_SUBDIR)

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "$rootDir/$subDirectory")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(collection, values)
            ?: throw IllegalStateException("Android did not create a media entry for $fileName")

        try {
            val out = contentResolver.openOutputStream(uri)
                ?: throw IllegalStateException("Android could not open $fileName for writing")
            out.use { stream -> writeContent(stream, bytes, sourcePath) }
            contentResolver.update(uri, ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }, null, null)
        } catch (e: Exception) {
            runCatching { contentResolver.delete(uri, null, null) }
            throw e
        }

        val storedName = queryDisplayName(uri) ?: fileName
        val base = Environment.getExternalStoragePublicDirectory(rootDir)
        return File(File(base, subDirectory), storedName).absolutePath
    }

    /** Android 6-9: plain file write into the public directories. */
    private fun saveViaLegacyPublicDir(
        isImage: Boolean,
        fileName: String,
        mime: String,
        bytes: ByteArray?,
        sourcePath: String?,
        subPath: String?,
    ): String {
        if (checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException(
                "Writing to shared storage needs the storage permission on this Android version."
            )
        }
        val rootDir =
            if (isImage) Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
            else Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val subDirectory = if (isImage) DEFAULT_IMAGE_SUBDIR else (subPath ?: DEFAULT_DOCUMENT_SUBDIR)
        val directory = File(rootDir, subDirectory)
        if (!directory.exists() && !directory.mkdirs()) {
            throw IllegalStateException("Could not create ${directory.absolutePath}")
        }
        var target = File(directory, fileName)
        target = deduplicate(target)
        target.outputStream().use { stream -> writeContent(stream, bytes, sourcePath) }
        MediaScannerConnection.scanFile(this, arrayOf(target.absolutePath), arrayOf(mime), null)
        return target.absolutePath
    }

    /** Writes into a SAF folder tree picked by the user (Settings or export). */
    private fun saveToTree(
        treeUri: String,
        fileName: String,
        bytes: ByteArray?,
        sourcePath: String?,
        mime: String,
    ): String {
        val tree = DocumentFile.fromTreeUri(this, Uri.parse(treeUri))
            ?: throw IllegalStateException("The selected folder is no longer available.")
        var targetName = fileName
        var index = 1
        val dot = fileName.lastIndexOf('.')
        val base = if (dot > 0) fileName.substring(0, dot) else fileName
        val ext = if (dot > 0) fileName.substring(dot) else ""
        while (tree.findFile(targetName) != null) {
            targetName = "$base ($index)$ext"
            index++
        }
        val target = tree.createFile(mime, targetName)
            ?: throw IllegalStateException("Could not create $targetName in the selected folder.")
        val out = contentResolver.openOutputStream(target.uri, "wt")
            ?: throw IllegalStateException("Android could not open ${target.name} for writing")
        out.use { stream -> writeContent(stream, bytes, sourcePath) }
        return describeTree(treeUri) + "/" + target.name
    }

    private fun writeContent(
        out: java.io.OutputStream,
        bytes: ByteArray?,
        sourcePath: String?,
    ) {
        if (bytes != null) {
            out.write(bytes)
            return
        }
        if (sourcePath == null) throw IllegalArgumentException("No content to write")
        val source = File(sourcePath)
        if (!source.exists()) throw IllegalStateException("Source file $sourcePath is missing")
        FileInputStream(source).use { input -> input.copyTo(out) }
    }

    private fun queryDisplayName(uri: Uri): String? {
        return contentResolver.query(
            uri,
            arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
            null, null, null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    }

    private fun deduplicate(file: File): File {
        if (!file.exists()) return file
        val name = file.name
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var index = 1
        var candidate = File(file.parentFile, "$base ($index)$ext")
        while (candidate.exists()) {
            index++
            candidate = File(file.parentFile, "$base ($index)$ext")
        }
        return candidate
    }

    private fun pickTree(result: MethodChannel.Result) {
        if (pendingTreeResult != null) {
            result.error(ERROR_PICK, "A folder picker is already open.", null)
            return
        }
        pendingTreeResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
        )
        try {
            startActivityForResult(intent, REQUEST_PICK_TREE)
        } catch (e: Exception) {
            pendingTreeResult = null
            result.error(ERROR_PICK, e.message ?: "Could not open the folder picker.", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_PICK_TREE) {
            val pending = pendingTreeResult
            pendingTreeResult = null
            val uri = data?.data
            if (resultCode == Activity.RESULT_OK && uri != null) {
                try {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                    )
                } catch (_: SecurityException) {
                    // Some providers only grant one direction; both were requested.
                }
                pending?.success(uri.toString())
            } else {
                pending?.success(null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun describeTree(uri: String): String {
        val marker = "/tree/"
        val markerIndex = uri.indexOf(marker)
        val documentId = when {
            markerIndex >= 0 -> {
                val rest = uri.substring(markerIndex + marker.length)
                URLDecoder.decode(rest.substringBefore('/'), "UTF-8")
            }
            else -> URLDecoder.decode(uri.substringAfterLast('/'), "UTF-8")
        }
        return when {
            documentId.startsWith("primary:") ->
                Environment.getExternalStorageDirectory().absolutePath + "/" +
                    documentId.removePrefix("primary:")
            documentId.contains(':') -> "/storage/" + documentId.replace(':', '/')
            else -> documentId
        }
    }

    private fun releaseTree(uri: String) {
        try {
            contentResolver.releasePersistableUriPermission(
                Uri.parse(uri),
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (_: SecurityException) {
            // The grant was already released or never persisted.
        }
    }

    private fun mimeFor(fileName: String, kind: String): String {
        return when (fileName.substringAfterLast('.', "").lowercase()) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "webp" -> "image/webp"
            "gif" -> "image/gif"
            "bmp" -> "image/bmp"
            "tiff", "tif" -> "image/tiff"
            "heic" -> "image/heic"
            "heif" -> "image/heif"
            "pdf" -> "application/pdf"
            "txt" -> "text/plain"
            "csv" -> "text/csv"
            "json" -> "application/json"
            "html" -> "text/html"
            "htm" -> "text/html"
            "doc" -> "application/msword"
            "docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            "xls" -> "application/vnd.ms-excel"
            "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            else -> if (kind == KIND_IMAGE) "image/jpeg" else "application/octet-stream"
        }
    }

    companion object {
        private const val CHANNEL = "com.bnbkio.pixeltools/storage"
        private const val METHOD_SAVE_BYTES = "saveBytes"
        private const val METHOD_SAVE_FILE = "saveFile"
        private const val METHOD_PICK_TREE = "pickTree"
        private const val METHOD_DESCRIBE_TREE = "describeTree"
        private const val METHOD_RELEASE_TREE = "releaseTree"
        private const val ERROR_PERMISSION = "PERMISSION_REQUIRED"
        private const val ERROR_SAVE = "SAVE_FAILED"
        private const val ERROR_PICK = "PICK_FAILED"
        private const val KIND_IMAGE = "image"
        private const val KIND_DOCUMENT = "document"
        private const val DEFAULT_IMAGE_SUBDIR = "PixelTools"
        private const val DEFAULT_DOCUMENT_SUBDIR = "PixelTools"
        private const val REQUEST_PICK_TREE = 4821
    }
}
