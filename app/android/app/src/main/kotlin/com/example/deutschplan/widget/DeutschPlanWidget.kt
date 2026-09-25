package com.example.deutschplan.widget

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import java.time.LocalDate
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.example.deutschplan.MainActivity
import com.example.deutschplan.R
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver
import org.json.JSONObject

/** X1's receiver (#160): what the app's `HomeWidget.updateWidget` names. */
class DeutschPlanWidgetReceiver : HomeWidgetGlanceWidgetReceiver<DeutschPlanWidget>() {
    override val glanceAppWidget = DeutschPlanWidget()
}

/**
 * X1 · the home-screen widget (`widget.md`, the Widget artboards): small 2 x 2 — the ring,
 * "8 left" and the step — and medium 4 x 2, which adds Wort des Tages with *Pronounce*.
 * Drawn from the snapshot the app writes (`widget_snapshot`, #159); its words are in it too,
 * in the learner's language.
 */
class DeutschPlanWidget : GlanceAppWidget() {
    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override val sizeMode = SizeMode.Responsive(setOf(SMALL, MEDIUM))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            val raw = currentState<HomeWidgetGlanceState>().preferences
                .getString(SNAPSHOT, null)
            Widget(raw?.let { runCatching { JSONObject(it) }.getOrNull() }?.takeIf(::current))
        }
    }

    companion object {
        /** The key `HomeWidgetStore` writes (`widget_snapshot.dart`). */
        const val SNAPSHOT = "widget_snapshot"
        val SMALL = DpSize(110.dp, 110.dp)
        val MEDIUM = DpSize(250.dp, 110.dp)
    }
}

/**
 * The text at [key], or "" for a missing key or a JSON null: `optString` gives
 * the string "null" for those, and "null bitte" is what a word without an
 * article would say.
 */
private fun JSONObject.text(key: String): String = if (isNull(key)) "" else optString(key)

/**
 * Today's snapshot, written since #160. One from an earlier day (a redraw before
 * the midnight task has run) or without the words says to open the app instead.
 */
private fun current(snapshot: JSONObject): Boolean =
    snapshot.has("copy") && snapshot.text("date") == LocalDate.now().toString()

private val ink = ColorProvider(R.color.widget_ink)
private val secondary = ColorProvider(R.color.widget_secondary)

@Composable
private fun Widget(snapshot: JSONObject?) {
    val context = LocalContext.current
    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            // A drawable, so the corners are round below Android 12 too, where
            // `cornerRadius` does nothing; it still clips the content above.
            .background(ImageProvider(R.drawable.widget_card))
            .cornerRadius(18.dp)
            .padding(12.dp)
            // FR-X1-02: the widget itself opens Today.
            .clickable(open(context, "deutschplan://today")),
    ) {
        when {
            snapshot == null -> Text(
                text = context.getString(R.string.widget_empty),
                style = TextStyle(color = ink, fontSize = 13.sp),
            )
            LocalSize.current.width >= DeutschPlanWidget.MEDIUM.width -> Medium(snapshot)
            else -> Small(snapshot)
        }
    }
}

/** The small size: the step and the app's name, then the ring and what is left. */
@Composable
private fun Small(snapshot: JSONObject) {
    val copy = snapshot.optJSONObject("copy") ?: JSONObject()
    Column(modifier = GlanceModifier.fillMaxSize()) {
        Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Step(snapshot.text("step"))
            Spacer(GlanceModifier.defaultWeight())
            Text(
                text = copy.text("app"),
                style = TextStyle(color = ink, fontSize = 11.sp, fontWeight = FontWeight.Bold),
            )
        }
        Spacer(GlanceModifier.defaultWeight())
        Row(verticalAlignment = Alignment.CenterVertically) {
            Ring(snapshot, 48)
            Spacer(GlanceModifier.width(10.dp))
            Column {
                val done = snapshot.optBoolean("done")
                Text(
                    text = copy.text(if (done) "done" else "left"),
                    // "Done for today" is three words beside the ring; "8 left" is the number.
                    style = TextStyle(color = ink, fontSize = if (done) 14.sp else 20.sp, fontWeight = FontWeight.Bold),
                    maxLines = 2,
                )
                Text(
                    text = copy.text(if (done) "tomorrow" else "minutes"),
                    style = TextStyle(color = secondary, fontSize = 11.sp),
                    maxLines = 2,
                )
            }
        }
    }
}

