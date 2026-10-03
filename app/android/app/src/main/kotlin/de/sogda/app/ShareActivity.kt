package de.sogda.app

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.util.Log
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import java.io.File

/**
 * "Share → Sogda" with text (#1227), a PDF (#1228) or photos (#1332) from
 * another app (FR-D1-01): no window of its own. It opens [MainActivity] as the widget
 * does (`NEW_TASK | CLEAR_TOP`, a `sogda:` link), so the share lands in the
 * app's own task and its one Flutter engine, never in the sender's task as a
 * second copy of the app. The link is [MainActivity.SHARE_LINK], an arrival
 * like any other: a running exam holds it (`app_router.dart`).
 *
 * What was shared stays in this process ([take], [takePdf], [takeImages]),
 * never on the
 * intent to [MainActivity]: that activity is exported and BROWSABLE, so an
 * extra on its intent could come from any app, or from a web page's
 * `intent://` link, and D1 would save it without the share sheet ever being
 * chosen.
 */
class ShareActivity : Activity() {
    companion object {
        @Volatile private var pending: String? = null
        @Volatile private var pendingPdf: String? = null
        @Volatile private var pendingImages: Map<String, Any>? = null

        /** D1's page limit (`docMaxPages`, BR-DOC-02). */
        private const val MAX_PAGES = 30

        /** The picker's page (`page_photos.dart`): at most 2400 px wide, JPEG 90. */
        private const val MAX_WIDTH = 2400
        private const val QUALITY = 90

        /** The text the last share brought, once (`sogda/share`). */
        fun take(): String? = pending.also { pending = null }

        /** The PDF the last share brought, as a copy in the cache, once. */
        fun takePdf(): String? = pendingPdf.also { pendingPdf = null }

        /**
         * The photos the last share brought, once: `pages`, their copies in
         * the cache in the order shared, at most [MAX_PAGES], and `of`, how
         * many were shared.
         */
        fun takeImages(): Map<String, Any>? = pendingImages.also { pendingImages = null }

        private fun clear() {
            pending = null
            pendingPdf = null
            pendingImages = null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val share = intent?.takeIf {
            it.action == Intent.ACTION_SEND || it.action == Intent.ACTION_SEND_MULTIPLE
        }
        val pdf = share?.takeIf { it.type == "application/pdf" }?.let(::stream)
        val images = share?.takeIf { it.type?.startsWith("image/") == true }
            ?.let(::streams)
            .orEmpty()
        if (pdf != null || images.isNotEmpty()) {
            // The copies, off the main thread: the sender's grant to read the
            // URIs lasts while this activity does, so it finishes after.
            Thread {
                // A copy that fails (the grant revoked, the disk full) still
                // opens D1, on its choices: the share wasn't lost unseen.
                clear()
                if (pdf != null) {
                    pendingPdf = runCatching { copyPdf(pdf) }.getOrNull()
                } else {
                    val pages = copyImages(images.take(MAX_PAGES))
                    if (pages.isNotEmpty()) {
                        pendingImages = mapOf("pages" to pages, "of" to images.size)
                    }
                }
                open()
                runOnUiThread { finish() }
            }.start()
            return
        }
        val text = share?.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        if (!text.isNullOrBlank()) {
            // ponytail: held whole; D1 cuts it to 20,000 characters. Cut here
            // too if a share ever runs to megabytes.
            clear()
            pending = text
            open()
        }
        finish()
    }

    private fun open() = startActivity(
        Intent(this, MainActivity::class.java)
            .setData(Uri.parse(MainActivity.SHARE_LINK))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
    )

    /**
     * The shared file, only as another app's `content:` URI. A `file:` path,
     * or a provider of Sogda's own (a plugin's, under its package), would be
     * opened with Sogda's permissions: a crafted share could have it copy
     * its own private files (a confused deputy).
     */
    @Suppress("DEPRECATION")
    private fun stream(intent: Intent): Uri? =
        (
            if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
        )?.takeIf(::fromAnotherApp)

    /**
     * The photos shared (#1332): one on `SEND`, several on `SEND_MULTIPLE`,
     * in the sender's order, each another app's `content:` URI ([stream]'s
     * rule). Not the type its provider names: some say
     * `application/octet-stream` for a WebP; [page] decodes each, and one
     * that isn't an image is left out there.
     */
    @Suppress("DEPRECATION")
    private fun streams(intent: Intent): List<Uri> =
        (
            if (intent.action == Intent.ACTION_SEND) {
                listOfNotNull(stream(intent))
            } else if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            }
        ).orEmpty().filter(::fromAnotherApp)

