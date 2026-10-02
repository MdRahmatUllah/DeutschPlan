package de.sogda.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle

/**
 * "Share → Sogda" with text from another app (#1227, FR-D1-01): no window of
 * its own. It opens [MainActivity] as the widget does (`NEW_TASK | CLEAR_TOP`,
 * a `sogda:` link), so the share lands in the app's own task and its one
 * Flutter engine, never in the sender's task as a second copy of the app. The
 * link is [MainActivity.SHARE_LINK], an arrival like any other: a running
 * exam holds it (`app_router.dart`).
 *
 * The text stays in this process ([take]), never on the intent to
 * [MainActivity]: that activity is exported and BROWSABLE, so an extra on its
 * intent could come from any app, or from a web page's `intent://` link, and
 * D1 would save it without the share sheet ever being chosen.
 */
class ShareActivity : Activity() {
    companion object {
        @Volatile private var pending: String? = null

        /** The text the last share brought, once (`sogda/share`). */
        fun take(): String? = pending.also { pending = null }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val text = intent?.takeIf { it.action == Intent.ACTION_SEND }
            ?.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        if (!text.isNullOrBlank()) {
            // ponytail: held whole; D1 cuts it to 20,000 characters. Cut here
            // too if a share ever runs to megabytes.
            pending = text
            startActivity(
                Intent(this, MainActivity::class.java)
                    .setData(Uri.parse(MainActivity.SHARE_LINK))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            )
        }
        finish()
    }
}
