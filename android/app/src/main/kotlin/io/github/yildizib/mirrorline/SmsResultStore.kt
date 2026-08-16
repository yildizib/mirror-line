package io.github.yildizib.mirrorline

import android.content.Context
import android.util.Base64

data class SmsResult(val operationId: String, val kind: String, val success: Boolean)

internal class SmsResultParts(private val expectedCount: Int) {
    private val results = mutableMapOf<Int, Boolean>()

    fun record(partIndex: Int, success: Boolean) {
        if (partIndex in 0 until expectedCount) results.putIfAbsent(partIndex, success)
    }

    fun finalSuccess(): Boolean? =
        if (results.size == expectedCount) results.values.all { it } else null
}

/** Persists each SMS callback until Dart confirms its domain update committed. */
class SmsResultStore(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(
        "mirrorline_sms_results",
        Context.MODE_PRIVATE,
    )

    @Synchronized
    fun prepare(operationId: String, kind: String, partCount: Int) {
        val token = token(operationId)
        val key = key(token, kind)
        val records = preferences.getStringSet(RECORDS, emptySet())!!.toMutableSet()
        records.add(key)
        preferences.edit()
            .putStringSet(RECORDS, records)
            .putInt("$META_PREFIX$key", partCount)
            .commit()
    }

    /** Returns a final result only after every distinct part has reported. */
    @Synchronized
    fun record(
        operationId: String,
        kind: String,
        partIndex: Int,
        partCount: Int,
        success: Boolean,
    ): SmsResult? {
        prepare(operationId, kind, partCount)
        val key = key(token(operationId), kind)
        val resultKey = "$RESULT_PREFIX$key.$partIndex"
        if (!preferences.contains(resultKey)) {
            // commit is intentional: routing Dart must never precede persistence.
            preferences.edit().putBoolean(resultKey, success).commit()
        }
        return completed(operationId, kind, key)
    }

    @Synchronized
    fun recordFailure(operationId: String, partCount: Int): SmsResult? {
        var result: SmsResult? = null
        for (partIndex in 0 until partCount) {
            result = record(operationId, SENT, partIndex, partCount, false) ?: result
        }
        discard(operationId, DELIVERED)
        return result
    }

    @Synchronized
    fun pending(): List<SmsResult> = preferences.getStringSet(RECORDS, emptySet())!!
        .mapNotNull { key ->
            val separator = key.lastIndexOf('.')
            if (separator <= 0) return@mapNotNull null
            val operationId = decode(key.substring(0, separator)) ?: return@mapNotNull null
            completed(operationId, key.substring(separator + 1), key)
        }

    @Synchronized
    fun acknowledge(operationId: String, kind: String) {
        val key = key(token(operationId), kind)
        val records = preferences.getStringSet(RECORDS, emptySet())!!.toMutableSet()
        records.remove(key)
        val partCount = preferences.getInt("$META_PREFIX$key", 0)
        val editor = preferences.edit().putStringSet(RECORDS, records).remove("$META_PREFIX$key")
        for (partIndex in 0 until partCount) {
            editor.remove("$RESULT_PREFIX$key.$partIndex")
        }
        editor.commit()
    }

    @Synchronized
    private fun discard(operationId: String, kind: String) {
        acknowledge(operationId, kind)
    }

    private fun completed(operationId: String, kind: String, key: String): SmsResult? {
        val partCount = preferences.getInt("$META_PREFIX$key", 0)
        if (partCount < 1) return null
        val parts = SmsResultParts(partCount)
        for (partIndex in 0 until partCount) {
            val resultKey = "$RESULT_PREFIX$key.$partIndex"
            if (!preferences.contains(resultKey)) return null
            parts.record(partIndex, preferences.getBoolean(resultKey, false))
        }
        return SmsResult(operationId, kind, parts.finalSuccess() ?: return null)
    }

    private fun token(operationId: String): String = Base64.encodeToString(
        operationId.toByteArray(Charsets.UTF_8),
        Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP,
    )

    private fun decode(token: String): String? = try {
        String(Base64.decode(token, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP), Charsets.UTF_8)
    } catch (_: IllegalArgumentException) {
        null
    }

    private fun key(token: String, kind: String) = "$token.$kind"

    companion object {
        const val SENT = "sent"
        const val DELIVERED = "delivered"
        private const val RECORDS = "records"
        private const val META_PREFIX = "meta."
        private const val RESULT_PREFIX = "result."
    }
}
