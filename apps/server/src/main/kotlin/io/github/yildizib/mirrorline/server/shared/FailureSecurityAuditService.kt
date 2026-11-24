package io.github.yildizib.mirrorline.server.shared

import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Propagation
import org.springframework.transaction.annotation.Transactional
import java.util.UUID

/** Persists denied/failure evidence even when the enclosing business transaction rolls back. */
@Service
class FailureSecurityAuditService(
    private val audit: SecurityAuditPersistenceRepository,
) {
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    fun append(
        eventType: String,
        result: String,
        userId: UUID? = null,
        deviceId: UUID? = null,
        sessionId: UUID? = null,
        correlationId: UUID? = null,
        failureCode: String? = null,
    ): Long = audit.append(eventType, result, userId, deviceId, sessionId, correlationId, failureCode)
}