    private fun fromAnotherApp(uri: Uri): Boolean =
        uri.scheme == ContentResolver.SCHEME_CONTENT &&
            uri.authority?.startsWith(packageName) == false

    /**
     * [uri] copied to `cache/shared/`, under its own name (D1 shows it), the
     * share before it deleted. pdfbox reads the copy page by page.
     */
    // ponytail: no size cap; a huge PDF is copied whole into the cache, and
    // D1 reads its first 30 pages. Cap it if a share ever fills a phone. A
    // cloud file (Drive) downloads here, behind the invisible window, for as
    // long as that takes: a progress note if that's ever seconds too long.
    private fun copyPdf(uri: Uri): String {
        val name = displayName(uri) ?: "shared.pdf"
        val file = File(sharedFolder(), if (name.endsWith(".pdf", ignoreCase = true)) name else "$name.pdf")
        copy(uri, file)
        return file.path
    }

    /**
     * [uris] as pages in `cache/shared/`, in order, numbered so two of one
     * name stay two, the share before deleted. Each is the picker's page
     * ([page]); one that can't be read is left out.
     */
    private fun copyImages(uris: List<Uri>): List<String> {
        val folder = sharedFolder()
        return uris.mapIndexedNotNull { i, uri ->
            runCatching {
                val number = (i + 1).toString().padStart(2, '0')
                val name = (displayName(uri) ?: "photo").substringBeforeLast('.')
                val file = File(folder, "$number-$name.jpg")
                page(uri, file)
                file.path
            }.onFailure { Log.w("SogdaShare", "shared page ${i + 1} not read", it) }
                .getOrNull()
        }
    }

    /**
     * [uri] written to [file] as the picker writes a chosen page (agent-2 on
     * #1371): upright, at most [MAX_WIDTH] wide, a JPEG at [QUALITY]. ML Kit
     * then never decodes a 200 MP photo whole (~800 MB), a HEIC or WebP page
     * becomes one D1 can keep, and the copy carries no metadata at all (no
     * GPS, BR-DOC-05), even one left behind. Decoded at the smallest power
     * of two that stays at least [MAX_WIDTH] wide.
     */
    // ponytail: the width alone bounds it, as the picker's maxWidth: a very
    // long screenshot (1080 x 20000) is decoded whole, ~90 MB. Cap the
    // height too if one ever runs out of memory.
    private fun page(uri: Uri, file: File) {
        // A format with no EXIF (or none this phone reads) stands as drawn.
        val degrees = runCatching {
            contentResolver.openInputStream(uri)!!.use { input ->
                when (ExifInterface(input).getAttributeInt(ExifInterface.TAG_ORIENTATION, 0)) {
                    ExifInterface.ORIENTATION_ROTATE_90 -> 90
                    ExifInterface.ORIENTATION_ROTATE_180 -> 180
                    ExifInterface.ORIENTATION_ROTATE_270 -> 270
                    else -> 0
                }
            }
        }.getOrDefault(0)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        contentResolver.openInputStream(uri)!!.use { BitmapFactory.decodeStream(it, null, bounds) }
        // The page's width as it stands, once turned upright.
        val width = if (degrees % 180 == 0) bounds.outWidth else bounds.outHeight
        require(width > 0) { "not an image" }
        var sample = 1
        while (width / (sample * 2) >= MAX_WIDTH) sample *= 2
        val decoded = contentResolver.openInputStream(uri)!!.use {
            BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
        } ?: error("not an image")
        val scale = MAX_WIDTH.toFloat() / (if (degrees % 180 == 0) decoded.width else decoded.height)
        val matrix = Matrix().apply {
            if (scale < 1) postScale(scale, scale)
            postRotate(degrees.toFloat())
        }
        val upright = if (matrix.isIdentity) {
            decoded
        } else {
            Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
        }
        file.outputStream().use { upright.compress(Bitmap.CompressFormat.JPEG, QUALITY, it) }
        if (upright !== decoded) upright.recycle()
        decoded.recycle()
    }

    /** `cache/shared/`, emptied: one share's copies at a time. */
    private fun sharedFolder(): File = File(cacheDir, "shared").apply {
        deleteRecursively()
        mkdirs()
    }

    /** [uri]'s name as its provider gives it, made safe for a file name. */
    private fun displayName(uri: Uri): String? =
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null }
            ?.replace(Regex("[^\\p{L}\\p{N} ._-]"), "_")
            ?.takeIf { it.isNotBlank() }

    private fun copy(uri: Uri, file: File) {
        contentResolver.openInputStream(uri)!!.use { input ->
            file.outputStream().use { input.copyTo(it) }
        }
    }
}
