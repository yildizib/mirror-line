package io.github.yildizib.mirrorline.server.pairing

import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.jdbc.core.RowMapper
import org.springframework.stereotype.Repository
import java.time.OffsetDateTime
import java.util.UUID

data class PairingDevice(
    val userId: UUID,
    val deviceId: UUID,
    val role: String,
    val keyVersion: Int,
    val signingKey: ByteArray,
    val fingerprint: String,
)

data class PairingRecord(
    val id: UUID,
    val state: String,
    val main: PairingDevice,
    val source: PairingDevice?,
    val codeHash: ByteArray?,
    val challenge: ByteArray?,
    val expiresAt: OffsetDateTime,
    val mainProof: Boolean,
    val sourceProof: Boolean,
    val mainMatch: Boolean?,
    val sourceMatch: Boolean?,
)

data class CreateIdempotency(
    val requestDigest: ByteArray,
    val record: PairingRecord,
    val capacityCurrent: Int,
)

data class PairingIdempotency(
    val requestDigest: ByteArray,
    val responseSnapshot: String,
    val failureCode: String?,
)

@Repository
class PairingRepository(
    private val jdbc: JdbcTemplate,
) {
    fun activeSourceCount(userId: UUID): Int =
        jdbc.queryForObject(
            "SELECT count(*) FROM devices WHERE user_id=? AND role='SOURCE' AND status='ACTIVE'",
            Int::class.java,
            userId,
        )!!

    /** Serializes final Source admission for an account without relying on an aborted constraint transaction. */
    fun lockAccountForCompletion(userId: UUID) {
        jdbc.query(
            "SELECT pg_advisory_xact_lock(hashtextextended(?, 0))",
            { _ -> },
            userId.toString(),
        )
    }

    fun lockCreate(
        actor: PairingDevice,
        key: String,
    ) {
        jdbc.query(
            "SELECT pg_advisory_xact_lock(hashtextextended(?, 0))",
            { _ -> },
            "${actor.userId}:${actor.deviceId}:$key",
        )
    }

    fun hasActivePairing(
        userId: UUID,
        deviceId: UUID,
    ): Boolean =
        jdbc.queryForObject(
            "SELECT EXISTS (SELECT 1 FROM pairings WHERE source_user_id=? AND source_device_id=?)",
            Boolean::class.java,
            userId,
            deviceId,
        ) ?: false

    /**
     * Locks both participant rows in a stable order. The caller already holds the
     * account advisory lock, so a revoke cannot interleave with activation.
     */
    fun lockCompletionEligibility(
        main: PairingDevice,
        source: PairingDevice,
    ): Boolean {
        val rows =
            jdbc.query(
                """SELECT user_id,device_id,role::text,status::text FROM devices
                WHERE (user_id=? AND device_id=?) OR (user_id=? AND device_id=?)
                ORDER BY user_id,device_id FOR UPDATE""",
                RowMapper { r, _ ->
                    CompletionDevice(
                        r.getObject(1, UUID::class.java),
                        r.getObject(2, UUID::class.java),
                        r.getString(3),
                        r.getString(4),
                    )
                },
                main.userId,
                main.deviceId,
                source.userId,
                source.deviceId,
            )
        val lockedMain = rows.firstOrNull { it.userId == main.userId && it.deviceId == main.deviceId }
        val lockedSource = rows.firstOrNull { it.userId == source.userId && it.deviceId == source.deviceId }
        return lockedMain?.role == "MAIN" &&
            lockedMain.status == "ACTIVE" &&
            lockedSource?.role == "SOURCE" &&
            lockedSource.status == "PENDING"
    }

    fun device(
        userId: UUID,
        deviceId: UUID,
    ): PairingDevice? =
        jdbc
            .query(
                """SELECT d.user_id,d.device_id,d.role::text,d.active_key_version,k.signing_public_key,k.key_fingerprint
        FROM devices d JOIN device_key_versions k ON k.user_id=d.user_id AND k.device_id=d.device_id
          AND k.key_version=d.active_key_version AND k.status='ACTIVE'
        WHERE d.user_id=? AND d.device_id=? AND d.status IN ('ACTIVE','PENDING')""",
                deviceMapper,
                userId,
                deviceId,
            ).firstOrNull()

    fun create(
        id: UUID,
        main: PairingDevice,
        code: ByteArray,
        challenge: ByteArray,
    ): UUID? =
        jdbc
            .query(
                """INSERT INTO pairing_sessions (pairing_session_id,initiator_user_id,initiator_device_id,initiator_public_key,initiator_key_version,initiator_key_fingerprint,code_hash,challenge,expires_at)
        VALUES (?,?,?,?,?,?,?,?,CURRENT_TIMESTAMP + INTERVAL '5 minutes')
        ON CONFLICT (code_hash) WHERE code_hash IS NOT NULL DO NOTHING RETURNING pairing_session_id""",
                RowMapper { r, _ -> r.getObject(1, UUID::class.java) },
                id,
                main.userId,
                main.deviceId,
                main.signingKey,
                main.keyVersion,
                main.fingerprint,
                code,
                challenge,
            ).firstOrNull()

    fun findCreateIdempotency(
        actor: PairingDevice,
        key: String,
    ): CreateIdempotency? =
        jdbc
            .query(
                """SELECT pairing_session_id,request_digest,capacity_current FROM pairing_create_idempotency
            WHERE actor_user_id=? AND actor_device_id=? AND idempotency_key=? AND expires_at>CURRENT_TIMESTAMP""",
                RowMapper { r, _ -> Triple(r.getObject(1, UUID::class.java), r.getBytes(2), r.getInt(3)) },
                actor.userId,
                actor.deviceId,
                key,
            ).firstOrNull()
            ?.let { (id, digest, capacity) -> get(id)?.let { CreateIdempotency(digest, it, capacity) } }

    fun deleteExpiredCreateIdempotency(
        actor: PairingDevice,
        key: String,
    ) {
        jdbc.update(
            "DELETE FROM pairing_create_idempotency WHERE actor_user_id=? AND actor_device_id=? AND idempotency_key=? AND expires_at<=CURRENT_TIMESTAMP",
            actor.userId,
            actor.deviceId,
            key,
        )
    }

    fun saveCreateIdempotency(
        actor: PairingDevice,
        key: String,
        digest: ByteArray,
        pairingId: UUID,
        capacityCurrent: Int,
    ) {
        jdbc.update(
            """INSERT INTO pairing_create_idempotency (actor_user_id,actor_device_id,idempotency_key,request_digest,pairing_session_id,capacity_current,expires_at)
            VALUES (?,?,?,?,?,?,CURRENT_TIMESTAMP + INTERVAL '5 minutes')""",
            actor.userId,
            actor.deviceId,
            key,
            digest,
            pairingId,
            capacityCurrent,
        )
    }

    fun get(
        id: UUID,
        lock: Boolean = false,
    ): PairingRecord? =
        jdbc
            .query(
                """
        SELECT p.pairing_session_id,p.state::text,p.code_hash,p.challenge,p.expires_at,
          p.main_proof_verified_at IS NOT NULL main_proof,p.source_proof_verified_at IS NOT NULL source_proof,
          p.main_confirmation,p.source_confirmation,
          m.user_id main_user,m.device_id main_device,m.role::text main_role,p.initiator_key_version main_version,p.initiator_public_key main_key,p.initiator_key_fingerprint main_fingerprint,
          s.user_id source_user,s.device_id source_device,s.role::text source_role,p.source_key_version source_version,p.source_public_key source_key,p.source_key_fingerprint source_fingerprint
        FROM pairing_sessions p JOIN devices m ON (m.user_id,m.device_id)=(p.initiator_user_id,p.initiator_device_id)
          JOIN device_key_versions mk ON (mk.user_id,mk.device_id,mk.key_version)=(m.user_id,m.device_id,p.initiator_key_version)
          LEFT JOIN devices s ON (s.user_id,s.device_id)=(p.source_user_id,p.source_device_id)
          LEFT JOIN device_key_versions sk ON (sk.user_id,sk.device_id,sk.key_version)=(s.user_id,s.device_id,p.source_key_version)
        WHERE p.pairing_session_id=?${if (lock) " FOR UPDATE OF p" else ""}""",
                recordMapper,
                id,
            ).firstOrNull()

    fun redeem(
        id: UUID,
        source: PairingDevice,
    ) = jdbc.update(
        """UPDATE pairing_sessions SET state='REDEEMED',source_user_id=?,source_device_id=?,source_key_version=?,source_public_key=?,source_key_fingerprint=? WHERE pairing_session_id=?""",
        source.userId,
        source.deviceId,
        source.keyVersion,
        source.signingKey,
        source.fingerprint,
        id,
    )

    fun proof(
        id: UUID,
        main: Boolean,
        completed: Boolean,
    ) {
        val column = if (main) "main_proof_verified_at" else "source_proof_verified_at"
        jdbc.update(
            "UPDATE pairing_sessions SET $column=CURRENT_TIMESTAMP,state=CAST(? AS pairing_session_state) WHERE pairing_session_id=?",
            if (completed) "PROOFS_VERIFIED" else "REDEEMED",
            id,
        )
    }

    fun confirmation(
        id: UUID,
        main: Boolean,
        match: Boolean,
        both: Boolean,
    ) {
        val column = if (main) "main_confirmation" else "source_confirmation"
        val state =
            if (!match) {
                "REJECTED"
            } else if (both) {
                "COMPARISON_CONFIRMED"
            } else {
                "PROOFS_VERIFIED"
            }
        ; jdbc.update(
            "UPDATE pairing_sessions SET $column=?,state=CAST(? AS pairing_session_state),terminal_at=CASE WHEN ?='REJECTED' THEN CURRENT_TIMESTAMP ELSE terminal_at END WHERE pairing_session_id=?",
            match,
            state,
            state,
            id,
        )
    }

    fun terminal(
        id: UUID,
        state: String,
    ) = jdbc.update(
        "UPDATE pairing_sessions SET state=CAST(? AS pairing_session_state),terminal_at=CURRENT_TIMESTAMP WHERE pairing_session_id=?",
        state,
        id,
    )

    fun expireIfDue(id: UUID): Int =
        jdbc.update(
            """UPDATE pairing_sessions SET state='EXPIRED',terminal_at=CURRENT_TIMESTAMP
            WHERE pairing_session_id=? AND state NOT IN ('COMPLETED','EXPIRED','CANCELLED','REJECTED','FAILED')
              AND expires_at<=CURRENT_TIMESTAMP""",
            id,
        )

    fun activateAndComplete(record: PairingRecord): Boolean {
        val source = requireNotNull(record.source)
        if (
            jdbc.update(
                "UPDATE devices SET status='ACTIVE' WHERE user_id=? AND device_id=? AND status='PENDING'",
                source.userId,
                source.deviceId,
            ) != 1
        ) {
            return false
        }
        jdbc.update(
            "INSERT INTO pairings (pairing_session_id,main_user_id,main_device_id,source_user_id,source_device_id,source_public_key) VALUES (?,?,?,?,?,?)",
            record.id,
            record.main.userId,
            record.main.deviceId,
            source.userId,
            source.deviceId,
            source.signingKey,
        )
        check(
            jdbc.update(
                "UPDATE pairing_sessions SET state='COMPLETED',completed_at=CURRENT_TIMESTAMP WHERE pairing_session_id=? AND state='COMPARISON_CONFIRMED'",
                record.id,
            ) == 1,
        ) {
            "Pairing completion lost its locked comparison state."
        }
        return true
    }

    fun findIdempotency(
        id: UUID,
        actor: PairingDevice,
        operation: String,
        key: String,
    ): PairingIdempotency? =
        jdbc
            .query(
                """SELECT request_digest,response_snapshot::text,failure_code FROM pairing_idempotency
            WHERE pairing_session_id=? AND actor_user_id=? AND actor_device_id=? AND operation=?
              AND idempotency_key=? AND expires_at>CURRENT_TIMESTAMP""",
                RowMapper { r, _ -> PairingIdempotency(r.getBytes(1), r.getString(2), r.getString(3)) },
                id,
                actor.userId,
                actor.deviceId,
                operation,
                key,
            ).firstOrNull()

    fun deleteExpiredIdempotency(
        id: UUID,
        actor: PairingDevice,
        operation: String,
        key: String,
    ) {
        jdbc.update(
            """DELETE FROM pairing_idempotency WHERE pairing_session_id=? AND actor_user_id=? AND actor_device_id=?
            AND operation=? AND idempotency_key=? AND expires_at<=CURRENT_TIMESTAMP""",
            id,
            actor.userId,
            actor.deviceId,
            operation,
            key,
        )
    }

    fun saveIdempotency(
        id: UUID,
        actor: PairingDevice,
        operation: String,
        key: String,
        state: String,
        digest: ByteArray,
        snapshot: String,
        failureCode: String? = null,
    ) {
        jdbc.update(
            """INSERT INTO pairing_idempotency (pairing_session_id,actor_user_id,actor_device_id,operation,idempotency_key,resulting_state,request_digest,response_snapshot,failure_code,expires_at)
            VALUES (?,?,?,?,?,CAST(? AS pairing_session_state),?,CAST(? AS jsonb),?,CURRENT_TIMESTAMP + INTERVAL '5 minutes')
            ON CONFLICT (pairing_session_id,actor_user_id,actor_device_id,operation,idempotency_key)
            DO UPDATE SET resulting_state=EXCLUDED.resulting_state,request_digest=EXCLUDED.request_digest,
              response_snapshot=EXCLUDED.response_snapshot,failure_code=EXCLUDED.failure_code,
              expires_at=EXCLUDED.expires_at""",
            id,
            actor.userId,
            actor.deviceId,
            operation,
            key,
            state,
            digest,
            snapshot,
            failureCode,
        )
    }

    private companion object {
        data class CompletionDevice(
            val userId: UUID,
            val deviceId: UUID,
            val role: String,
            val status: String,
        )

        val deviceMapper =
            RowMapper {
                r,
                _,
                ->
                PairingDevice(
                    r.getObject(1, UUID::class.java),
                    r.getObject(2, UUID::class.java),
                    r.getString(3),
                    r.getInt(4),
                    r.getBytes(5),
                    r.getString(6),
                )
            }
        val recordMapper =
            RowMapper {
                r,
                _,
                ->
                val main =
                    PairingDevice(
                        r.getObject("main_user", UUID::class.java),
                        r.getObject("main_device", UUID::class.java),
                        r.getString("main_role"),
                        r.getInt("main_version"),
                        r.getBytes("main_key"),
                        r.getString("main_fingerprint"),
                    )
                val source =
                    r.getObject("source_user", UUID::class.java)?.let {
                        PairingDevice(
                            it,
                            r.getObject("source_device", UUID::class.java),
                            r.getString("source_role"),
                            r.getInt("source_version"),
                            r.getBytes("source_key"),
                            r.getString("source_fingerprint"),
                        )
                    }
                PairingRecord(
                    r.getObject(1, UUID::class.java),
                    r.getString(2),
                    main,
                    source,
                    r.getBytes(3),
                    r.getBytes(4),
                    r.getObject(5, OffsetDateTime::class.java),
                    r.getBoolean(6),
                    r.getBoolean(7),
                    nullableBoolean(r, 8),
                    nullableBoolean(r, 9),
                )
            }

        private fun nullableBoolean(
            result: java.sql.ResultSet,
            column: Int,
        ): Boolean? = result.getBoolean(column).let { if (result.wasNull()) null else it }
    }
}