/** The medium size: the ring with "12/20" and "8 left · A2.1", then Wort des Tages. */
@Composable
private fun Medium(snapshot: JSONObject) {
    val context = LocalContext.current
    val copy = snapshot.optJSONObject("copy") ?: JSONObject()
    val word = snapshot.optJSONObject("wordOfDay")
    Row(modifier = GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
        Column(
            modifier = GlanceModifier.width(96.dp).fillMaxHeight(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(contentAlignment = Alignment.Center) {
                Ring(snapshot, 64)
                if (!snapshot.optBoolean("done")) {
                    Text(
                        text = copy.text("progress"),
                        style = TextStyle(color = ink, fontSize = 14.sp, fontWeight = FontWeight.Bold),
                    )
                }
            }
            Spacer(GlanceModifier.height(8.dp))
            Text(
                text = copy.text(if (snapshot.optBoolean("done")) "done" else "leftStep"),
                style = TextStyle(color = ink, fontSize = 11.sp, fontWeight = FontWeight.Bold),
                maxLines = 1,
            )
        }
        Box(
            modifier = GlanceModifier
                .width(1.dp)
                .fillMaxHeight()
                .padding(vertical = 4.dp)
                .background(ColorProvider(R.color.widget_outline)),
        ) {}
        Spacer(GlanceModifier.width(12.dp))
        Column(modifier = GlanceModifier.defaultWeight()) {
            if (word == null) {
                // No word due within three days: tomorrow's plan instead.
                Text(
                    text = copy.text(if (snapshot.optBoolean("done")) "tomorrow" else "minutes"),
                    style = TextStyle(color = secondary, fontSize = 12.sp),
                )
                return@Column
            }
            val uid = word.text("uid")
            Text(
                text = copy.text("wordOfDay").uppercase(),
                style = TextStyle(color = secondary, fontSize = 10.sp, fontWeight = FontWeight.Bold),
            )
            Spacer(GlanceModifier.height(4.dp))
            // FR-X1-02: the word opens it.
            Row(modifier = GlanceModifier.clickable(open(context, "deutschplan://word/$uid"))) {
                val article = word.text("article")
                if (article.isNotEmpty()) {
                    Text(
                        text = "$article ",
                        style = TextStyle(color = articleColour(article), fontSize = 20.sp),
                    )
                }
                Text(
                    text = word.text("german"),
                    style = TextStyle(color = ink, fontSize = 20.sp),
                    maxLines = 1,
                )
            }
            Text(
                text = word.text("meaning"),
                style = TextStyle(color = secondary, fontSize = 12.sp),
                maxLines = 1,
            )
            Spacer(GlanceModifier.height(6.dp))
            // FR-X1-02: *Pronounce* opens the word and plays it.
            Row(
                modifier = GlanceModifier.clickable(open(context, "deutschplan://word/$uid?speak=1")),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Image(
                    provider = ImageProvider(R.drawable.widget_play),
                    contentDescription = null,
                    modifier = GlanceModifier.size(26.dp),
                )
                Spacer(GlanceModifier.width(6.dp))
                Text(
                    text = copy.text("pronounce"),
                    style = TextStyle(color = ink, fontSize = 12.sp, fontWeight = FontWeight.Bold),
                )
            }
            // "Done for the day → Lime check and tomorrow's preview" (the Widget artboard).
            if (snapshot.optBoolean("done") && copy.has("tomorrow")) {
                Spacer(GlanceModifier.height(6.dp))
                Text(
                    text = copy.text("tomorrow"),
                    style = TextStyle(color = secondary, fontSize = 11.sp),
                    maxLines = 1,
                )
            }
        }
    }
}

/** "A2.1" on Sun with the ink edge. */
@Composable
private fun Step(code: String) {
    if (code.isEmpty()) return
    Box(
        modifier = GlanceModifier
            .background(ImageProvider(R.drawable.widget_step))
            .padding(horizontal = 6.dp, vertical = 2.dp),
    ) {
        Text(
            text = code,
            style = TextStyle(color = ColorProvider(R.color.widget_on_accent), fontSize = 11.sp, fontWeight = FontWeight.Bold),
        )
    }
}

/**
 * The day's ring, or the Lime check once it is done. The track and the check are drawables and
 * the arc a white bitmap tinted Lagoon, all by resource: the launcher resolves those, so a switch
 * between light and dark shows at once. Glance has no determinate ring, hence the bitmap.
 */
@Composable
private fun Ring(snapshot: JSONObject, sizeDp: Int) {
    val size = GlanceModifier.size(sizeDp.dp)
    if (snapshot.optBoolean("done")) {
        Image(provider = ImageProvider(R.drawable.widget_done), contentDescription = null, modifier = size)
        return
    }
    val total = snapshot.optInt("total", 0)
    val share = if (total == 0) 0f else (total - snapshot.optInt("remaining", 0)).toFloat() / total
    Box {
        Image(provider = ImageProvider(R.drawable.widget_ring_track), contentDescription = null, modifier = size)
        if (share > 0f) {
            Image(
                provider = ImageProvider(ringArc(LocalContext.current, sizeDp, share)),
                contentDescription = null,
                modifier = size,
                colorFilter = ColorFilter.tint(ColorProvider(R.color.widget_primary)),
            )
        }
    }
}

/** The arc from twelve o'clock, as `widget_ring_track` draws its track: 14% of the ring wide. */
private fun ringArc(context: Context, sizeDp: Int, share: Float): Bitmap {
    val px = (sizeDp * context.resources.displayMetrics.density).toInt()
    val stroke = px * 0.14f
    val bitmap = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = stroke
        strokeCap = Paint.Cap.ROUND
        color = Color.WHITE
    }
    val box = RectF(stroke / 2, stroke / 2, px - stroke / 2, px - stroke / 2)
    Canvas(bitmap).drawArc(box, -90f, 360f * share.coerceAtMost(1f), false, paint)
    return bitmap
}

private fun articleColour(article: String): ColorProvider = when (article) {
    "der" -> ColorProvider(R.color.widget_der)
    "die" -> ColorProvider(R.color.widget_die)
    "das" -> ColorProvider(R.color.widget_das)
    else -> ink
}

/** A `deutschplan://` link into the app, which its router resolves (`deep_links.dart`). */
private fun open(context: Context, link: String): Action =
    actionStartActivity(
        Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .setData(Uri.parse(link))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
    )
