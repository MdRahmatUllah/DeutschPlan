package de.sogda.app

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.util.Log
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.WindowManager
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

        /**
         * #1386: the last share's number, the photos it is still copying, and
         * the last copy. Copies run one at a time, each after the one before
         * (they share `cache/shared/`), and one a newer share overtook stops,
         * publishes nothing and deletes what it wrote.
         */
        @Volatile private var shares = 0
        @Volatile private var incoming = 0
        @Volatile private var copying: Thread? = null

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
        fun takeImages(): Map<String, Any>? {
            // #1386: D1 opened before the copies were made; it waits for them.
            // A call a newer share overtook while it waited takes nothing.
            val number = shares
            copying?.join()
            if (number != shares) return null
            return pendingImages.also { pendingImages = null }
        }

        /**
         * How many photos a share is still copying, 0 when none (#1386): D1
         * says «Receiving 34 photos…» at once, then [takeImages] waits for
         * them (off the main thread: it blocks).
         */
        fun receiving(): Int = incoming

        /** A new share: whatever an older one left, or is still copying, is dropped. */
        private fun clear() {
            pending = null
            pendingPdf = null
            pendingImages = null
            incoming = 0
            shares++
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
        // The copies, off the main thread: the sender's grant to read the
        // URIs lasts while this activity does, so it finishes after (and
        // isn't `noHistory`: D1 in front would finish it, the grant with it).
        // A copy that fails (the grant revoked, the disk full) still opens
        // D1, on its choices: the share wasn't lost unseen.
        if (pdf != null || images.isNotEmpty()) {
            // #1386: the invisible window stays for the whole copy, over the
            // sender: touches and keys go through to it, never to this one.
            window.addFlags(
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            )
            clear()
            val number = shares
            val current = { number == shares }
            val before = copying
            val copy = Thread {
                before?.join()
                try {
                    if (pdf != null) {
                        val path = runCatching { copyPdf(pdf) }.getOrNull()
                        if (current()) {
                            pendingPdf = path
                            open()
                        } else {
                            path?.let { File(it).delete() }
                        }
                    } else {
                        val pages = copyImages(images.take(MAX_PAGES), current)
                        if (!current()) {
                            pages.forEach { File(it).delete() }
                        } else if (pages.isNotEmpty()) {
                            pendingImages = mapOf("pages" to pages, "of" to images.size)
                        }
                    }
                } finally {
                    if (current()) incoming = 0
                    runOnUiThread { finish() }
                }
            }
            copying = copy
            if (images.isEmpty()) {
                copy.start()
                return
            }
            // #1386: D1 first, told how many are coming, and the copies behind
            // it: 34 photos took ~14 s, D1's idle choices on screen meanwhile.
            // A PDF, one file, is copied before D1 opens.
            incoming = images.size
            copy.start()
            open()
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
    private fun copyImages(uris: List<Uri>, current: () -> Boolean): List<String> {
        val folder = sharedFolder()
        // Overtaken by a newer share (#1386): no more pages.
        return uris.asSequence().takeWhile { current() }.withIndex().mapNotNull { (i, uri) ->
            runCatching {
                val number = (i + 1).toString().padStart(2, '0')
                val name = (displayName(uri) ?: "photo").substringBeforeLast('.')
                val file = File(folder, "$number-$name.jpg")
                page(uri, file)
                file.path
            }.onFailure { Log.w("SogdaShare", "shared page ${i + 1} not read", it) }
                .getOrNull()
        }.toList()
    }

    /**
     * [uri] written to [file] as the picker writes a chosen page (agent-2 on
     * #1371): upright, at most [MAX_WIDTH] wide, a JPEG at [QUALITY]. ML Kit
     * then never decodes a 200 MP photo whole (~800 MB), a HEIC or WebP page
     * becomes one D1 can keep, and the copy carries no metadata at all (no
     * GPS, BR-DOC-05), even one left behind.
     *
     * #1400: from Android 9, [ImageDecoder] decodes it straight at that
     * width, upright from its EXIF: a 12 MP photo is never ~48 MB in memory
     * (34 of them stalled a 2 GB phone for seconds). Before 9, [pageBefore28].
     */
    // ponytail: the width alone bounds it, as the picker's maxWidth: a very
    // long screenshot (1080 x 20000) is decoded whole, ~90 MB. Cap the
    // height too if one ever runs out of memory.
    private fun page(uri: Uri, file: File) {
        if (Build.VERSION.SDK_INT < 28) return pageBefore28(uri, file)
        val decoded = ImageDecoder.decodeBitmap(ImageDecoder.createSource(contentResolver, uri)) { decoder, info, _ ->
            // A software bitmap: compress() reads its pixels.
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            // The size as it stands, already turned upright.
            val (width, height) = info.size.width to info.size.height
            if (width > MAX_WIDTH) decoder.setTargetSize(MAX_WIDTH, height * MAX_WIDTH / width)
        }
        file.outputStream().use { decoded.compress(Bitmap.CompressFormat.JPEG, QUALITY, it) }
        decoded.recycle()
    }

    /**
     * [page] on Android 8: decoded at the smallest power of two that stays
     * at least [MAX_WIDTH] wide, turned upright and scaled.
     */
    // ponytail: Android 8's 12 MP photo is still decoded whole (~48 MB),
    // as before #1400; inDensity scaling if those phones ever stall.
    private fun pageBefore28(uri: Uri, file: File) {
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
