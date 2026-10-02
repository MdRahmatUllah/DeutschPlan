package de.sogda.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle

/**
 * "Share → Sogda" with text from another app (#1227, FR-D1-01): no window of
 * its own. It hands the text to [MainActivity] as the widget opens it
 * (`NEW_TASK | CLEAR_TOP`, a `sogda:` link), so the share lands in the app's
 * own task and its one Flutter engine, never in the sender's task as a second
 * copy of the app. The link is [MainActivity.SHARE_LINK], an arrival like any
 * other: a running exam holds it (`app_router.dart`). The text goes as an
 * extra, never as data (#613).
 */
class ShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val text = intent?.takeIf { it.action == Intent.ACTION_SEND }
            ?.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        if (!text.isNullOrBlank()) {
            startActivity(
                Intent(this, MainActivity::class.java)
                    .setData(Uri.parse(MainActivity.SHARE_LINK))
                    .putExtra(MainActivity.EXTRA_SHARED_TEXT, text)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            )
        }
        finish()
    }
}
