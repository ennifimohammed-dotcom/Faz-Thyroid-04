
import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.io.File

class MainActivity : FlutterActivity() {
    private val xlsxMime = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    private val reqPick = 4101
    private val reqCapture = 4102
    private var pendingResult: MethodChannel.Result? = null
    private var pendingCaptureUri: Uri? = null

    private fun copyToAttachments(uri: Uri): String? {
        val dir = File(filesDir, "attachments")
        if (!dir.exists()) dir.mkdirs()
        val out = File(dir, "img_" + System.currentTimeMillis() + ".jpg")
        val input = contentResolver.openInputStream(uri) ?: return null
        input.use { i -> out.outputStream().use { o -> i.copyTo(o) } }
        return out.absolutePath
    }

    /// Les 14 premieres lignes de la trace d'une erreur (diagnostic affiche dans l'application).
    private fun trace(e: Throwable): String {
        val sw = java.io.StringWriter()
        e.printStackTrace(java.io.PrintWriter(sw))
        return sw.toString().lines().take(14).joinToString("\n")
    }

    /// Decode la photo (reduite a 2600 px max) et lit son orientation EXIF.
    private fun decodeForOcr(path: String): Pair<Bitmap, Int>? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        var sample = 1
        while (Math.max(bounds.outWidth, bounds.outHeight) / sample > 2600) sample *= 2
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        val bmp = BitmapFactory.decodeFile(path, opts) ?: return null
        var rotation = 0
        try {
            val exif = ExifInterface(path)
            rotation = when (exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90
                ExifInterface.ORIENTATION_ROTATE_180 -> 180
                ExifInterface.ORIENTATION_ROTATE_270 -> 270
                else -> 0
            }
        } catch (e: Throwable) {
            rotation = 0
        }
        return Pair(bmp, rotation)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != reqPick && requestCode != reqCapture) return
        val res = pendingResult
        pendingResult = null
        val captureUri = pendingCaptureUri
        pendingCaptureUri = null
        if (res == null) return
        try {
            if (resultCode != Activity.RESULT_OK) {
                if (captureUri != null) contentResolver.delete(captureUri, null, null)
                res.success(null)
                return
            }
            val src: Uri? = if (requestCode == reqCapture) captureUri else data?.data
            if (src == null) {
                res.success(null)
                return
            }
            val path = copyToAttachments(src)
            if (requestCode == reqCapture && captureUri != null) {
                contentResolver.delete(captureUri, null, null)
            }
            res.success(path)
        } catch (e: Throwable) {
            res.error("IMAGE_FAILED", e.toString(), null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "faztyroid/files")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        try {
                            val name = call.argument<String>("name")
                            val bytes = call.argument<ByteArray>("bytes")
                            if (name == null || bytes == null) {
                                result.error("BAD_ARGS", "Arguments manquants", null)
                            } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                                result.error("UNSUPPORTED", "Android 10 ou plus requis", null)
                            } else {
                                val values = ContentValues().apply {
                                    put(MediaStore.Downloads.DISPLAY_NAME, name)
                                    put(MediaStore.Downloads.MIME_TYPE, xlsxMime)
                                    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                                }
                                val uri = contentResolver.insert(
                                    MediaStore.Downloads.EXTERNAL_CONTENT_URI, values
                                )
                                if (uri == null) {
                                    result.error("NO_URI", "Création du fichier impossible", null)
                                } else {
                                    contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                                    result.success(uri.toString())
                                }
                            }
                        } catch (e: Throwable) {
                            result.error("SAVE_FAILED", e.toString(), null)
                        }
                    }
                    "shareFile" -> {
                        try {
                            val uriText = call.argument<String>("uri")
                            if (uriText == null) {
                                result.error("BAD_ARGS", "URI manquante", null)
                            } else {
                                val send = Intent(Intent.ACTION_SEND).apply {
                                    type = xlsxMime
                                    putExtra(Intent.EXTRA_STREAM, Uri.parse(uriText))
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                startActivity(Intent.createChooser(send, null))
                                result.success(null)
                            }
                        } catch (e: Throwable) {
                            result.error("SHARE_FAILED", e.toString(), null)
                        }
                    }
                    "pickImage" -> {
                        if (pendingResult != null) {
                            result.error("BUSY", "Une sélection est déjà en cours", null)
                        } else {
                            try {
                                pendingResult = result
                                val pick = Intent(Intent.ACTION_GET_CONTENT).apply {
                                    type = "image/*"
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                }
                                startActivityForResult(Intent.createChooser(pick, null), reqPick)
                            } catch (e: Throwable) {
                                pendingResult = null
                                result.error("PICK_FAILED", e.toString(), null)
                            }
                        }
                    }
                    "captureImage" -> {
                        if (pendingResult != null) {
                            result.error("BUSY", "Une capture est déjà en cours", null)
                        } else {
                            try {
                                val values = ContentValues().apply {
                                    put(MediaStore.Images.Media.DISPLAY_NAME, "FazTyroid_" + System.currentTimeMillis() + ".jpg")
                                    put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                                }
                                val uri = contentResolver.insert(
                                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values
                                )
                                if (uri == null) {
                                    result.error("NO_URI", "Création de la photo impossible", null)
                                } else {
                                    pendingResult = result
                                    pendingCaptureUri = uri
                                    val shot = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                                        putExtra(MediaStore.EXTRA_OUTPUT, uri)
                                    }
                                    startActivityForResult(shot, reqCapture)
                                }
                            } catch (e: Throwable) {
                                pendingResult = null
                                pendingCaptureUri = null
                                result.error("CAPTURE_FAILED", e.toString(), null)
                            }
                        }
                    }
                    "recognizeText" -> {
                        try {
                            val path = call.argument<String>("path")
                            if (path == null) {
                                result.error("BAD_ARGS", "Chemin manquant", null)
                            } else {
                                val decoded = decodeForOcr(path)
                                if (decoded == null) {
                                    result.error("DECODE_FAILED", "Image illisible", null)
                                } else {
                                    val image = InputImage.fromBitmap(decoded.first, decoded.second)
                                    val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                                    recognizer.process(image)
                                        .addOnSuccessListener { text ->
                                            try {
                                                val lines = ArrayList<HashMap<String, Any>>()
                                                for (block in text.textBlocks) {
                                                    for (line in block.lines) {
                                                        val corners = ArrayList<Int>()
                                                        val cp = line.cornerPoints
                                                        val box = line.boundingBox
                                                        if (cp != null && cp.size >= 4) {
                                                            for (i in 0 until 4) {
                                                                corners.add(cp[i].x)
                                                                corners.add(cp[i].y)
                                                            }
                                                        } else if (box != null) {
                                                            corners.addAll(listOf(
                                                                box.left, box.top, box.right, box.top,
                                                                box.right, box.bottom, box.left, box.bottom
                                                            ))
                                                        } else {
                                                            continue
                                                        }
                                                        val item = HashMap<String, Any>()
                                                        item["text"] = line.text
                                                        item["corners"] = corners
                                                        lines.add(item)
                                                    }
                                                }
                                                result.success(lines)
                                            } catch (e: Throwable) {
                                                result.error("OCR_RESULT_FAILED", trace(e), null)
                                            } finally {
                                                recognizer.close()
                                            }
                                        }
                                        .addOnFailureListener { e ->
                                            recognizer.close()
                                            result.error("OCR_FAILED", trace(e), null)
                                        }
                                }
                            }
                        } catch (e: Throwable) {
                            result.error("OCR_SETUP_FAILED", trace(e), null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
