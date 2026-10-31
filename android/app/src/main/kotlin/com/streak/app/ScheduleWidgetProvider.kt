// Level Up — Based on Streak by InlitX. GPL-3.0-only.
package com.streak.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.glance.appwidget.GlanceAppWidgetReceiver

/** Receiver for the Level Up schedule widget (see ScheduleWidget). */
class ScheduleWidgetProvider : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = ScheduleWidget()

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        // The midnight alarm repaints the widget so it moves to the next day
        // from the week the app already published.
        WidgetRefreshReceiver.schedule(context)
        scheduleTicks(context)
        GlanceWidgets.refreshSoon(context, glanceAppWidget, appWidgetIds, goAsync())
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TICK) {
            val ids = AppWidgetManager.getInstance(context)
                .getAppWidgetIds(ComponentName(context, ScheduleWidgetProvider::class.java))
            if (ids.isEmpty()) {
                cancelTicks(context)
                return
            }
            GlanceWidgets.refreshSoon(context, glanceAppWidget, ids, goAsync())
            return
        }
        super.onReceive(context, intent)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        cancelTicks(context)
    }

    companion object {
        private const val ACTION_TICK = "com.streak.app.SCHEDULE_WIDGET_TICK"
        private const val REQUEST_CODE = 90311
        private const val MINUTE_MS = 60_000L

        private fun tick(context: Context): PendingIntent = PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            Intent(context, ScheduleWidgetProvider::class.java).setAction(ACTION_TICK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        /**
         * Moves the "now" line about once a minute. RTC (not RTC_WAKEUP) never
         * wakes the phone: while the screen is off nothing runs, and the next
         * tick arrives as soon as it is awake again.
         */
        fun scheduleTicks(context: Context) {
            try {
                val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val nextMinute = (System.currentTimeMillis() / MINUTE_MS + 1) * MINUTE_MS
                alarms.setRepeating(AlarmManager.RTC, nextMinute, MINUTE_MS, tick(context))
            } catch (e: Exception) {
                // Without ticks the widget still refreshes on changes and periodically.
            }
        }

        fun cancelTicks(context: Context) {
            try {
                val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                alarms.cancel(tick(context))
            } catch (e: Exception) {
                return
            }
        }
    }
}
