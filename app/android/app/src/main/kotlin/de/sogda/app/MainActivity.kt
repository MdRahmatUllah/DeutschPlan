package de.sogda.app

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.StatFs
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.function.Consumer

/**
 * Answers the glass capability query from `lib/core/theme/glass_capability.dart`.
 *
 * `docs/01-architecture/theming.md` degrades glass to an opaque surface on
 * "Android API < 31". API 31 is where cross-window blur exists at all, but the
 * platform can also refuse it at runtime — battery saver, "disable window
 * blurs" in developer options, or a device whose GPU cannot afford it. Asking
 * `isCrossWindowBlurEnabled` covers the documented rule and those cases in one
 * call, so a BackdropFilter is never paid for when it would render nothing.
 *
 * That value is not fixed for the session: battery saver can engage at any
 * time, so the listener below pushes changes instead of leaving Dart to find
 * out two seconds of dropped frames later.
 *
 * Android has no "reduce transparency" accessibility setting, so that half of
 * the answer is always false here; iOS supplies it.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "sogda/glass"

        /** `lib/services/device_storage.dart`: M4's free space (#156). */
        private const val STORAGE_CHANNEL = "sogda/storage"

        /** `lib/services/start_report.dart`: the start drawn in full (#462). */
        private const val START_CHANNEL = "sogda/start"

        /** `lib/services/shared_text.dart`: text shared from another app (#1227). */
        private const val SHARE_CHANNEL = "sogda/share"

        /** Where [ShareActivity] sends a share: D1 (`deep_links.dart`). */
        const val SHARE_LINK = "sogda://import"

        /** The shared text, on [ShareActivity]'s intent to this activity. */
        const val EXTRA_SHARED_TEXT = "de.sogda.app.SHARED_TEXT"
    }

    private var channel: MethodChannel? = null

    /** The text [ShareActivity] passed on, until D1 takes it (#1227). */
    private var sharedText: String? = null
    private var blurListener: Consumer<Boolean>? = null

    /**
     * #613: this activity is exported, and Flutter hands any intent's data to
     * the router as its route, and a `route` extra as the first one. Only
     * `sogda:` links are the app's. Another app's data is dropped here, before
     * Flutter reads it, because a scheme-less `/exam/7` could not be told from
     * the app's own navigation once it reached Dart (`app_router.dart` turns
     * away the rest).
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        // #1227: a share is taken once. An activity restored from recents
        // gets its first intent again, and D1 then opens with no text rather
        // than saving the same document twice.
        takeShare(intent, keep = savedInstanceState == null)
        ownLinksOnly(intent)
        super.onCreate(savedInstanceState)
        // #854: the system splash's exit reveal (Android 12+) is removed at
        // once rather than animated. `splash.md` wants no visible hand-off,
        // and a reveal cut short under load is the likeliest cause of the
        // app-wide ~12 % dim SQA saw three times. Flutter's splash docs
        // suggest the same.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            splashScreen.setOnExitAnimationListener { view -> view.remove() }
        }
    }

    override fun onNewIntent(intent: Intent) {
        takeShare(intent, keep = true)
        ownLinksOnly(intent)
        super.onNewIntent(intent)
    }

    /**
     * [ShareActivity]'s text, kept for D1 when [keep], and off the intent
     * either way. Only with the share's own link: any other intent's extra
     * is dropped unread.
     */
    private fun takeShare(intent: Intent, keep: Boolean) {
        if (keep && intent.dataString == SHARE_LINK) {
            sharedText = intent.getStringExtra(EXTRA_SHARED_TEXT)
        }
        intent.removeExtra(EXTRA_SHARED_TEXT)
    }

    /** No `route` extra: the first route is the intent's `sogda:` link, if any. */
    override fun getInitialRoute(): String? = null

    private fun ownLinksOnly(intent: Intent) {
        if (intent.data != null && intent.data?.scheme != "sogda") intent.data = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        this.channel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "capabilities" -> result.success(
                    mapOf(
                        "supportsBlur" to supportsBlur(),
                        "reduceTransparency" to false,
                    )
                )
                else -> result.notImplemented()
            }
        }

        registerBlurListener(channel)

        // The space M4's card shows and a model download is checked against:
        // the volume the app's files, and so the models, live on.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "space" -> {
                        val stat = StatFs(filesDir.path)
                        result.success(
                            mapOf(
                                "free" to stat.availableBytes,
                                "total" to stat.totalBytes,
                            )
                        )
                    }
                    else -> result.notImplemented()
                }
            }

        // #1227: D1 takes the shared text once; null when there's none.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "take" -> {
                        result.success(sharedText)
                        sharedText = null
                    }
                    else -> result.notImplemented()
                }
            }

        // The cold start's end: Today with its plan, or setup's first page.
        // The system logs it as "Fully drawn", after the first frame's
        // "Displayed", which is only the splash (#462).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, START_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "fullyDrawn" -> {
                        reportFullyDrawn()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun registerBlurListener(channel: MethodChannel) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val windowManager = getSystemService(WindowManager::class.java) ?: return

        val listener = Consumer<Boolean> { enabled ->
            runOnUiThread {
                channel.invokeMethod(
                    "capabilitiesChanged",
                    mapOf("supportsBlur" to enabled),
                )
            }
        }
        blurListener = listener
        windowManager.addCrossWindowBlurEnabledListener(mainExecutor, listener)
    }

    /**
     * #462: FlutterActivity reports fully drawn here, at Flutter's first
     * frame, which is only the splash, and Android keeps the first report
     * alone. The app reports it itself once Today shows its plan (or setup
     * its first page), through [START_CHANNEL]. Not calling super is the
     * point: that is all super does.
     */
    override fun onFlutterUiDisplayed() {}

    override fun onDestroy() {
        val listener = blurListener
        if (listener != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(WindowManager::class.java)
                ?.removeCrossWindowBlurEnabledListener(listener)
        }
        blurListener = null
        channel = null
        super.onDestroy()
    }

    private fun supportsBlur(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        val windowManager = getSystemService(WindowManager::class.java) ?: return false
        return windowManager.isCrossWindowBlurEnabled
    }
}
