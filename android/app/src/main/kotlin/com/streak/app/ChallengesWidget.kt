// Level Up — Based on Streak by InlitX. GPL-3.0-only.
package com.streak.app

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextDecoration
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import java.util.Calendar
import org.json.JSONObject

private val CH_BACKGROUND = Color(0xFF141414)
private val CH_ROW = Color(0xFF232326)
private val CH_TEXT = Color(0xFFECECEC)
private val CH_MUTED = Color(0xFF9CA3AF)
private val CH_ACCENT = Color(0xFF7C3AED)
private val CH_DONE = Color(0xFF22C55E)

/**
 * Home-screen view of today's challenge package: progress bar, done/total and
 * its tasks, like the Challenges tab, plus tomorrow's selection status.
 */
class ChallengesWidget : GlanceAppWidget() {

    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            currentState(GlanceWidgets.REVISION)
            Body(context)
        }
    }

    @Composable
    private fun Body(context: Context) {
        val root = LevelUpWidgetData.load(context)
        val now = Calendar.getInstance()
        val day = LevelUpWidgetData.today(root, now)
        val rtl = root?.optBoolean("rtl") == true
        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(CH_BACKGROUND)
                .cornerRadius(22.dp)
                .padding(14.dp)
                .clickable(actionStartActivity<MainActivity>()),
        ) {
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = root?.optString("challengeTitle").orEmpty().ifEmpty { "Level Up" },
                    style = TextStyle(color = ColorProvider(CH_MUTED), fontSize = 12.sp, fontWeight = FontWeight.Medium),
                    maxLines = 1,
                    modifier = GlanceModifier.defaultWeight(),
                )
                Text(
                    text = "Level Up",
                    style = TextStyle(color = ColorProvider(CH_ACCENT), fontSize = 11.sp),
                )
            }
            Spacer(GlanceModifier.height(8.dp))
            if (root == null || day == null) {
                Note(context.getString(R.string.schedule_widget_open))
                return@Column
            }
            val packages = day.optJSONArray("challenges")
            val tomorrow = root.optString("tomorrowLabel")
                .takeIf { root.optString("tomorrowFor") == day.optString("key") }
            if (packages == null || packages.length() == 0) {
                Note(root.optString("noChallenge"))
                if (!tomorrow.isNullOrEmpty()) Footer(tomorrow)
                return@Column
            }
            // The first package leads; a second one is rare and still listed.
            val rows = mutableListOf<Pair<JSONObject, JSONObject?>>()
            for (p in 0 until packages.length()) {
                val pack = packages.optJSONObject(p) ?: continue
                rows.add(pack to null)
                val tasks = pack.optJSONArray("tasks")
                for (t in 0 until (tasks?.length() ?: 0)) {
                    tasks?.optJSONObject(t)?.let { rows.add(pack to it) }
                }
            }
            LazyColumn(modifier = GlanceModifier.defaultWeight().fillMaxWidth()) {
                items(rows) { (pack, task) ->
                    if (task == null) PackageHeader(pack, rtl) else TaskRow(task)
                }
            }
            if (!tomorrow.isNullOrEmpty()) Footer(tomorrow)
        }
    }

    @Composable
    private fun PackageHeader(pack: JSONObject, rtl: Boolean) {
        val done = pack.optInt("done")
        val total = pack.optInt("total").coerceAtLeast(1)
        Column(modifier = GlanceModifier.fillMaxWidth().padding(bottom = 8.dp)) {
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = pack.optString("name"),
                    style = TextStyle(color = ColorProvider(CH_TEXT), fontSize = 16.sp, fontWeight = FontWeight.Bold),
                    maxLines = 1,
                    modifier = GlanceModifier.defaultWeight(),
                )
                Text(
                    text = LevelUpWidgetData.digits("$done/${pack.optInt("total")}", rtl),
                    style = TextStyle(color = ColorProvider(CH_MUTED), fontSize = 12.sp),
                )
            }
            Spacer(GlanceModifier.height(6.dp))
            LinearProgressIndicator(
                progress = done.toFloat() / total,
                modifier = GlanceModifier.fillMaxWidth().height(6.dp),
                color = ColorProvider(CH_ACCENT),
                backgroundColor = ColorProvider(CH_ROW),
            )
        }
    }

    @Composable
    private fun TaskRow(task: JSONObject) {
        val done = task.optBoolean("done")
        val skipped = task.optBoolean("skipped")
        Row(
            modifier = GlanceModifier
                .fillMaxWidth()
                .padding(bottom = 6.dp)
                .background(CH_ROW)
                .cornerRadius(12.dp)
                .padding(horizontal = 10.dp, vertical = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = if (done) "✓" else if (skipped) "–" else "○",
                style = TextStyle(
                    color = ColorProvider(if (done) CH_DONE else if (skipped) CH_MUTED else CH_ACCENT),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                ),
            )
            Spacer(GlanceModifier.width(10.dp))
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(
                    text = task.optString("title"),
                    style = TextStyle(
                        color = ColorProvider(if (done || skipped) CH_MUTED else CH_TEXT),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                        textDecoration = if (done) TextDecoration.LineThrough else null,
                    ),
                    maxLines = 1,
                )
                val time = task.optString("time")
                if (time.isNotEmpty()) {
                    Text(
                        text = time,
                        style = TextStyle(color = ColorProvider(CH_MUTED), fontSize = 10.sp),
                        maxLines = 1,
                    )
                }
            }
        }
    }

    @Composable
    private fun Note(text: String) {
        Text(
            text = text,
            style = TextStyle(color = ColorProvider(CH_MUTED), fontSize = 13.sp),
            modifier = GlanceModifier.fillMaxWidth().padding(top = 4.dp, bottom = 8.dp),
        )
    }

    @Composable
    private fun Footer(text: String) {
        Text(
            text = text,
            style = TextStyle(color = ColorProvider(CH_ACCENT), fontSize = 12.sp, fontWeight = FontWeight.Medium),
            maxLines = 2,
            modifier = GlanceModifier.fillMaxWidth().padding(top = 4.dp),
        )
    }
}
