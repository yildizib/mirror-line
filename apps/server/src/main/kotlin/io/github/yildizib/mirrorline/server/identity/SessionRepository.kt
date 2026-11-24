package io.github.yildizib.mirrorline.server.identity

import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.jdbc.core.RowMapper
import org.springframework.stereotype.Repository
import java.sql.ResultSet
import java.time.OffsetDateTime
import java.util.UUID

data class SessionRecord(
    val sessionId: UUID,
    val userId: UUID,
    val deviceId: UUID,
    val accessExpiresAt: OffsetDateTime,
    val refreshExpiresAt: OffsetDateTime,
)

data class SessionView(
    val sessionId: UUID,
    val deviceId: UUID,
    val issuedAt: OffsetDateTime,
    val lastUsedAt: OffsetDateTime?,
    val expiresAt: OffsetDateTime,
    val status: String,
)

@Repository
class SessionRepository(
    private val jdbcTemplate: JdbcTemplate,
) {
    fun create(
        userId: UUID,
        deviceId: UUID,
        accessHash: ByteArray,
        accessExpiresAt: OffsetDateTime,
        refreshHash: ByteArray,
        refreshExpiresAt: OffsetDateTime,
    ): SessionRecord =
        jdbcTemplate.queryForObject(
            """
            INSERT INTO sessions (
                user_id, device_id, session_fingerprint, access_token_hash, access_expires_at,
                refresh_token_hash, refresh_expires_at, expires_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?) RETURNING session_id
            """.trimIndent(),
            RowMapper { result: ResultSet, _: Int ->
                SessionRecord(
                    result.getObject("session_id", UUID::class.java),
                    userId,
                    deviceId,
                    accessExpiresAt,
                    refreshExpiresAt,
                )
            },
            userId,
            deviceId,
            java.util.Base64
                .getUrlEncoder()
                .withoutPadding()
                .encodeToString(refreshHash),
            accessHash,
            accessExpiresAt,
            refreshHash,
            refreshExpiresAt,
            refreshExpiresAt,
        )!!

    fun findActiveAccess(accessHash: ByteArray): SessionRecord? =
        jdbcTemplate
            .query(
                """
                SELECT s.session_id, s.user_id, s.device_id, s.access_expires_at, s.refresh_expires_at
                FROM sessions s JOIN devices d ON d.user_id = s.user_id AND d.device_id = s.device_id
                WHERE s.access_token_hash = ? AND s.status = 'ACTIVE'
                  AND s.access_expires_at > CURRENT_TIMESTAMP AND d.status = 'ACTIVE'
                """.trimIndent(),
                recordMapper,
                accessHash,
            ).firstOrNull()

    fun rotateRefresh(
        refreshHash: ByteArray,
        accessHash: ByteArray,
        accessExpiresAt: OffsetDateTime,
        nextRefreshHash: ByteArray,
        refreshExpiresAt: OffsetDateTime,
    ): SessionRecord? =
        jdbcTemplate
            .query(
                """
                UPDATE sessions SET access_token_hash = ?, access_expires_at = ?, refresh_token_hash = ?,
                    refresh_expires_at = ?, expires_at = ?, last_used_at = CURRENT_TIMESTAMP
                WHERE refresh_token_hash = ? AND status = 'ACTIVE' AND refresh_expires_at > CURRENT_TIMESTAMP
                RETURNING session_id, user_id, device_id, access_expires_at, refresh_expires_at
                """.trimIndent(),
                recordMapper,
                accessHash,
                accessExpiresAt,
                nextRefreshHash,
                refreshExpiresAt,
                refreshExpiresAt,
                refreshHash,
            ).firstOrNull()

    fun listForUser(userId: UUID): List<SessionView> =
        jdbcTemplate.query(
            """
            SELECT session_id, device_id, issued_at, last_used_at, expires_at, status::text
            FROM sessions WHERE user_id = ? ORDER BY issued_at DESC
            """.trimIndent(),
            RowMapper { result, _ ->
                SessionView(
                    result.getObject("session_id", UUID::class.java),
                    result.getObject("device_id", UUID::class.java),
                    result.getObject("issued_at", OffsetDateTime::class.java),
                    result.getObject("last_used_at", OffsetDateTime::class.java),
                    result.getObject("expires_at", OffsetDateTime::class.java),
                    result.getString("status"),
                )
            },
            userId,
        )

    fun revoke(
        userId: UUID,
        sessionId: UUID,
    ): Int =
        jdbcTemplate.update(
            """
            UPDATE sessions SET status = 'REVOKED', revoked_at = CURRENT_TIMESTAMP
            WHERE user_id = ? AND session_id = ? AND status = 'ACTIVE'
            """.trimIndent(),
            userId,
            sessionId,
        )

    fun revokeForDevice(
        userId: UUID,
        deviceId: UUID,
    ) {
        jdbcTemplate.update(
            """
            UPDATE sessions SET status = 'REVOKED', revoked_at = CURRENT_TIMESTAMP
            WHERE user_id = ? AND device_id = ? AND status = 'ACTIVE'
            """.trimIndent(),
            userId,
            deviceId,
        )
    }

    fun revokeAll(userId: UUID) {
        jdbcTemplate.update(
            """
            UPDATE sessions SET status = 'REVOKED', revoked_at = CURRENT_TIMESTAMP
            WHERE user_id = ? AND status = 'ACTIVE'
            """.trimIndent(),
            userId,
        )
    }

    private companion object {
        val recordMapper =
            RowMapper { result: ResultSet, _: Int ->
                SessionRecord(
                    result.getObject("session_id", UUID::class.java),
                    result.getObject("user_id", UUID::class.java),
                    result.getObject("device_id", UUID::class.java),
                    result.getObject("access_expires_at", OffsetDateTime::class.java),
                    result.getObject("refresh_expires_at", OffsetDateTime::class.java),
                )
            }
    }
}
