// Level Up — Based on Streak by InlitX. GPL-3.0-only.
package com.streak.app

import kotlinx.coroutines.sync.Mutex

/** The owner token prevents a detached Flutter engine from unlocking another run. */
internal class PlannerRefreshGate {
    private val mutex = Mutex()

    suspend fun acquire(owner: Any) = mutex.lock(owner)

    fun owns(owner: Any): Boolean = mutex.holdsLock(owner)

    /** Channel strings compare by value, but Mutex owners compare by identity. */
    fun requireLease(presentedToken: String?, storedOwner: String?): String {
        val owner = storedOwner
        require(owner != null && presentedToken == owner && owns(owner)) {
            "A current planner refresh lease is required."
        }
        return owner
    }

    fun release(owner: Any): Boolean {
        if (!mutex.holdsLock(owner)) return false
        mutex.unlock(owner)
        return true
    }
}
