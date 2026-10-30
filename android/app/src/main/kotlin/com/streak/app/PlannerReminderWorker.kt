// Level Up — Based on Streak by InlitX. GPL-3.0-only.
package com.streak.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.launch

/** Reconciles canonical deadlines and reminders without opening Hive. */
class PlannerReminderWorker(context: Context, params: WorkerParameters) :
    CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val owner = Any()
        PlannerReminderBridge.gate.acquire(owner)
        var engine: FlutterEngine? = null
        try {
            return withTimeoutOrNull(RUN_TIMEOUT_MS) {
                val projection = withContext(Dispatchers.IO) { PlannerReminderBridge.read(applicationContext) }
                    ?: return@withTimeoutOrNull Result.success()
                val done = CompletableDeferred<Completion>()
                val workerScope = CoroutineScope(coroutineContext)
                withContext(Dispatchers.Main) {
                    val loader = FlutterInjector.instance().flutterLoader()
                    loader.startInitialization(applicationContext)
                    loader.ensureInitializationComplete(applicationContext, null)
                    val created = FlutterEngine(applicationContext)
                    // Assign inside this context so timeout cancellation cannot
                    // discard the engine before finally can destroy it.
                    engine = created
                    // Sound resolution uses the same bundled/system tone bridge as the UI.
                    SoundBridge.attach(
                        applicationContext,
                        MethodChannel(created.dartExecutor.binaryMessenger, SoundBridge.CHANNEL),
                    )
                    MethodChannel(created.dartExecutor.binaryMessenger, PlannerReminderBridge.CHANNEL)
                        .setMethodCallHandler { call, result ->
                            when (call.method) {
                                "readBackground" -> result.success(projection.asMap())
                                "checkpointBackground" -> workerScope.launch {
                                    try {
                                        val state = call.argument<Map<*, *>>("plannerState")
                                            ?: throw IllegalArgumentException("Missing planner state.")
                                        val values = call.argument<Map<*, *>>("values")
                                            ?: throw IllegalArgumentException("Missing reminder bookkeeping.")
                                        withContext(Dispatchers.IO) {
                                            PlannerReminderBridge.write(applicationContext,
                                                projection.withPlannerState(state, values, System.currentTimeMillis()))
                                        }
                                        result.success(true)
                                    } catch (error: Exception) {
                                        if (error is CancellationException) throw error
                                        result.error("planner_checkpoint", error.message, null)
                                    }
                                }
                                "completeBackground" -> {
                                    val success = call.argument<Boolean>("success") == true
                                    val values = call.argument<Map<*, *>>("values")
                                    if (success && values == null) {
                                        result.error("planner_worker_values", "Missing reminder bookkeeping.", null)
                                    } else {
                                        done.complete(Completion(success, values, call.argument<Map<*, *>>("plannerState"), call.argument<Number>("nextDeadlineMillis")?.toLong(), call.argument<String>("error")))
                                        result.success(true)
                                    }
                                }
                                else -> result.notImplemented()
                            }
                        }
                    created.dartExecutor.executeDartEntrypoint(
                        DartExecutor.DartEntrypoint(loader.findAppBundlePath(), ENTRYPOINT),
                    )
                }
                val completed = done.await()
                // Accounting is independent of notification permission/platform
                // failures. Persist reconciled deadlines before retrying alarms.
                if (completed.values != null) withContext(Dispatchers.IO) {
                    PlannerReminderBridge.write(
                        applicationContext,
                        if (completed.plannerState != null)
                            projection.withPlannerState(completed.plannerState, completed.values!!, System.currentTimeMillis())
                        else projection.withValues(completed.values!!, System.currentTimeMillis()),
                    )
                }
                completed.nextDeadline?.let { scheduleDeadline(applicationContext, it) }
                if (!completed.success) {
                    Log.w(TAG, "Planner reminders need a retry: ${completed.error.orEmpty()}")
                    return@withTimeoutOrNull Result.retry()
                }
                Result.success()
            } ?: Result.retry()
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            Log.e(TAG, "Planner reconciliation failed; retrying the atomic transaction", error)
            return Result.retry()
        } finally {
            // Destroy the engine while still holding the gate: late plugin calls
            // must not race a foreground reschedule that has acquired a new lease.
            val target = engine
            try {
                if (target != null) withContext(NonCancellable + Dispatchers.Main) { target.destroy() }
            } finally {
                PlannerReminderBridge.gate.release(owner)
            }
        }
    }

    private data class Completion(val success: Boolean, val values: Map<*, *>?, val plannerState: Map<*, *>?, val nextDeadline: Long?, val error: String?)

    companion object {
        private const val TAG = "LevelUpPlannerRefresh"
        private const val ENTRYPOINT = "plannerReminderEntrypoint"
        private const val RUN_TIMEOUT_MS = 60_000L
        private const val PERIODIC_NAME = "levelup_planner_periodic"
        private const val REFRESH_NAME = "levelup_planner_refresh"
        private const val DEADLINE_NAME = "levelup_planner_deadline"

        fun scheduleDeadline(context: Context, deadlineMillis: Long) {
            WorkManager.getInstance(context).enqueueUniqueWork(
                "${DEADLINE_NAME}_$deadlineMillis",
                ExistingWorkPolicy.KEEP,
                OneTimeWorkRequestBuilder<PlannerReminderWorker>()
                    .addTag(DEADLINE_NAME)
                    .setInitialDelay((deadlineMillis - System.currentTimeMillis()).coerceAtLeast(0), TimeUnit.MILLISECONDS)
                    .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.MINUTES)
                    .build(),
            )
        }

        fun configure(context: Context) {
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                PERIODIC_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                PeriodicWorkRequestBuilder<PlannerReminderWorker>(12, TimeUnit.HOURS)
                    .setInitialDelay(12, TimeUnit.HOURS)
                    .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.MINUTES)
                    .build(),
            )
        }

        fun enqueue(context: Context) {
            WorkManager.getInstance(context).enqueueUniqueWork(
                REFRESH_NAME,
                ExistingWorkPolicy.KEEP,
                OneTimeWorkRequestBuilder<PlannerReminderWorker>()
                    .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.MINUTES)
                    .build(),
            )
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(PERIODIC_NAME)
            WorkManager.getInstance(context).cancelUniqueWork(REFRESH_NAME)
            WorkManager.getInstance(context).cancelAllWorkByTag(DEADLINE_NAME)
        }
    }
}

class PlannerReminderRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in ACTIONS) return
        try {
            PlannerReminderWorker.enqueue(context.applicationContext)
        } catch (error: Exception) {
            Log.w("LevelUpPlannerRefresh", "Android deferred reminder refresh", error)
        }
    }

    companion object {
        private val ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
        )
    }
}
