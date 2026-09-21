package com.example.deutschplan

import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
 * Android has no "reduce transparency" accessibility setting, so that half of
 * the answer is always false here; iOS supplies it.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "deutschplan/glass"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
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
    }

    private fun supportsBlur(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        val windowManager = getSystemService(WindowManager::class.java) ?: return false
        return windowManager.isCrossWindowBlurEnabled
    }
}
