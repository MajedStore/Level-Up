// Level Up — Based on Streak by InlitX. GPL-3.0-only.
package com.streak.app

import android.appwidget.AppWidgetManager
import android.content.Context
import androidx.glance.appwidget.GlanceAppWidgetReceiver

/** Receiver for the Level Up challenges widget (see ChallengesWidget). */
class ChallengesWidgetProvider : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = ChallengesWidget()

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        // Repaint at midnight so the widget moves to the next published day.
        WidgetRefreshReceiver.schedule(context)
        GlanceWidgets.refreshSoon(context, glanceAppWidget, appWidgetIds, goAsync())
    }
}
