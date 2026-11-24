package io.github.yildizib.mirrorline.server.devices

import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.jdbc.core.RowMapper
import org.springframework.stereotype.Repository
import java.time.OffsetDateTime
import java.util.UUID

data class DeviceView(
    val deviceId: UUID,
    val role: String,
    val status: String,
    val displayName: String,
    val createdAt: OffsetDateTime,
)

@Repository
class DeviceAccountRepository(
    private val jdbcTemplate: JdbcTemplate,
) {
    fun existsActive(
        userId: UUID,
        deviceId: UUID,
    ): Boolean =
        jdbcTemplate.queryForObject(
            """
            SELECT EXISTS(
                SELECT 1 FROM devices WHERE user_id = ? AND device_id = ? AND status = 'ACTIVE'
            )
            """.trimIndent(),
            Boolean::class.java,
            userId,
            deviceId,
        )!!

    fun activeRole(
        userId: UUID,
        deviceId: UUID,
    ): String? =
        jdbcTemplate
            .queryForList(
                "SELECT role::text FROM devices WHERE user_id = ? AND device_id = ? AND status = 'ACTIVE'",
                String::class.java,
                userId,
                deviceId,
            ).firstOrNull()

    fun createActive(
        userId: UUID,
        role: String,
        platform: String,
        appVersion: String,
        displayName: String,
    ): UUID =
        jdbcTemplate.queryForObject(
            """
            INSERT INTO devices (user_id, role, status, platform, app_version, display_name)
            VALUES (?, CAST(? AS device_role), 'ACTIVE', ?, ?, ?) RETURNING device_id
            """.trimIndent(),
            UUID::class.java,
            userId,
            role,
            platform,
            appVersion,
            displayName,
        )!!

    fun createActiveKeyVersionOne(
        userId: UUID,
        deviceId: UUID,
        signingPublicKey: ByteArray,
        encryptionPublicKey: ByteArray,
        binding: ByteArray,
        fingerprint: String,
    ) {
        jdbcTemplate.update(
            """
            INSERT INTO device_key_versions (
                user_id, device_id, key_version, status, signing_public_key, encryption_public_key,
                certificate_binding_material, key_fingerprint, activated_at
            ) VALUES (?, ?, 1, 'ACTIVE', ?, ?, ?, ?, CURRENT_TIMESTAMP)
            """.trimIndent(),
            userId,
            deviceId,
            signingPublicKey,
            encryptionPublicKey,
            binding,
            fingerprint,
        )
        jdbcTemplate.update(
            "UPDATE devices SET active_key_version = 1, last_authenticated_at = CURRENT_TIMESTAMP WHERE user_id = ? AND device_id = ?",
            userId,
            deviceId,
        )
    }

    fun list(userId: UUID): List<DeviceView> =
        jdbcTemplate.query(
            """
            SELECT device_id, role::text, status::text, display_name, created_at
            FROM devices WHERE user_id = ? ORDER BY created_at
            """.trimIndent(),
            RowMapper { result, _ ->
                DeviceView(
                    result.getObject("device_id", UUID::class.java),
                    result.getString("role"),
                    result.getString("status"),
                    result.getString("display_name"),
                    result.getObject("created_at", OffsetDateTime::class.java),
                )
            },
            userId,
        )

    fun updateFcmToken(
        userId: UUID,
        deviceId: UUID,
        token: String?,
    ): Int =
        jdbcTemplate.update(
            "UPDATE devices SET fcm_token = ? WHERE user_id = ? AND device_id = ? AND status = 'ACTIVE'",
            token,
            userId,
            deviceId,
        )

    fun revoke(
        userId: UUID,
        deviceId: UUID,
    ): Int =
        jdbcTemplate.update(
            """
            UPDATE devices SET status = 'REVOKED', revoked_at = CURRENT_TIMESTAMP
            WHERE user_id = ? AND device_id = ? AND status = 'ACTIVE'
            """.trimIndent(),
            userId,
            deviceId,
        )
}
