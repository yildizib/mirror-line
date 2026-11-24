package io.github.yildizib.mirrorline.server.pairing

import com.fasterxml.jackson.databind.ObjectMapper
import io.github.yildizib.mirrorline.server.bootstrap.MirrorLineProperties
import io.github.yildizib.mirrorline.server.identity.AuthenticatedPrincipal
import io.github.yildizib.mirrorline.server.shared.ApiException
import io.github.yildizib.mirrorline.server.shared.CorrelationIds
import io.github.yildizib.mirrorline.server.shared.SecurityAuditPersistenceRepository
import io.github.yildizib.mirrorline.server.shared.protocolv1.ProtocolCrypto
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.nio.charset.StandardCharsets
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.Base64
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

data class PairingCreated(
    val pairingId: UUID,
    val state: String,
    val localRole: String,
    val code: String,
    val protocolVersion: Int,
    val expiresAt: OffsetDateTime,
    val capacity: PairingCapacity,
    val comparisonValue: String? = null,
    val transcript: PairingTranscript? = null,
)

data class PairingCapacity(
    val current: Int,
    val max: Int,
)

data class PairingTranscript(
    val protocolVersion: Int,
    val pairingId: UUID,
    val challenge: String,
    val main: PairingIdentity,
    val source: PairingIdentity,
)

data class PairingView(
    val pairingId: UUID,
    val state: String,
    val localRole: String,
    val protocolVersion: Int = 1,
    val expiresAt: OffsetDateTime,
    val capacity: PairingCapacity,
    val comparisonValue: String? = null,
    val transcript: PairingTranscript? = null,
)

data class PairingIdentity(
    val userId: UUID,
    val deviceId: UUID,
    val role: String,
    val keyVersion: Int,
    val keyFingerprint: String,
)

