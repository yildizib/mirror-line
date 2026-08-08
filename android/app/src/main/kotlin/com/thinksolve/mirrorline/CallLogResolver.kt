package com.thinksolve.mirrorline

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
    data class Entry(val number: String, val name: String)

    fun latestEntry(context: Context): Entry? {
        return try {
            context.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.CACHED_NAME),
                null, null,
                "${CallLog.Calls.DATE} DESC LIMIT 1"
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val number = cursor.getString(cursor.getColumnIndexOrThrow(CallLog.Calls.NUMBER))
                    val name = cursor.getString(cursor.getColumnIndexOrThrow(CallLog.Calls.CACHED_NAME)) ?: ""
                    // Android uses negative sentinel values (UNKNOWN_NUMBER,
                    // PRIVATE_NUMBER, PAYPHONE_NUMBER) in place of a real
                    // number -- not an improvement over what we already have.
                    if (number.isNullOrEmpty() || number.startsWith("-")) null else Entry(number, name)
                } else null
            }
        } catch (_: Exception) {
            null
        }
    }
}
