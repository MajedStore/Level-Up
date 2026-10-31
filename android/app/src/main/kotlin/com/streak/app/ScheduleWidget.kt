// Level Up — Based on Streak by InlitX. GPL-3.0-only.
package com.streak.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.text.TextPaint
import android.text.TextUtils
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import androidx.glance.currentState
import androidx.glance.layout.ContentScale
import androidx.glance.layout.fillMaxSize
import java.util.Calendar
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.json.JSONObject

/** Payload written by ScheduleWidgetService in Dart, shared by both widgets. */
internal object LevelUpWidgetData {
    const val KEY = "levelup_schedule"

    fun load(context: Context): JSONObject? = try {
        context
            .getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            .getString(KEY, null)
            ?.takeIf { it.isNotEmpty() }
            ?.let(::JSONObject)
            ?.takeIf { it.optInt("version") == 1 }
    } catch (e: Exception) {
        null
    }

    fun todayKey(now: Calendar): String = String.format(
        Locale.US,
        "%04d-%02d-%02d",
        now.get(Calendar.YEAR),
        now.get(Calendar.MONTH) + 1,
        now.get(Calendar.DAY_OF_MONTH),
    )

    fun today(root: JSONObject?, now: Calendar): JSONObject? {
        val days = root?.optJSONArray("days") ?: return null
        val key = todayKey(now)
        for (i in 0 until days.length()) {
            val day = days.optJSONObject(i) ?: continue
            if (day.optString("key") == key) return day
        }
        return null
    }

    /** Arabic-Indic digits when the app is in Arabic, like the in-app labels. */
    fun digits(text: String, arabic: Boolean): String =
        if (!arabic) text else text.map { if (it in '0'..'9') '٠' + (it - '0') else it }.joinToString("")
}

/**
 * Home-screen schedule drawn like the in-app timeline: hour gutter, blocks
 * placed by time with their category edge, side-by-side overlaps and the
 * moving "now" line. Rendered as one bitmap because widgets cannot position
 * views by time; ScheduleWidgetProvider redraws it every minute while the
 * screen is on.
 */
class ScheduleWidget : GlanceAppWidget() {

    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        ScheduleWidgetProvider.scheduleTicks(context)
        provideContent {
            currentState(GlanceWidgets.REVISION)
            val size = LocalSize.current
            val bitmap = ScheduleRenderer.render(
                context,
                LevelUpWidgetData.load(context),
                size.width.value,
                size.height.value,
                Calendar.getInstance(),
            )
            Image(
                provider = ImageProvider(bitmap),
                contentDescription = context.getString(R.string.schedule_widget_label),
                contentScale = ContentScale.FillBounds,
                modifier = GlanceModifier
                    .fillMaxSize()
                    .clickable(actionStartActivity<MainActivity>()),
            )
        }
    }
}

internal object ScheduleRenderer {
    private const val BACKGROUND = 0xFF141414.toInt()
    private const val ROW = 0xFF232326.toInt()
    private const val TEXT = 0xFFECECEC.toInt()
    private const val MUTED = 0xFF9CA3AF.toInt()
    private const val LINE = 0x1FFFFFFF
    private const val ACCENT = 0xFF7C3AED.toInt()

    /** Height of one hour, matching the app's default zoom feel. */
    private const val HOUR_DP = 52f

    private class Block(
        val title: String,
        val time: String,
        val start: Int,
        val end: Int,
        val done: Boolean,
        val skipped: Boolean,
        val challenge: Boolean,
        val category: String,
    ) {
        var lane = 0
        var lanes = 1
    }

    private fun accent(block: Block): Int = when {
        block.challenge -> ACCENT
        block.category == "Study" -> 0xFF3B82F6.toInt()
        block.category == "Fitness" -> 0xFF22C55E.toInt()
        block.category == "Work" -> 0xFFF59E0B.toInt()
        else -> MUTED
    }

    private fun withAlpha(color: Int, alpha: Int) = (color and 0x00FFFFFF) or (alpha shl 24)

