package io.github.yildizib.mirrorline.server.devices

import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Repository
import java.util.UUID

/** Database primitives only. Device admission rules live in PostgreSQL triggers and indexes. */
@Repository
class DevicePersistenceRepository(
    private val jdbcTemplate: JdbcTemplate,
) {
    fun registerActiveDevice(
        userId: UUID,
        role: String,
        platform: String = "android",
        appVersion: String = "test",
        displayName: String = "Test device",
    ): UUID =
        jdbcTemplate.queryForObject(
            """
            INSERT INTO devices (user_id, role, status, platform, app_version, display_name)
            VALUES (?, CAST(? AS device_role), 'ACTIVE', ?, ?, ?)
            RETURNING device_id
            """.trimIndent(),
            UUID::class.java,
            userId,
            role,
            platform,
            appVersion,
            displayName,
        )!!

    fun addKeyVersion(
        userId: UUID,
        deviceId: UUID,
        keyVersion: Int,
        previousKeyVersion: Int? = null,
        signingPublicKey: ByteArray = ByteArray(32) { 1 },
        encryptionPublicKey: ByteArray = ByteArray(32) { 2 },
        certificateBindingMaterial: ByteArray = ByteArray(32) { 3 },
        fingerprint: String = "test-fingerprint",
    ) {
        jdbcTemplate.update(
            """
            INSERT INTO device_key_versions (
                user_id,
                device_id,
                key_version,
                previous_key_version,
                signing_public_key,
                encryption_public_key,
                certificate_binding_material,
                key_fingerprint
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
            userId,
            deviceId,
            keyVersion,
            previousKeyVersion,
            signingPublicKey,
            encryptionPublicKey,
            certificateBindingMaterial,
            fingerprint,
        )
    }
}
