package de.sogda.app

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.encryption.InvalidPasswordException
import com.tom_roush.pdfbox.text.PDFTextStripper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * `lib/services/pdf_text.dart`: a PDF's text layer, page by page (#1228,
 * ADR 31), with pdfbox-android, on a worker thread. Dart opens a document,
 * asks for each page in turn (D1's "Reading page 2 of 4…", and *Cancel*
 * between two pages), and closes it.
 *
 * - `open {source}` → `{handle, pages}`. The source is a `content:` URI (the
 *   picker, a share) or a path. A password-protected file fails with
 *   `password`, anything else unreadable with `unreadable`.
 * - `page {handle, page}` → the page's text, 1-based.
 * - `close {handle}`.
 */
object PdfText {
    const val CHANNEL = "sogda/pdf"

    /** One thread: the documents are only ever touched from it. */
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val documents = mutableMapOf<Int, PDDocument>()
    private var nextHandle = 0
    private var fontsLoaded = false

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            fun answer(work: () -> Any?) = worker.execute {
                val outcome = runCatching(work)
                main.post {
                    outcome.fold(
                        { result.success(it) },
                        {
                            val code = if (it is InvalidPasswordException) "password" else "unreadable"
                            result.error(code, it.message, null)
                        },
                    )
                }
            }
            when (call.method) {
                "open" -> answer {
                    if (!fontsLoaded) {
                        PDFBoxResourceLoader.init(app)
                        fontsLoaded = true
                    }
                    val source = call.argument<String>("source")!!
                    val stream = if (source.startsWith("content:")) {
                        app.contentResolver.openInputStream(Uri.parse(source))
                            ?: throw IllegalArgumentException("no stream for $source")
                    } else {
                        File(source).inputStream()
                    }
                    // A large file spills to the cache, not the heap: a 2 GB
                    // phone reads it too.
                    val memory = MemoryUsageSetting.setupMixed(16L * 1024 * 1024)
                        .setTempDir(app.cacheDir)
                    val document = stream.use { PDDocument.load(it, memory) }
                    val handle = ++nextHandle
                    documents[handle] = document
                    mapOf("handle" to handle, "pages" to document.numberOfPages)
                }
                "page" -> answer {
                    val document = documents[call.argument<Int>("handle")!!]
                        ?: throw IllegalStateException("closed")
                    val page = call.argument<Int>("page")!!
                    PDFTextStripper().apply {
                        startPage = page
                        endPage = page
                    }.getText(document)
                }
                "close" -> answer {
                    documents.remove(call.argument<Int>("handle")!!)?.close()
                    null
                }
                else -> result.notImplemented()
            }
        }
    }
}
