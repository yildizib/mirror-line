package io.github.yildizib.mirrorline

import android.content.Context

class MirroringLifecycleStore(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE,
    )

    fun read() = MirroringLifecycleState(
        initialized = preferences.getBoolean(KEY_INITIALIZED, false),
        enabled = preferences.getBoolean(KEY_ENABLED, false),
        role = preferences.getString(KEY_ROLE, "") ?: "",
        paired = preferences.getBoolean(KEY_PAIRED, false),
    )

    fun sync(enabled: Boolean, role: String, paired: Boolean): MirroringLifecycleState {
        preferences.edit()
            .putBoolean(KEY_INITIALIZED, true)
            .putBoolean(KEY_ENABLED, enabled)
            .putString(KEY_ROLE, role)
            .putBoolean(KEY_PAIRED, paired)
            .apply()
        return read()
    }

    companion object {
        private const val PREFERENCES_NAME = "mirroring_lifecycle"
        private const val KEY_INITIALIZED = "initialized"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_ROLE = "role"
        private const val KEY_PAIRED = "paired"
    }
}
