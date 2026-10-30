// Level Up — Based on Streak by InlitX. GPL-3.0-only.
package com.streak.app

import android.content.Context
import android.util.AtomicFile
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.Job
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

/** Shares one scheduling lease across foreground engines and the periodic worker. */
internal object PlannerReminderBridge {
    const val CHANNEL = "streak/planner_refresh"
    val gate = PlannerRefreshGate()

    fun attach(context: Context, messenger: BinaryMessenger): Foreground =
        Foreground(context.applicationContext, MethodChannel(messenger, CHANNEL))

    fun read(context: Context): PlannerProjection? {
        val file = projectionFile(context)
        if (!file.baseFile.exists() && !File("${file.baseFile.path}.bak").exists()) return null
        return file.openRead().bufferedReader(Charsets.UTF_8).use { PlannerProjection.parse(it.readText()) }
    }

    fun write(context: Context, projection: PlannerProjection) {
        val file = projectionFile(context)
        val stream = file.startWrite()
        try {
            stream.write(projection.encode().toByteArray(Charsets.UTF_8))
            file.finishWrite(stream)
        } catch (error: Exception) {
            file.failWrite(stream)
            throw error
        }
    }

    private fun projectionFile(context: Context): AtomicFile =
        AtomicFile(File(context.filesDir, "levelup_reminder_projection.json"))

    class Foreground internal constructor(
        private val context: Context,
        private val channel: MethodChannel,
    ) {
        private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        private var lease: String? = null
        private var detached = false

        init {
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> scope.launch {
                        var token: String? = null
                        try {
                            check(lease == null) { "This engine already owns a planner refresh lease." }
                            val owner = UUID.randomUUID().toString()
                            token = owner
                            withTimeout(ACQUIRE_TIMEOUT_MS) { gate.acquire(owner) }
                            if (detached) {
                                gate.release(owner)
                                return@launch
                            }
                            lease = owner
                            // Corrupt authoritative data must fail visibly. AtomicFile
                            // recovers an interrupted write from its own backup.
                            val projection = withContext(Dispatchers.IO) { read(context)?.asMap() }
                            result.success(mapOf("lease" to owner, "projection" to projection))
                        } catch (error: Exception) {
                            token?.let { gate.release(it) }
                            if (lease == token) lease = null
                            if (error is CancellationException && error !is TimeoutCancellationException) throw error
                            result.error("planner_refresh_acquire", error.message, null)
                        }
                    }
                    "publish" -> scope.launch {
                        try {
                            requireLease(call.argument<String>("lease"))
                            val raw = call.argument<Map<*, *>>("projection")
                                ?: throw IllegalArgumentException("Missing planner projection.")
                            val projection = PlannerProjection.fromMap(raw)
                            withContext(Dispatchers.IO) { write(context, projection) }
                            result.success(true)
                        } catch (error: Exception) {
                            if (error is CancellationException) throw error
                            result.error("planner_refresh_publish", error.message, null)
                        }
                    }
                    "release" -> {
                        try {
                            val token = requireLease(call.argument<String>("lease"))
                            lease = null
                            result.success(gate.release(token))
                        } catch (error: Exception) {
                            result.error("planner_refresh_release", error.message, null)
                        }
                    }
                    "clear" -> scope.launch {
                        try {
                            requireLease(call.argument<String>("lease"))
                            withContext(Dispatchers.IO) { projectionFile(context).delete() }
                            PlannerReminderWorker.cancel(context)
                            result.success(true)
                        } catch (error: Exception) {
                            if (error is CancellationException) throw error
                            result.error("planner_refresh_clear", error.message, null)
                        }
                    }
                    "configure" -> {
                        try {
                            if (call.argument<Boolean>("enabled") != false) {
                                PlannerReminderWorker.configure(context)
                                call.argument<Number>("deadlineMillis")?.toLong()?.let {
                                    PlannerReminderWorker.scheduleDeadline(context, it)
                                }
                            } else {
                                PlannerReminderWorker.cancel(context)
                            }
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("planner_refresh_configure", error.message, null)
                        }
                    }
                    "refresh" -> {
                        try {
                            PlannerReminderWorker.enqueue(context)
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("planner_refresh_enqueue", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }

        private fun requireLease(token: String?): String = gate.requireLease(token, lease)

        fun detach() {
            detached = true
            channel.setMethodCallHandler(null)
            val pending = scope.coroutineContext[Job]
            scope.cancel()
            val token = lease
            lease = null
            // A blocking AtomicFile write may still be finishing on IO. Do not
            // let a worker acquire the gate before that write has actually ended.
            CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate).launch {
                pending?.join()
                if (token != null) gate.release(token)
            }
        }
    }

    private const val ACQUIRE_TIMEOUT_MS = 75_000L
}
