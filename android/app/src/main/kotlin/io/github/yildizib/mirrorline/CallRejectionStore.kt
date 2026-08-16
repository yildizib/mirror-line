package io.github.yildizib.mirrorline

import android.content.Context
import android.util.Base64

/** Records accepted end-call requests so Dart can safely reconcile a lost reply. */
class CallRejectionStore(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(
        "mirrorline_call_rejections",
        Context.MODE_PRIVATE,
    )

    fun record(operationId: String) = synchronized(lock) {
        val rejections = preferences.getStringSet(REJECTIONS, emptySet())!!.toMutableSet()
        if (rejections.add(token(operationId))) {
            // The channel response must never precede this durable acceptance record.
            preferences.edit().putStringSet(REJECTIONS, rejections).commit()
        }
    }

    fun hasRejection(operationId: String): Boolean = synchronized(lock) {
        token(operationId) in preferences.getStringSet(REJECTIONS, emptySet())!!
    }

    private fun token(operationId: String): String = Base64.encodeToString(
        operationId.toByteArray(Charsets.UTF_8),
        Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP,
    )

    companion object {
        private const val REJECTIONS = "rejections"
        private val lock = Any()
    }
}