@Service
class PairingFacade(
    private val pairs: PairingRepository,
    private val audit: SecurityAuditPersistenceRepository,
    private val mapper: ObjectMapper,
    private val properties: MirrorLineProperties,
) {
    @Transactional(noRollbackFor = [ApiException::class])
    fun create(
        principal: AuthenticatedPrincipal,
        key: String,
    ): PairingCreated {
        val main = actor(principal)
        if (main.role != "MAIN") deny("PAIRING_STATE_INVALID", main)
        pairs.lockCreate(main, key)
        pairs.deleteExpiredCreateIdempotency(main, key)
        val digest = hash(ProtocolCrypto.pairingTranscriptBytes(mapOf("operation" to "create", "protocolVersion" to 1)))
        pairs.findCreateIdempotency(main, key)?.let { existing ->
            if (!MessageDigest.isEqual(existing.requestDigest, digest)) {
                throw ApiException(HttpStatus.CONFLICT, "PAIRING_STATE_INVALID", "Pairing request conflicts with an earlier request.")
            }
            if (existing.record.state != "CREATED" || !existing.record.expiresAt.isAfter(now())) {
                throw ApiException(HttpStatus.CONFLICT, "PAIRING_STATE_INVALID", "Pairing is no longer active.")
            }
            return PairingCreated(
                existing.record.id,
                "created",
                "MAIN",
                deterministicCode(main, existing.record.id, key),
                1,
                utc(existing.record.expiresAt),
                PairingCapacity(existing.capacityCurrent, 5),
            )
        }
        val capacity = pairs.activeSourceCount(main.userId)
        if (capacity >= 5) throw ApiException(HttpStatus.CONFLICT, "DEVICE_LIMIT_REACHED", "Pairing capacity is unavailable.")
        val created =
            (1..CODE_ATTEMPTS)
                .asSequence()
                .mapNotNull {
                    val id = UUID.randomUUID()
                    val code = deterministicCode(main, id, key)
                    if (pairs.create(id, main, hash(code), ByteArray(32).also(random::nextBytes)) == null) null else id to code
                }.firstOrNull()
                ?: throw ApiException(HttpStatus.SERVICE_UNAVAILABLE, "SERVICE_UNAVAILABLE", "Pairing is unavailable.")
        val (id, code) = created
        pairs.saveCreateIdempotency(main, key, digest, id, capacity)
        audit.append(
            "PAIRING_CREATED",
            "SUCCESS",
            main.userId,
            main.deviceId,
            pairingSessionId = id,
            correlationId = CorrelationIds.current(),
        )
        val record = requireNotNull(pairs.get(id))
        return PairingCreated(id, "created", "MAIN", code, 1, utc(record.expiresAt), PairingCapacity(capacity, 5))
    }

    @Transactional(noRollbackFor = [ApiException::class])
    fun redeem(
        principal: AuthenticatedPrincipal,
        id: UUID,
        code: String,
        key: String,
    ): PairingView {
        val source = actor(principal)
        val record = redeemableRecord(id, source)
        if (source.role != "SOURCE") deny("PAIRING_STATE_INVALID", source, id)
        if (!code.matches(codePattern)) throw ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_FAILED", "The request is not valid.")
        expire(record, source, "REDEEM", key, mapOf("code" to code))
        replay(record, source, "REDEEM", key, mapOf("code" to code))?.let { return it }
        if (pairs.hasActivePairing(source.userId, source.deviceId)) fail("DEVICE_ROLE_CONFLICT", source, id)
        if (record.state != "CREATED") fail("PAIRING_CODE_USED", source, id)
        if (!MessageDigest.isEqual(record.codeHash, hash(code))) fail("PAIRING_CODE_INVALID", source, id)
        if (source.userId != record.main.userId) fail("PAIRING_CODE_INVALID", source, id)
        pairs.redeem(id, source)
        audit.append(
            "PAIRING_REDEEMED",
            "SUCCESS",
            source.userId,
            source.deviceId,
            pairingSessionId = id,
            correlationId = CorrelationIds.current(),
        )
        return saveReplay(view(requireNotNull(pairs.get(id)), source), source, "REDEEM", key, mapOf("code" to code))
    }

    @Transactional(noRollbackFor = [ApiException::class])
    fun proof(
        principal: AuthenticatedPrincipal,
        id: UUID,
        signature: ByteArray,
        key: String,
    ): PairingView {
        if (signature.size != 64) {
            throw ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_FAILED", "The request is not valid.")
        }
        val actor = actor(principal)
        val record = participantRecord(id, actor)
        expire(record, actor, "PROOF", key, mapOf("signature" to encode(signature)))
        replay(record, actor, "PROOF", key, mapOf("signature" to encode(signature)))?.let { return it }
        if (record.state !in setOf("REDEEMED", "PROOFS_VERIFIED")) fail("PAIRING_STATE_INVALID", actor, id)
        val main =
            actor.deviceId == record.main.deviceId
        val pairingKey = if (main) record.main.signingKey else requireNotNull(record.source).signingKey
        if (!verify(pairingKey, transcript(record), signature)) {
            audit.append(
                "PAIRING_PROOF_REJECTED",
                "FAILURE",
                actor.userId,
                actor.deviceId,
                pairingSessionId = id,
                correlationId = CorrelationIds.current(),
                failureCode = "PAIRING_PROOF_INVALID",
            )
            throw ApiException(HttpStatus.FORBIDDEN, "PAIRING_PROOF_INVALID", "Pairing proof was rejected.")
        }
        if ((main && record.mainProof) || (!main && record.sourceProof)) {
            return saveReplay(view(record, actor), actor, "PROOF", key, mapOf("signature" to encode(signature)))
        }
        pairs.proof(id, main, (main && record.sourceProof) || (!main && record.mainProof))
        val after = record(id, false, actor)
        audit.append(
            "PAIRING_PROOF_ACCEPTED",
            "SUCCESS",
            actor.userId,
            actor.deviceId,
            pairingSessionId = id,
            correlationId = CorrelationIds.current(),
        )
        return saveReplay(view(after, actor), actor, "PROOF", key, mapOf("signature" to encode(signature)))
    }

    @Transactional(noRollbackFor = [ApiException::class])
    fun confirm(
        principal: AuthenticatedPrincipal,
        id: UUID,
        matched: Boolean,
        key: String,
    ): PairingView {
        val actor = actor(principal)
        val record = participantRecord(id, actor)
        expire(record, actor, "CONFIRM", key, mapOf("matches" to matched))
        replay(record, actor, "CONFIRM", key, mapOf("matches" to matched))?.let { return it }
        if (record.state !in setOf("PROOFS_VERIFIED", "COMPARISON_CONFIRMED")) fail("PAIRING_STATE_INVALID", actor, id)
        val source = requireNotNull(record.source)
        pairs.lockAccountForCompletion(record.main.userId)
        if (!pairs.lockCompletionEligibility(record.main, source)) {
            pairs.terminal(id, "FAILED")
            terminalFailure(record, actor, "CONFIRM", key, mapOf("matches" to matched), "PAIRING_STATE_INVALID")
        }
        val main =
            actor.deviceId == record.main.deviceId
        val both =
            (main && record.sourceMatch == true) || (!main && record.mainMatch == true)
        pairs.confirmation(id, main, matched, both)
        var after = record(id, true, actor)
        if (matched &&
            both
        ) {
            if (pairs.activeSourceCount(after.main.userId) >= 5) {
                pairs.terminal(id, "FAILED")
                terminalFailure(after, actor, "CONFIRM", key, mapOf("matches" to matched), "DEVICE_LIMIT_REACHED")
            }
            if (!pairs.activateAndComplete(after)) {
                pairs.terminal(id, "FAILED")
                terminalFailure(after, actor, "CONFIRM", key, mapOf("matches" to matched), "PAIRING_STATE_INVALID")
            }
            after =
                record(id, false, actor)
        }
        audit.append(
            "PAIRING_CONFIRMATION",
            "SUCCESS",
            actor.userId,
            actor.deviceId,
            pairingSessionId = id,
            correlationId = CorrelationIds.current(),
        )
        return saveReplay(view(after, actor), actor, "CONFIRM", key, mapOf("matches" to matched))
    }

    @Transactional(noRollbackFor = [ApiException::class])
    fun cancel(
        principal: AuthenticatedPrincipal,
        id: UUID,
        key: String,
    ): PairingView {
        val actor = actor(principal)
        val record = participantRecord(id, actor)
        expire(record, actor, "CANCEL", key, emptyMap())
        replay(record, actor, "CANCEL", key, emptyMap())?.let { return it }
        if (record.state in
            terminals
        ) {
            fail("PAIRING_STATE_INVALID", actor, id)
        }
        pairs.terminal(id, "CANCELLED")
        audit.append(
            "PAIRING_CANCELLED",
            "SUCCESS",
            actor.userId,
            actor.deviceId,
            pairingSessionId = id,
            correlationId = CorrelationIds.current(),
        )
        return saveReplay(view(requireNotNull(pairs.get(id)), actor), actor, "CANCEL", key, emptyMap())
    }

    @Transactional(noRollbackFor = [ApiException::class])
    fun status(
        principal: AuthenticatedPrincipal,
        id: UUID,
    ): PairingView {
        val actor = actor(principal)
        val record = record(id, false, actor)
        participant(record, actor)
        expireRead(record, actor)
        return view(record(id, false, actor), actor)
    }

    private fun actor(p: AuthenticatedPrincipal) =
        pairs.device(p.userId, p.deviceId) ?: throw ApiException(HttpStatus.FORBIDDEN, "DEVICE_REVOKED", "Device is unavailable.")

    private fun record(
        id: UUID,
        lock: Boolean,
        actor: PairingDevice,
    ) = pairs.get(id, lock) ?: throw ApiException(HttpStatus.NOT_FOUND, "PAIRING_NOT_FOUND", "Pairing was not found.")

    /** Non-locking authorization prevents cross-account lock contention; the locked recheck closes the TOCTOU window. */
    private fun participantRecord(
        id: UUID,
        actor: PairingDevice,
    ): PairingRecord {
        participant(record(id, false, actor), actor)
        return record(id, true, actor).also { participant(it, actor) }
    }

    private fun redeemableRecord(
        id: UUID,
        source: PairingDevice,
    ): PairingRecord {
        redeemParticipant(record(id, false, source), source)
        return record(id, true, source).also { redeemParticipant(it, source) }
    }

    private fun participant(
        r: PairingRecord,
        a: PairingDevice,
    ) {
        if (a.userId != r.main.userId ||
            (a.deviceId != r.main.deviceId && a.deviceId != r.source?.deviceId)
        ) {
            throw ApiException(HttpStatus.NOT_FOUND, "PAIRING_NOT_FOUND", "Pairing was not found.")
        }
    }

    private fun redeemParticipant(
        record: PairingRecord,
        source: PairingDevice,
    ) {
        if (source.userId != record.main.userId || (record.source != null && source.deviceId != record.source.deviceId)) {
            notFound()
        }
    }

    private fun expire(
        r: PairingRecord,
        actor: PairingDevice,
        operation: String,
        key: String,
        request: Map<String, Any>,
    ) {
        // Terminal records are immutable, but an exact idempotency replay below may
        // still return (or rethrow) its stored, non-regressing outcome.
        val digest = requestDigest(request)
        pairs.findIdempotency(r.id, actor, operation, key)?.let { existing ->
            if (!MessageDigest.isEqual(existing.requestDigest, digest)) {
                throw ApiException(HttpStatus.CONFLICT, "PAIRING_STATE_INVALID", "Pairing request conflicts with an earlier request.")
            }
        }
        if (r.state == "EXPIRED") {
            persistExpiryOutcome(r, actor, operation, key, digest)
        }
        if (r.state in terminals) return
        if (pairs.expireIfDue(r.id) > 0) {
            audit.append(
                "PAIRING_EXPIRED",
                "SUCCESS",
                actor.userId,
                actor.deviceId,
                pairingSessionId = r.id,
                correlationId = CorrelationIds.current(),
            )
            persistExpiryOutcome(requireNotNull(pairs.get(r.id)), actor, operation, key, digest)
        }
    }

    private fun persistExpiryOutcome(
        expired: PairingRecord,
        actor: PairingDevice,
        operation: String,
        key: String,
        digest: ByteArray,
    ): Nothing {
        pairs.saveIdempotency(
            expired.id,
            actor,
            operation,
            key,
            expired.state,
            digest,
            mapper.writeValueAsString(view(expired, actor)),
            "PAIRING_CODE_EXPIRED",
        )
        throw ApiException(HttpStatus.FORBIDDEN, "PAIRING_CODE_EXPIRED", "Pairing could not be completed.")
    }

    private fun expireRead(
        r: PairingRecord,
        actor: PairingDevice,
    ) {
        if (pairs.expireIfDue(r.id) > 0) {
            audit.append(
                "PAIRING_EXPIRED",
                "SUCCESS",
                actor.userId,
                actor.deviceId,
                pairingSessionId = r.id,
                correlationId = CorrelationIds.current(),
            )
        }
    }

    private fun replay(
        record: PairingRecord,
        actor: PairingDevice,
        operation: String,
        key: String,
        request: Map<String, Any>,
    ): PairingView? {
        pairs.deleteExpiredIdempotency(record.id, actor, operation, key)
        val existing = pairs.findIdempotency(record.id, actor, operation, key) ?: return null
        if (!MessageDigest.isEqual(existing.requestDigest, requestDigest(request))) {
            throw ApiException(HttpStatus.CONFLICT, "PAIRING_STATE_INVALID", "Pairing request conflicts with an earlier request.")
        }
        existing.failureCode?.let { code ->
            throw ApiException(
                if (code == "DEVICE_LIMIT_REACHED") HttpStatus.CONFLICT else HttpStatus.FORBIDDEN,
                code,
                "Pairing could not be completed.",
            )
        }
        val snapshot = mapper.readValue(existing.responseSnapshot, PairingView::class.java)
        return if (snapshot.state == record.state.lowercase()) snapshot else view(record, actor)
    }

    private fun saveReplay(
        response: PairingView,
        actor: PairingDevice,
        operation: String,
        key: String,
        request: Map<String, Any>,
    ): PairingView {
        pairs.saveIdempotency(
            response.pairingId,
            actor,
            operation,
            key,
            response.state.uppercase(),
            requestDigest(request),
            mapper.writeValueAsString(response),
        )
        return response
    }

    private fun terminalFailure(
        record: PairingRecord,
        actor: PairingDevice,
        operation: String,
        key: String,
        request: Map<String, Any>,
        code: String,
    ): Nothing {
        val failed = requireNotNull(pairs.get(record.id))
        pairs.saveIdempotency(
            failed.id,
            actor,
            operation,
            key,
            failed.state,
            requestDigest(request),
            mapper.writeValueAsString(view(failed, actor)),
            code,
        )
        audit.append(
            "PAIRING_COMPLETION",
            "FAILURE",
            actor.userId,
            actor.deviceId,
            pairingSessionId = failed.id,
            correlationId = CorrelationIds.current(),
            failureCode = code,
        )
        throw ApiException(
            if (code == "DEVICE_LIMIT_REACHED") HttpStatus.CONFLICT else HttpStatus.FORBIDDEN,
            code,
            "Pairing could not be completed.",
        )
    }

    private fun requestDigest(request: Map<String, Any>): ByteArray = hash(ProtocolCrypto.pairingTranscriptBytes(request))

    private fun view(
        r: PairingRecord,
        actor: PairingDevice,
    ): PairingView {
        val source = r.source
        return PairingView(
            r.id,
            r.state.lowercase(),
            if (actor.deviceId == r.main.deviceId) "MAIN" else "SOURCE",
            1,
            utc(r.expiresAt),
            PairingCapacity(pairs.activeSourceCount(r.main.userId), 5),
            if (r.mainProof && r.sourceProof) comparison(r) else null,
            source?.let {
                PairingTranscript(
                    1,
                    r.id,
                    encode(requireNotNull(r.challenge)),
                    participant(r.main),
                    participant(it),
                )
            },
        )
    }

    private fun transcript(r: PairingRecord): ByteArray {
        val source = requireNotNull(r.source)
        return ProtocolCrypto.pairingTranscriptBytes(
            mapOf(
                "protocolVersion" to 1,
                "pairingId" to r.id.toString(),
                "challenge" to encode(requireNotNull(r.challenge)),
                "main" to identity(r.main),
                "source" to identity(source),
            ),
        )
    }

    private fun identity(d: PairingDevice) =
        mapOf(
            "userId" to d.userId.toString(),
            "deviceId" to d.deviceId.toString(),
            "role" to d.role,
            "keyVersion" to d.keyVersion,
            "keyFingerprint" to d.fingerprint,
        )

    private fun participant(d: PairingDevice) = PairingIdentity(d.userId, d.deviceId, d.role, d.keyVersion, d.fingerprint)

    private fun comparison(r: PairingRecord) =
        hash(transcript(r))
            .take(4)
            .fold(0L) { a, b -> (a shl 8) + (b.toInt() and 255) }
            .rem(1_000_000)
            .toString()
            .padStart(6, '0')

    private fun verify(
        key: ByteArray,
        body: ByteArray,
        sig: ByteArray,
    ) = runCatching {
        Signature.getInstance("Ed25519").run {
            initVerify(
                KeyFactory.getInstance("Ed25519").generatePublic(
                    X509EncodedKeySpec(
                        prefix + key,
                    ),
                ),
            )
            ; update(body)
            verify(sig)
        }
    }.getOrDefault(false)

    private fun fail(
        code: String,
        a: PairingDevice,
        id: UUID? = null,
    ): Nothing {
        audit.append(
            "PAIRING_FAILURE",
            "FAILURE",
            a.userId,
            a.deviceId,
            pairingSessionId = id,
            correlationId = CorrelationIds.current(),
            failureCode = code,
        )
        throw ApiException(HttpStatus.FORBIDDEN, code, "Pairing could not be completed.")
    }

    private fun deny(
        code: String,
        a: PairingDevice,
        id: UUID? = null,
    ): Nothing = fail(code, a, id)

    private fun notFound(): Nothing = throw ApiException(HttpStatus.NOT_FOUND, "PAIRING_NOT_FOUND", "Pairing was not found.")

    private fun hash(s: String) = MessageDigest.getInstance("SHA-256").digest(s.toByteArray(StandardCharsets.UTF_8))

    private fun hash(b: ByteArray) = MessageDigest.getInstance("SHA-256").digest(b)

    private fun deterministicCode(
        actor: PairingDevice,
        pairingId: UUID,
        key: String,
    ): String {
        val secret =
            runCatching { Base64.getUrlDecoder().decode(properties.pairingCodeHmacKey) }
                .getOrNull()
                ?.takeIf { it.size >= 32 }
                ?: throw ApiException(HttpStatus.SERVICE_UNAVAILABLE, "SERVICE_UNAVAILABLE", "Pairing is unavailable.")
        val material =
            ProtocolCrypto.pairingTranscriptBytes(
                mapOf(
                    "actorDeviceId" to actor.deviceId.toString(),
                    "actorUserId" to actor.userId.toString(),
                    "idempotencyKey" to key,
                    "pairingId" to pairingId.toString(),
                ),
            )
        val bytes =
            Mac.getInstance("HmacSHA256").run {
                init(SecretKeySpec(secret, "HmacSHA256"))
                doFinal(material)
            }
        return bytes.take(10).joinToString("") { ALPHABET[(it.toInt() and 0xff) and 31].toString() }
    }

    private fun encode(b: ByteArray) = Base64.getUrlEncoder().withoutPadding().encodeToString(b)

    private fun now() = OffsetDateTime.now(ZoneOffset.UTC)

    private fun utc(value: OffsetDateTime): OffsetDateTime = value.withOffsetSameInstant(ZoneOffset.UTC)

    companion object {
        private val random = SecureRandom()
        private const val ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        private const val CODE_ATTEMPTS = 4
        private val codePattern = Regex("[$ALPHABET]{10}")
        private val prefix = "302a300506032b6570032100".chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        private val terminals = setOf("COMPLETED", "EXPIRED", "CANCELLED", "REJECTED", "FAILED")
    }
}
