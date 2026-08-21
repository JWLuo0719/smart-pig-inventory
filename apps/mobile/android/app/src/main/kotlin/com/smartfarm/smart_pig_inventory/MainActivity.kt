package com.smartfarm.smart_pig_inventory

import android.graphics.BitmapFactory
import android.webkit.MimeTypeMap
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.smartfarm.inventory/image-metadata"
        ).setMethodCallHandler { call, result ->
            if (call.method != "read") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            if (path.isNullOrBlank()) {
                result.error("invalid_argument", "Missing image path", null)
                return@setMethodCallHandler
            }
            try {
                result.success(readImageMetadata(path))
            } catch (error: Exception) {
                result.error("metadata_unavailable", error.message, null)
            }
        }
    }

    private fun readImageMetadata(path: String): Map<String, Any> {
        val file = File(path)
        if (!file.isFile) throw IllegalArgumentException("Image file does not exist")
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw IllegalArgumentException("Unsupported or incomplete image")
        }
        val orientation = ExifInterface(path).getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_UNDEFINED
        )
        val rotated = orientation in setOf(
            ExifInterface.ORIENTATION_TRANSPOSE,
            ExifInterface.ORIENTATION_ROTATE_90,
            ExifInterface.ORIENTATION_TRANSVERSE,
            ExifInterface.ORIENTATION_ROTATE_270
        )
        val extension = MimeTypeMap.getFileExtensionFromUrl(file.name).lowercase()
        val detectedContentType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: when (extension) {
                "heic", "heif" -> "image/heic"
                else -> throw IllegalArgumentException("Unsupported image extension")
            }
        val contentType = if (detectedContentType == "image/heif") "image/heic" else detectedContentType
        if (contentType !in setOf("image/jpeg", "image/png", "image/heic")) {
            throw IllegalArgumentException("Unsupported image type")
        }
        return mutableMapOf<String, Any>(
            "width" to if (rotated) bounds.outHeight else bounds.outWidth,
            "height" to if (rotated) bounds.outWidth else bounds.outHeight,
            "contentType" to contentType
        ).apply {
            if (orientation in ExifInterface.ORIENTATION_NORMAL..ExifInterface.ORIENTATION_ROTATE_270) {
                put("orientation", orientation)
            }
        }
    }
}