    private fun font(context: Context, arabic: Boolean, bold: Boolean): Typeface = try {
        val file = if (arabic) {
            if (bold) "fonts/Cairo/Cairo-Bold.ttf" else "fonts/Cairo/Cairo-Regular.ttf"
        } else {
            if (bold) "fonts/GoogleSansRounded-Bold.ttf" else "fonts/GoogleSansRounded-Medium.ttf"
        }
        Typeface.createFromAsset(context.assets, "flutter_assets/$file")
    } catch (e: Exception) {
        if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
    }

    private fun blocks(day: JSONObject): List<Block> {
        val items = day.optJSONArray("items") ?: return emptyList()
        val list = List(items.length()) { i ->
            val item = items.optJSONObject(i) ?: JSONObject()
            Block(
                title = item.optString("title"),
                time = item.optString("time"),
                start = item.optInt("start", 0),
                end = item.optInt("end", 0),
                done = item.optBoolean("done"),
                skipped = item.optBoolean("skipped"),
                challenge = item.optBoolean("challenge"),
                category = item.optString("category"),
            )
        }.filter { it.end > it.start }.sortedWith(compareBy({ it.start }, { -it.end }))
        // Same lane rule as the app: overlapping blocks share the width.
        var group = mutableListOf<Block>()
        var groupEnd = Int.MIN_VALUE
        fun finish() {
            val ends = mutableListOf<Int>()
            for (b in group) {
                var lane = ends.indexOfFirst { it <= b.start }
                if (lane < 0) {
                    lane = ends.size
                    ends.add(b.end)
                } else {
                    ends[lane] = b.end
                }
                b.lane = lane
            }
            for (b in group) b.lanes = ends.size
            group = mutableListOf()
        }
        for (b in list) {
            if (b.start >= groupEnd && group.isNotEmpty()) finish()
            group.add(b)
            groupEnd = max(groupEnd, b.end)
        }
        if (group.isNotEmpty()) finish()
        return list
    }

