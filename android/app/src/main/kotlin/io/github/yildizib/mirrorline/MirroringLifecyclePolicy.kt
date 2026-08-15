package io.github.yildizib.mirrorline

data class MirroringLifecycleState(
    val initialized: Boolean,
    val enabled: Boolean,
    val role: String,
    val paired: Boolean,
) {
    fun toMap(permissionsGranted: Boolean, eligible: Boolean) = mapOf(
        "initialized" to initialized,
        "enabled" to enabled,
        "role" to role,
        "paired" to paired,
        "permissionsGranted" to permissionsGranted,
        "eligible" to eligible,
        "networkMonitoringEligible" to MirroringLifecyclePolicy.shouldMonitorNetwork(this),
    )
}

object MirroringLifecyclePolicy {
    const val SOURCE_ROLE = "source"

    fun isEligible(state: MirroringLifecycleState, permissionsGranted: Boolean): Boolean =
        state.initialized &&
            state.enabled &&
            state.role.equals(SOURCE_ROLE, ignoreCase = true) &&
            state.paired &&
            permissionsGranted

    fun shouldMonitorNetwork(state: MirroringLifecycleState): Boolean =
        state.initialized && state.enabled && state.paired
}
