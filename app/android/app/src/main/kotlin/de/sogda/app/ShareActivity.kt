package de.sogda.app

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
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
     * rule), and an image as its provider says, when it says.
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
        ).orEmpty().filter { uri ->
            fromAnotherApp(uri) &&
                contentResolver.getType(uri)?.startsWith("image/") != false
        }

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
     * [uris] copied to `cache/shared/` in order, numbered so two of one name
     * stay two, the share before deleted. One that fails to copy is left out.
     * D1 drops the copies once read (#1298); a kept page is rewritten
     * without its metadata (BR-DOC-05).
     */
    // ponytail: copied as sent, not resized like the picker's 2400 px: a
    // 12 MP photo is read and kept at full size. Resize here if kept pages
    // grow too big.
    private fun copyImages(uris: List<Uri>): List<String> {
        val folder = sharedFolder()
        return uris.mapIndexedNotNull { i, uri ->
            runCatching {
                val number = (i + 1).toString().padStart(2, '0')
                val file = File(folder, "$number-${displayName(uri) ?: "photo.jpg"}")
                copy(uri, file)
                file.path
            }.getOrNull()
        }
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
