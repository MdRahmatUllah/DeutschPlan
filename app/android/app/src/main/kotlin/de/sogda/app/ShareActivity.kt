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
 * "Share → Sogda" with text (#1227) or a PDF (#1228) from another app
 * (FR-D1-01): no window of its own. It opens [MainActivity] as the widget
 * does (`NEW_TASK | CLEAR_TOP`, a `sogda:` link), so the share lands in the
 * app's own task and its one Flutter engine, never in the sender's task as a
 * second copy of the app. The link is [MainActivity.SHARE_LINK], an arrival
 * like any other: a running exam holds it (`app_router.dart`).
 *
 * What was shared stays in this process ([take], [takePdf]), never on the
 * intent to [MainActivity]: that activity is exported and BROWSABLE, so an
 * extra on its intent could come from any app, or from a web page's
 * `intent://` link, and D1 would save it without the share sheet ever being
 * chosen.
 */
class ShareActivity : Activity() {
    companion object {
        @Volatile private var pending: String? = null
        @Volatile private var pendingPdf: String? = null

        /** The text the last share brought, once (`sogda/share`). */
        fun take(): String? = pending.also { pending = null }

        /** The PDF the last share brought, as a copy in the cache, once. */
        fun takePdf(): String? = pendingPdf.also { pendingPdf = null }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val share = intent?.takeIf { it.action == Intent.ACTION_SEND }
        val pdf = share?.takeIf { it.type == "application/pdf" }?.let(::stream)
        if (pdf != null) {
            // The copy, off the main thread: the sender's grant to read the
            // URI lasts while this activity does, so it finishes after.
            Thread {
                // A copy that fails (the grant revoked, the disk full) still
                // opens D1, on its choices: the share wasn't lost unseen.
                pending = null
                pendingPdf = runCatching { copyPdf(pdf) }.getOrNull()
                open()
                runOnUiThread { finish() }
            }.start()
            return
        }
        val text = share?.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        if (!text.isNullOrBlank()) {
            // ponytail: held whole; D1 cuts it to 20,000 characters. Cut here
            // too if a share ever runs to megabytes.
            pendingPdf = null
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
        )?.takeIf { uri ->
            uri.scheme == ContentResolver.SCHEME_CONTENT &&
                uri.authority?.startsWith(packageName) == false
        }

    /**
     * [uri] copied to `cache/shared/`, under its own name (D1 shows it), the
     * share before it deleted. pdfbox reads the copy page by page.
     */
    // ponytail: no size cap; a huge PDF is copied whole into the cache, and
    // D1 reads its first 30 pages. Cap it if a share ever fills a phone. A
    // cloud file (Drive) downloads here, behind the invisible window, for as
    // long as that takes: a progress note if that's ever seconds too long.
    private fun copyPdf(uri: Uri): String {
        val folder = File(cacheDir, "shared")
        folder.deleteRecursively()
        folder.mkdirs()
        val name = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null }
            ?.replace(Regex("[^\\p{L}\\p{N} ._-]"), "_")
            ?.takeIf { it.isNotBlank() }
            ?: "shared.pdf"
        val file = File(folder, if (name.endsWith(".pdf", ignoreCase = true)) name else "$name.pdf")
        contentResolver.openInputStream(uri)!!.use { input ->
            file.outputStream().use { input.copyTo(it) }
        }
        return file.path
    }
}
