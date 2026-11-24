package io.github.yildizib.mirrorline.server.devices

import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.jdbc.core.RowMapper
import org.springframework.stereotype.Repository
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID

data class DeviceView(
    val deviceId: UUID,
    val role: String,
    val status: String,
    val displayName: String,
    val createdAt: OffsetDateTime,
)

data class DeviceRevokeIdempotency(
    val targetDeviceId: UUID,
)

@Repository
class DeviceAccountRepository(
    private val jdbcTemplate: JdbcTemplate,
) {
    fun lockRevokeIdempotency(
        userId: UUID,
        actorDeviceId: UUID,
        key: String,
    ) {
        jdbcTemplate.query(
            "SELECT pg_advisory_xact_lock(hashtextextended(?, 0))",
            { _ -> },
            "$userId:$actorDeviceId:$key",
        )
    }

    fun deleteExpiredRevokeIdempotency(
        userId: UUID,
        actorDeviceId: UUID,
        key: String,
    ) {
        jdbcTemplate.update(
            "DELETE FROM device_revoke_idempotency WHERE actor_user_id=? AND actor_device_id=? AND idempotency_key=? AND expires_at<=CURRENT_TIMESTAMP",
            userId,
            actorDeviceId,
            key,
        )
    }

    fun findRevokeIdempotency(
        userId: UUID,
        actorDeviceId: UUID,
        key: String,
    ): DeviceRevokeIdempotency? =
        jdbcTemplate
            .query(
                """SELECT target_device_id FROM device_revoke_idempotency
                WHERE actor_user_id=? AND actor_device_id=? AND idempotency_key=? AND expires_at>CURRENT_TIMESTAMP""",
                RowMapper { row, _ -> DeviceRevokeIdempotency(row.getObject(1, UUID::class.java)) },
                userId,
                actorDeviceId,
                key,
            ).firstOrNull()

    fun saveRevokeIdempotency(
        userId: UUID,
        actorDeviceId: UUID,
        targetDeviceId: UUID,
        key: String,
    ): Boolean =
        jdbcTemplate.update(
            """INSERT INTO device_revoke_idempotency (actor_user_id,actor_device_id,target_device_id,idempotency_key,expires_at)
            VALUES (?,?,?,?,CURRENT_TIMESTAMP + INTERVAL '5 minutes') ON CONFLICT DO NOTHING""",
            userId,
            actorDeviceId,
            targetDeviceId,
            key,
        ) == 1

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

    /** A Main may clean up an unpaired pending Source; no other pending role is manageable. */
    fun manageableRole(
        userId: UUID,
        deviceId: UUID,
    ): String? =
        jdbcTemplate
            .queryForList(
                """SELECT role::text FROM devices WHERE user_id=? AND device_id=?
                AND (status='ACTIVE' OR (role='SOURCE' AND status='PENDING'))""",
                String::class.java,
                userId,
                deviceId,
            ).firstOrNull()

    fun create(
        userId: UUID,
        role: String,
        status: String,
        platform: String,
        appVersion: String,
        displayName: String,
    ): UUID =
        jdbcTemplate.queryForObject(
            """
            INSERT INTO devices (user_id, role, status, platform, app_version, display_name)
            VALUES (?, CAST(? AS device_role), CAST(? AS device_status), ?, ?, ?) RETURNING device_id
            """.trimIndent(),
            UUID::class.java,
            userId,
            role,
            status,
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
                    result.getObject("created_at", OffsetDateTime::class.java).withOffsetSameInstant(ZoneOffset.UTC),
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
            WHERE user_id = ? AND device_id = ? AND status IN ('ACTIVE', 'PENDING')
            """.trimIndent(),
            userId,
            deviceId,
        )
}
