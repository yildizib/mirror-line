package io.github.yildizib.mirrorline

import android.content.Context
import android.provider.CallLog

/**
 * Reads the most recently written call-log entry. The live
 * ACTION_PHONE_STATE_CHANGED broadcast's EXTRA_INCOMING_NUMBER can come back
 * null for some calls (carrier delivery timing, OEM call screening), leaving
 * the caller shown as "unknown" even though Android's own call log -- backed
 * by the richer Telecom-level caller ID resolution the system Phone app
 * uses -- resolves it correctly moments later. Querying it after a call
 * ends lets that same resolution backfill our record.
 */
object CallLogResolver {
    data class Entry(val rowId: Long, val number: String, val name: String)
    data class BaselineResult(val successful: Boolean, val rowId: Long?)

    fun captureBaseline(context: Context): BaselineResult {
        return try {
            val cursor = context.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(CallLog.Calls._ID),
                null,
                null,
                "${CallLog.Calls._ID} DESC LIMIT 1",
            ) ?: return BaselineResult(false, null)
            cursor.use {
                BaselineResult(
                    true,
                    if (it.moveToFirst()) {
                        it.getLong(it.getColumnIndexOrThrow(CallLog.Calls._ID))
                    } else {
                        null
                    },
                )
            }
        } catch (_: Exception) {
            BaselineResult(false, null)
        }
    }

    /**
     * [sinceMs] bounds the query to entries written at or after that time --
     * both a correctness guard (never returns a stale, unrelated call) and,
     * combined with the caller's retry loop, a way to tell "not written yet"
     * (no matching row) apart from "written, but not useful" (redacted
     * number) without ever risking a wrong match.
     */
    fun matchingEntry(context: Context, window: CallWindow): Entry? {
        return try {
            val baseline = window.baseline.snapshot()
            if (!baseline.resolved) return null
            val allowedTypes = when (window.direction) {
                CallDirection.INCOMING -> intArrayOf(
                    CallLog.Calls.INCOMING_TYPE,
                    CallLog.Calls.MISSED_TYPE,
                )
                CallDirection.OUTGOING -> intArrayOf(CallLog.Calls.OUTGOING_TYPE)
            }
            val typePlaceholders = allowedTypes.joinToString(",") { "?" }
            context.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(
                    CallLog.Calls.NUMBER,
                    CallLog.Calls._ID,
                    CallLog.Calls.CACHED_NAME,
                    CallLog.Calls.DATE,
                    CallLog.Calls.TYPE,
                    CallLog.Calls.DURATION,
                ),
                buildString {
                    append("${CallLog.Calls.DATE} BETWEEN ? AND ? AND ")
                    append("${CallLog.Calls.TYPE} IN ($typePlaceholders)")
                    if (baseline.rowId != null) append(" AND ${CallLog.Calls._ID} > ?")
                },
                buildList {
                    add(CallLogMatcher.lowerBoundMs(window).toString())
                    add((window.endedAtMs + CallLogMatcher.END_TOLERANCE_MS).toString())
                    addAll(allowedTypes.map(Int::toString))
                    baseline.rowId?.let { add(it.toString()) }
                }.toTypedArray(),
                "${CallLog.Calls.DATE} DESC LIMIT $CANDIDATE_LIMIT"
            )?.use { cursor ->
                val rows = mutableListOf<Pair<CallLogCandidate, Entry>>()
                while (cursor.moveToNext()) {
                    val number = cursor.getString(
                        cursor.getColumnIndexOrThrow(CallLog.Calls.NUMBER),
                    )
                    if (number.isNullOrEmpty() || number.startsWith("-")) continue
                    val rowId = cursor.getLong(cursor.getColumnIndexOrThrow(CallLog.Calls._ID))
                    val name = cursor.getString(
                        cursor.getColumnIndexOrThrow(CallLog.Calls.CACHED_NAME),
                    ) ?: ""
                    val date = cursor.getLong(cursor.getColumnIndexOrThrow(CallLog.Calls.DATE))
                    val type = cursor.getInt(cursor.getColumnIndexOrThrow(CallLog.Calls.TYPE))
                    val durationIndex = cursor.getColumnIndexOrThrow(CallLog.Calls.DURATION)
                    val durationMs = if (cursor.isNull(durationIndex)) {
                        null
                    } else {
                        cursor.getLong(durationIndex) * 1_000L
                    }
                    rows += CallLogCandidate(rowId, date, type, durationMs) to
                        Entry(rowId, number, name)
                }
                val selected = CallLogMatcher.selectBest(rows.map { it.first }, window)
                    ?: return@use null
                rows.first { it.first.rowId == selected.rowId }.second
            }
        } catch (_: Exception) {
            null
        }
    }

    private const val CANDIDATE_LIMIT = 8
}
