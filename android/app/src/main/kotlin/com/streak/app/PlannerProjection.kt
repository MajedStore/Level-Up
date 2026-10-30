// Level Up — Based on Streak by InlitX. GPL-3.0-only.
package com.streak.app

import org.json.JSONArray
import org.json.JSONObject

/** Versioned AtomicFile document shared under the foreground/worker gate.
 * Old documents are notification mirrors; canonicalPlanner marks migrated data.
 */
internal class PlannerProjection private constructor(private val json: JSONObject) {
    fun encode(): String = json.toString()

    fun asMap(): Map<String, Any?> = objectMap(json)

    /** Only notification bookkeeping may be changed by the headless worker. */
    fun withValues(values: Map<*, *>, refreshedAt: Long): PlannerProjection {
        val copy = JSONObject(encode())
        copy.put("values", JSONObject(values))
        copy.put("lastRefreshAt", refreshedAt)
        return parse(copy.toString())
    }

    /** Canonical writes are permitted only after foreground migration. */
    fun withPlannerState(state: Map<*, *>, values: Map<*, *>, refreshedAt: Long): PlannerProjection {
        require(json.optBoolean("canonicalPlanner", false)) { "Planner store has not been migrated." }
        val copy = JSONObject(encode())
        copy.put("plannerState", JSONObject(state))
        copy.put("values", JSONObject(values))
        copy.put("lastRefreshAt", refreshedAt)
        return parse(copy.toString())
    }

    companion object {
        fun fromMap(value: Map<*, *>): PlannerProjection = parse(JSONObject(value).toString())

        fun parse(raw: String): PlannerProjection {
            val data = JSONObject(raw)
            require(data.optInt("schemaVersion", -1) == 1) {
                "Unsupported planner notification projection version."
            }
            require(data.opt("plannerState") is JSONObject) { "Missing planner snapshot." }
            require(data.opt("values") is JSONObject) { "Missing reminder bookkeeping." }
            require(!data.has("settings") || data.opt("settings") is JSONObject) {
                "Invalid planner settings snapshot."
            }
            return PlannerProjection(data)
        }

        private fun objectMap(value: JSONObject): Map<String, Any?> = buildMap {
            val keys = value.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                put(key, platformValue(value.get(key)))
            }
        }

        private fun platformValue(value: Any?): Any? = when (value) {
            null, JSONObject.NULL -> null
            is JSONObject -> objectMap(value)
            is JSONArray -> List(value.length()) { platformValue(value.get(it)) }
            else -> value
        }
    }
}
