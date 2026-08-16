package io.github.yildizib.mirrorline

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Manifest receiver so SMS callbacks survive a killed Flutter process. */
class SmsResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val operationId = intent.getStringExtra(EXTRA_OPERATION_ID) ?: return
        val kind = intent.getStringExtra(EXTRA_KIND) ?: return
        val partIndex = intent.getIntExtra(EXTRA_PART_INDEX, -1)
        val partCount = intent.getIntExtra(EXTRA_PART_COUNT, 0)
        if (partIndex < 0 || partCount < 1 || partIndex >= partCount) return

        val result = SmsResultStore(context).record(
            operationId,
            kind,
            partIndex,
            partCount,
            resultCode == Activity.RESULT_OK,
        ) ?: return
        MirrorLineChannel.routeSmsResult(result)
    }

    companion object {
        const val ACTION = "io.github.yildizib.mirrorline.SMS_RESULT"
        const val EXTRA_OPERATION_ID = "operationId"
        const val EXTRA_KIND = "kind"
        const val EXTRA_PART_INDEX = "partIndex"
        const val EXTRA_PART_COUNT = "partCount"
    }
}
