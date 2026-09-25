package com.example.deutschplan

import android.os.Build
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
    private companion object {
        const val CHANNEL = "deutschplan/glass"

        /** `lib/services/device_storage.dart`: M4's free space (#156). */
        const val STORAGE_CHANNEL = "deutschplan/storage"
    }

    private var channel: MethodChannel? = null
    private var blurListener: Consumer<Boolean>? = null

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
