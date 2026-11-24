package io.github.yildizib.mirrorline.server.shared

import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Repository
import java.util.UUID

/** Append-only security metadata. It intentionally has no update or delete operations. */
@Repository
class SecurityAuditPersistenceRepository(
    private val jdbcTemplate: JdbcTemplate,
) {
    fun append(
        eventType: String,
        result: String,
        userId: UUID? = null,
        deviceId: UUID? = null,
        correlationId: UUID? = null,
    ): Long =
        jdbcTemplate.queryForObject(
            """
            INSERT INTO security_audit_events (
                event_type,
                result,
                user_id,
                device_id,
                correlation_id
            ) VALUES (?, CAST(? AS audit_result), ?, ?, ?)
            RETURNING audit_event_id
            """.trimIndent(),
            Long::class.java,
            eventType,
            result,
            userId,
            deviceId,
            correlationId,
        )!!
}