    fun render(context: Context, root: JSONObject?, widthDp: Float, heightDp: Float, now: Calendar): Bitmap {
        // Capped density keeps each minute's bitmap well inside widget limits.
        val density = min(context.resources.displayMetrics.density, 2.5f)
        fun dp(v: Float) = v * density
        val w = (widthDp * density).roundToInt().coerceIn(1, 1800)
        val h = (heightDp * density).roundToInt().coerceIn(1, 2400)
        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val rtl = root?.optBoolean("rtl") == true
        val regular = font(context, rtl, bold = false)
        val bold = font(context, rtl, bold = true)
        val fill = Paint(Paint.ANTI_ALIAS_FLAG)
        val text = TextPaint(Paint.ANTI_ALIAS_FLAG)
        fun mirror(x: Float) = if (rtl) w - x else x

        fun drawText(value: String, x: Float, y: Float, size: Float, color: Int, face: Typeface, alignEnd: Boolean = false, maxWidth: Float? = null, strike: Boolean = false) {
            text.typeface = face
            text.textSize = dp(size)
            text.color = color
            text.isStrikeThruText = strike
            val toEnd = alignEnd != rtl
            text.textAlign = if (toEnd) Paint.Align.RIGHT else Paint.Align.LEFT
            val shown = if (maxWidth != null && maxWidth > 0) {
                TextUtils.ellipsize(value, text, maxWidth, TextUtils.TruncateAt.END).toString()
            } else {
                value
            }
            canvas.drawText(shown, mirror(x), y, text)
        }

        fill.color = BACKGROUND
        canvas.drawRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), dp(22f), dp(22f), fill)

        val pad = dp(14f)
        val day = LevelUpWidgetData.today(root, now)
        // Header: date and app name.
        drawText(
            day?.optString("title").orEmpty().ifEmpty { "Level Up" },
            pad, pad + dp(14f), 15f, TEXT, bold,
            maxWidth = w - pad * 2 - dp(70f),
        )
        drawText("Level Up", w - pad, pad + dp(13f), 11f, ACCENT, regular, alignEnd = true)

        val top = pad + dp(30f)
        val bottom = h - pad
        if (day == null) {
            drawText(context.getString(R.string.schedule_widget_open), pad, top + dp(16f), 13f, MUTED, regular, maxWidth = w - pad * 2)
            return bitmap
        }

        val nowMinute = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val perMinute = dp(HOUR_DP) / 60f
        val visible = ((bottom - top) / perMinute).toInt()
        // Like the app, the view sits just before the current time.
        val windowStart = (((nowMinute - 45) / 15) * 15).coerceIn(0, max(0, 1440 - visible))
        fun y(minute: Int) = top + (minute - windowStart) * perMinute

        val gutter = dp(46f)
        val left = pad + gutter
        val right = w - pad
        canvas.save()
        canvas.clipRect(0f, top - dp(8f), w.toFloat(), bottom)

        // Hour grid and labels.
        fill.color = LINE
        var hour = ((windowStart + 59) / 60) * 60
        while (hour <= windowStart + visible && hour <= 1440) {
            val lineY = y(hour)
            canvas.drawRect(RectF(mirror(left - dp(6f)).let { min(it, mirror(right)) }, lineY, max(mirror(left - dp(6f)), mirror(right)), lineY + dp(.75f)), fill)
            val label = String.format(Locale.US, "%02d:00", (hour / 60) % 24)
            drawText(LevelUpWidgetData.digits(label, rtl), pad + gutter - dp(10f), lineY + dp(4f), 10f, MUTED, regular, alignEnd = true)
            hour += 60
        }

        val list = blocks(day)
        if (list.isEmpty()) {
            drawText(root?.optString("empty").orEmpty(), left + dp(6f), top + dp(26f), 13f, MUTED, regular, maxWidth = right - left)
        }
        val width = right - left
        for (b in list) {
            val y1 = y(max(b.start, 0))
            var y2 = y(min(b.end, 1440)) - dp(2f)
            if (y2 < top - dp(8f) || y1 > bottom) continue
            y2 = max(y2, y1 + dp(22f))
            val laneWidth = width / b.lanes
            val x1 = left + b.lane * laneWidth
            val x2 = x1 + laneWidth - dp(4f)
            val box = RectF(min(mirror(x1), mirror(x2)), y1, max(mirror(x1), mirror(x2)), y2)
            val faded = b.done || b.skipped || nowMinute >= b.end
            fill.color = if (b.challenge) withAlpha(ACCENT, 0x38) else ROW
            canvas.drawRoundRect(box, dp(9f), dp(9f), fill)
            // The block in progress fills up to now.
            if (nowMinute in b.start until b.end) {
                fill.color = withAlpha(ACCENT, 0x2E)
                canvas.save()
                canvas.clipRect(box.left, y1, box.right, y(nowMinute))
                canvas.drawRoundRect(box, dp(9f), dp(9f), fill)
                canvas.restore()
            }
            // Category edge on the leading side.
            fill.color = withAlpha(accent(b), if (faded) 0x66 else 0xFF)
            val edgeX = mirror(x1)
            canvas.drawRoundRect(
                RectF(min(edgeX, mirror(x1 + dp(3f))), y1, max(edgeX, mirror(x1 + dp(3f))), y2),
                dp(2f), dp(2f), fill,
            )
            val textWidth = laneWidth - dp(18f)
            val height = y2 - y1
            if (height >= dp(18f)) {
                drawText(
                    b.title, x1 + dp(10f), y1 + min(dp(16f), height - dp(5f)),
                    12.5f, if (faded) MUTED else TEXT, bold,
                    maxWidth = textWidth, strike = b.done,
                )
            }
            if (height >= dp(38f)) {
                drawText(b.time, x1 + dp(10f), y1 + dp(31f), 10f, MUTED, regular, maxWidth = textWidth)
            }
        }

        // The moving "now" line with the current time in the gutter.
        if (nowMinute in windowStart..(windowStart + visible)) {
            val lineY = y(nowMinute)
            fill.color = ACCENT
            canvas.drawRect(
                RectF(min(mirror(left - dp(6f)), mirror(right)), lineY - dp(1f), max(mirror(left - dp(6f)), mirror(right)), lineY + dp(1f)),
                fill,
            )
            canvas.drawCircle(mirror(left - dp(6f)), lineY, dp(3.5f), fill)
            val clock = String.format(Locale.US, "%02d:%02d", nowMinute / 60, nowMinute % 60)
            drawText(LevelUpWidgetData.digits(clock, rtl), pad + gutter - dp(10f), lineY + dp(4f), 10f, ACCENT, bold, alignEnd = true)
        }
        canvas.restore()
        return bitmap
    }
}
