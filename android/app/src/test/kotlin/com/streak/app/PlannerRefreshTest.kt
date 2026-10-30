package com.streak.app

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class PlannerRefreshTest {
    @Test fun aRoundTrippedLeaseUsesTheStoredOwnerIdentity() = runBlocking {
        val gate = PlannerRefreshGate()
        val owner = String(charArrayOf('l', 'e', 'a', 's', 'e'))
        val roundTripped = String(owner.toCharArray())
        assertEquals(owner, roundTripped)
        assertNotSame(owner, roundTripped)
        gate.acquire(owner)
        assertFalse(gate.owns(roundTripped))
        val resolved = gate.requireLease(roundTripped, owner)
        assertSame(owner, resolved)
        assertTrue(gate.release(resolved))
    }

    @Test fun wrongOwnerCannotReleaseAnActiveWorker() = runBlocking {
        val gate = PlannerRefreshGate()
        val worker = Any()
        gate.acquire(worker)
        assertFalse(gate.release(Any()))
        assertTrue(gate.owns(worker))
        assertTrue(gate.release(worker))
        assertFalse(gate.release(worker))
    }

    @Test fun foregroundWaitsUntilWorkerHasFinishedItsWholeTransaction() = runBlocking {
        val gate = PlannerRefreshGate()
        val worker = Any()
        val foreground = Any()
        val entered = CompletableDeferred<Unit>()
        gate.acquire(worker)
        val waiting = async(start = CoroutineStart.UNDISPATCHED) {
            gate.acquire(foreground)
            entered.complete(Unit)
            gate.release(foreground)
        }
        assertFalse(entered.isCompleted)
        gate.release(worker)
        waiting.await()
        assertTrue(entered.isCompleted)
    }

    @Test fun cancellingAWaitingEngineCannotReleaseTheCurrentOwner() = runBlocking {
        val gate = PlannerRefreshGate()
        val worker = Any()
        val foreground = Any()
        gate.acquire(worker)
        val waiting = launch(start = CoroutineStart.UNDISPATCHED) { gate.acquire(foreground) }
        waiting.cancelAndJoin()
        assertTrue(gate.owns(worker))
        assertFalse(gate.owns(foreground))
        assertTrue(gate.release(worker))
    }

    @Test fun workerUpdatesCannotReplaceCanonicalTasksOrXp() {
        val projection = PlannerProjection.fromMap(mapOf(
            "schemaVersion" to 1,
            "plannerState" to mapOf("ledger" to listOf(mapOf("change" to 10)), "items" to listOf("keep")),
            "values" to mapOf("plannerNotificationIds" to mapOf("a" to 12)),
            "settings" to mapOf("locale" to "en"),
        ))
        val refreshed = projection.withValues(mapOf("plannerNotificationIds" to mapOf("b" to 13)), 123)
        assertEquals(projection.asMap()["plannerState"], refreshed.asMap()["plannerState"])
        assertEquals(projection.asMap()["settings"], refreshed.asMap()["settings"])
        assertNotEquals(projection.asMap()["values"], refreshed.asMap()["values"])
        assertEquals(123, refreshed.asMap()["lastRefreshAt"])
    }

    @Test fun serializationProducesDetachedNestedMaps() {
        val mutableItems = mutableListOf("original")
        val projection = PlannerProjection.fromMap(mapOf(
            "schemaVersion" to 1,
            "plannerState" to mapOf("items" to mutableItems),
            "values" to emptyMap<String, Any>(),
        ))
        mutableItems.add("must not leak")
        val state = projection.asMap()["plannerState"] as Map<*, *>
        assertEquals(listOf("original"), state["items"])
        assertEquals(projection.asMap(), PlannerProjection.parse(projection.encode()).asMap())
    }

    @Test fun unknownProjectionSchemaIsRejected() {
        try {
            PlannerProjection.parse("{\"schemaVersion\":99,\"plannerState\":{},\"values\":{}}")
            fail("Unsupported snapshot must not be accepted")
        } catch (_: IllegalArgumentException) {
        }
    }

    @Test fun onlyMigratedCanonicalDocumentsAcceptHeadlessLedgerTransactions() {
        val raw = mapOf(
            "schemaVersion" to 1,
            "plannerState" to mapOf("ledger" to emptyList<Any>()),
            "values" to emptyMap<String, Any>(),
        )
        val legacy = PlannerProjection.fromMap(raw)
        try {
            legacy.withPlannerState(mapOf("ledger" to listOf("penalty")), emptyMap<String, Any>(), 1)
            fail("A disposable legacy mirror cannot become authoritative headlessly")
        } catch (_: IllegalArgumentException) {}
        val canonical = PlannerProjection.fromMap(raw + ("canonicalPlanner" to true))
        val updated = canonical.withPlannerState(mapOf("ledger" to listOf("penalty")), emptyMap<String, Any>(), 2)
        assertEquals(listOf("penalty"), (updated.asMap()["plannerState"] as Map<*, *>)["ledger"])
        assertEquals(true, updated.asMap()["canonicalPlanner"])
        assertEquals(2, updated.asMap()["lastRefreshAt"])
    }
}
