package io.github.yildizib.mirrorline.server.persistence

import io.github.yildizib.mirrorline.server.bootstrap.MirrorLineServerApplication
import io.github.yildizib.mirrorline.server.devices.DevicePersistenceRepository
import io.github.yildizib.mirrorline.server.identity.UserPersistenceRepository
import io.github.yildizib.mirrorline.server.shared.SecurityAuditPersistenceRepository
import io.github.yildizib.mirrorline.server.sync.RelayEnvelopeInput
import io.github.yildizib.mirrorline.server.sync.RelayEnvelopePersistenceRepository
import org.assertj.core.api.Assertions.assertThat
import org.assertj.core.api.Assertions.assertThatThrownBy
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.testcontainers.service.connection.ServiceConnection
import org.springframework.dao.DataAccessException
import org.springframework.jdbc.core.JdbcTemplate
import org.testcontainers.containers.PostgreSQLContainer
import org.testcontainers.junit.jupiter.Container
import org.testcontainers.junit.jupiter.Testcontainers
import java.time.OffsetDateTime
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors

@SpringBootTest(classes = [MirrorLineServerApplication::class])
@Testcontainers(disabledWithoutDocker = true)
class PersistenceSchemaIntegrationTest {
    @Autowired
    lateinit var jdbcTemplate: JdbcTemplate

    @Autowired
    lateinit var userRepository: UserPersistenceRepository

    @Autowired
    lateinit var deviceRepository: DevicePersistenceRepository

    @Autowired
    lateinit var relayEnvelopeRepository: RelayEnvelopePersistenceRepository

    @Autowired
    lateinit var securityAuditRepository: SecurityAuditPersistenceRepository

    @Test
    fun `clean database receives the marker and synchronization schema`() {
        val marker =
            jdbcTemplate.queryForObject(
                "SELECT version FROM mirrorline_schema_marker",
                Int::class.java,
            )
        val tables =
            jdbcTemplate.queryForList(
                """
                SELECT tablename
                FROM pg_tables
                WHERE schemaname = 'public'
                  AND tablename IN (
                    'users', 'sessions', 'devices', 'device_key_versions',
                    'pairing_sessions', 'pairings', 'key_rotations',
                    'key_rotation_acks', 'relay_envelopes', 'security_audit_events'
                  )
                """.trimIndent(),
                String::class.java,
            )
        val operationalColumns =
            jdbcTemplate.queryForList(
                """
                SELECT column_name
                FROM information_schema.columns
                WHERE table_schema = 'public'
                  AND (
                    (table_name = 'users' AND column_name = 'last_successful_login_at')
                    OR (table_name = 'sessions' AND column_name = 'last_used_at')
                    OR (
                        table_name = 'devices'
                        AND column_name IN (
                            'display_name', 'fcm_token', 'last_authenticated_at',
                            'last_seen_at', 'active_key_version'
                        )
                    )
                  )
                """.trimIndent(),
                String::class.java,
            )

        assertThat(marker).isEqualTo(1)
        assertThat(tables).hasSize(10)
        assertThat(operationalColumns).hasSize(7)
    }

    @Test
    fun `foreign key unique and check constraints reject invalid records`() {
        assertThat(jdbcTemplate.queryForObject("SELECT current_setting('TimeZone')", String::class.java)).isEqualTo("UTC")
        assertThatThrownBy {
            jdbcTemplate.update(
                """
                INSERT INTO devices (user_id, role, status, platform, app_version)
                VALUES (?, 'MAIN', 'ACTIVE', 'android', 'test')
                """.trimIndent(),
                UUID.randomUUID(),
            )
        }.isInstanceOf(DataAccessException::class.java)
        val userId = userRepository.createUser()
        deviceRepository.registerActiveDevice(userId, "MAIN")
        assertThatThrownBy { deviceRepository.registerActiveDevice(userId, "MAIN") }
            .isInstanceOf(DataAccessException::class.java)

        assertThatThrownBy {
            jdbcTemplate.update(
                """
                INSERT INTO sessions (user_id, session_fingerprint, expires_at)
                VALUES (?, 'fingerprint', CURRENT_TIMESTAMP - INTERVAL '1 second')
                """.trimIndent(),
                userId,
            )
        }.isInstanceOf(DataAccessException::class.java)
    }

    @Test
    fun `database serializes one Main and five active Sources per user`() {
        val userId = userRepository.createUser()
        val mainResults = submitConcurrent(2) { deviceRepository.registerActiveDevice(userId, "MAIN") }
        val sourceResults = submitConcurrent(6) { deviceRepository.registerActiveDevice(userId, "SOURCE") }

        assertThat(mainResults.count { it == null }).isEqualTo(1)
        assertThat(sourceResults.count { it == null }).isEqualTo(5)
        assertThat(
            jdbcTemplate.queryForObject(
                """
                SELECT count(*) FROM devices
                WHERE user_id = ? AND role = 'MAIN' AND status = 'ACTIVE'
                """.trimIndent(),
                Int::class.java,
                userId,
            ),
        ).isEqualTo(1)
        assertThat(
            jdbcTemplate.queryForObject(
                """
                SELECT count(*) FROM devices
                WHERE user_id = ? AND role = 'SOURCE' AND status = 'ACTIVE'
                """.trimIndent(),
                Int::class.java,
                userId,
            ),
        ).isEqualTo(5)
    }

    @Test
    fun `sender scoped replay protection permits the same message from another sender`() {
        val userId = userRepository.createUser()
        val senderOne = registerDeviceWithKey(userId, "MAIN")
        val senderTwo = registerDeviceWithKey(userId, "SOURCE")
        val recipient = registerDeviceWithKey(userId, "SOURCE")
        val messageId = UUID.randomUUID()

        val first = relayEnvelopeRepository.accept(relayInput(userId, senderOne, recipient, messageId))
        assertThat(first.idempotent).isFalse()
        assertThat(relayEnvelopeRepository.accept(relayInput(userId, senderOne, recipient, messageId)).idempotent)
            .isTrue()
        assertThatThrownBy {
            relayEnvelopeRepository.accept(
                relayInput(userId, senderOne, recipient, messageId, digest = ByteArray(32) { 99 }),
            )
        }.isInstanceOf(IllegalStateException::class.java)
        assertThat(relayEnvelopeRepository.accept(relayInput(userId, senderTwo, recipient, messageId)).idempotent)
            .isFalse()
    }

    @Test
    fun `key versions are positive and strictly increase per device`() {
        val userId = userRepository.createUser()
        val deviceId = deviceRepository.registerActiveDevice(userId, "MAIN")

        assertThatThrownBy { deviceRepository.addKeyVersion(userId, deviceId, 0) }
            .isInstanceOf(DataAccessException::class.java)
        assertThatThrownBy {
            deviceRepository.addKeyVersion(
                userId,
                deviceId,
                1,
                signingPublicKey = ByteArray(31),
            )
        }.isInstanceOf(DataAccessException::class.java)
        deviceRepository.addKeyVersion(userId, deviceId, 2)
        assertThatThrownBy { deviceRepository.addKeyVersion(userId, deviceId, 1) }
            .isInstanceOf(DataAccessException::class.java)
        deviceRepository.addKeyVersion(userId, deviceId, 3, previousKeyVersion = 2)
    }

    @Test
    fun `acknowledgement purges payload and retains a replay tombstone`() {
        val userId = userRepository.createUser()
        val sender = registerDeviceWithKey(userId, "MAIN")
        val recipient = registerDeviceWithKey(userId, "SOURCE")
        val messageId = UUID.randomUUID()
        val digest = ByteArray(32) { 14 }
        val envelopeId = relayEnvelopeRepository.accept(relayInput(userId, sender, recipient, messageId, digest)).envelopeId

        assertThat(relayEnvelopeRepository.acknowledgeAndPurge(envelopeId)).isEqualTo(1)
        val replay = relayEnvelopeRepository.accept(relayInput(userId, sender, recipient, messageId, digest))
        assertThat(replay.envelopeId).isEqualTo(envelopeId)
        assertThat(replay.idempotent).isTrue()
        val envelope =
            jdbcTemplate.queryForMap(
                """
                SELECT message_id, status::text AS status, ciphertext, nonce, signature,
                       associated_data, envelope_digest, payload_purged_at,
                       expires_at = server_accepted_at + INTERVAL '7 days' AS exact_ttl
                FROM relay_envelopes
                WHERE envelope_id = ?
                """.trimIndent(),
                envelopeId,
            )

        assertThat(envelope["message_id"]).isEqualTo(messageId)
        assertThat(envelope["status"]).isEqualTo("ACKNOWLEDGED")
        assertThat(envelope["ciphertext"]).isNull()
        assertThat(envelope["nonce"]).isNull()
        assertThat(envelope["signature"]).isNull()
        assertThat(envelope["associated_data"]).isNull()
        assertThat(envelope["envelope_digest"] as ByteArray).isEqualTo(digest)
        assertThat(envelope["payload_purged_at"]).isNotNull()
        assertThat(envelope["exact_ttl"]).isEqualTo(true)
        assertThatThrownBy {
            jdbcTemplate.update(
                "UPDATE relay_envelopes SET expires_at = CURRENT_TIMESTAMP WHERE envelope_id = ?",
                envelopeId,
            )
        }.isInstanceOf(DataAccessException::class.java)
    }

    @Test
    fun `relay requires registered key versions and valid opaque payload shapes`() {
        val userId = userRepository.createUser()
        val sender = registerDeviceWithKey(userId, "MAIN")
        val recipient = registerDeviceWithKey(userId, "SOURCE")

        assertThatThrownBy {
            relayEnvelopeRepository.accept(
                relayInput(userId, sender, recipient, UUID.randomUUID(), senderKeyVersion = 2),
            )
        }.isInstanceOf(DataAccessException::class.java)
        assertThatThrownBy {
            relayEnvelopeRepository.accept(
                relayInput(userId, sender, recipient, UUID.randomUUID(), nonce = ByteArray(11)),
            )
        }.isInstanceOf(DataAccessException::class.java)
        assertThatThrownBy {
            relayEnvelopeRepository.accept(
                relayInput(userId, sender, recipient, UUID.randomUUID(), signature = ByteArray(63)),
            )
        }.isInstanceOf(DataAccessException::class.java)
    }

    @Test
    fun `pairing workflow and durable status are separate and same account only`() {
        val userId = userRepository.createUser()
        val mainDevice = deviceRepository.registerActiveDevice(userId, "MAIN")
        val sourceDevice = deviceRepository.registerActiveDevice(userId, "SOURCE")
        val otherUserId = userRepository.createUser()
        val otherSource = deviceRepository.registerActiveDevice(otherUserId, "SOURCE")
        val pairingSessionId =
            jdbcTemplate.queryForObject(
                """
                INSERT INTO pairing_sessions (
                    initiator_user_id, initiator_device_id, state, initiator_public_key, expires_at
                ) VALUES (?, ?, 'PROOFS_VERIFIED', ?, CURRENT_TIMESTAMP + INTERVAL '15 minutes')
                RETURNING pairing_session_id
                """.trimIndent(),
                UUID::class.java,
                userId,
                mainDevice,
                ByteArray(32) { 1 },
            )!!

        assertThatThrownBy {
            jdbcTemplate.update(
                """
                INSERT INTO pairings (
                    pairing_session_id, main_user_id, main_device_id, source_user_id,
                    source_device_id, status, source_public_key
                ) VALUES (?, ?, ?, ?, ?, 'ACTIVE', ?)
                """.trimIndent(),
                pairingSessionId,
                userId,
                mainDevice,
                otherUserId,
                otherSource,
                ByteArray(32) { 2 },
            )
        }.isInstanceOf(DataAccessException::class.java)
        jdbcTemplate.update(
            """
            INSERT INTO pairings (
                pairing_session_id, main_user_id, main_device_id, source_user_id,
                source_device_id, status, source_public_key
            ) VALUES (?, ?, ?, ?, ?, 'ACTIVE', ?)
            """.trimIndent(),
            pairingSessionId,
            userId,
            mainDevice,
            userId,
            sourceDevice,
            ByteArray(32) { 3 },
        )
        val workflowAndStatus =
            jdbcTemplate.queryForMap(
                """
                SELECT pairing_sessions.state::text AS workflow_state, pairings.status::text AS status
                FROM pairing_sessions
                JOIN pairings USING (pairing_session_id)
                WHERE pairing_sessions.pairing_session_id = ?
                """.trimIndent(),
                pairingSessionId,
            )
        assertThat(workflowAndStatus["workflow_state"]).isEqualTo("PROOFS_VERIFIED")
        assertThat(workflowAndStatus["status"]).isEqualTo("ACTIVE")
    }

    @Test
    fun `V4 pairing idempotency constraints bind actors snapshots digests and expiry`() {
        val userId = userRepository.createUser()
        val deviceId = registerDeviceWithKey(userId, "MAIN")
        val pairingId = UUID.randomUUID()
        jdbcTemplate.update(
            """INSERT INTO pairing_sessions (
                pairing_session_id,initiator_user_id,initiator_device_id,initiator_public_key,initiator_key_version,initiator_key_fingerprint,
                code_hash,challenge,expires_at
            ) VALUES (?,?,?,?,?,?,?,?,CURRENT_TIMESTAMP + INTERVAL '5 minutes')""",
            pairingId,
            userId,
            deviceId,
            ByteArray(32),
            1,
            "fingerprint",
            ByteArray(32),
            ByteArray(32),
        )
        assertThatThrownBy {
            jdbcTemplate.update(
                """INSERT INTO pairing_idempotency (
                    pairing_session_id,actor_user_id,actor_device_id,operation,idempotency_key,resulting_state,
                    request_digest,response_snapshot,expires_at
                ) VALUES (?,?,?,?,?,'CREATED',?,CAST(? AS jsonb),CURRENT_TIMESTAMP + INTERVAL '5 minutes')""",
                pairingId,
                userId,
                deviceId,
                "NOT_AN_OPERATION",
                "bad-operation",
                ByteArray(31),
                "[]",
            )
        }.isInstanceOf(DataAccessException::class.java)
        assertThatThrownBy {
            jdbcTemplate.update(
                """INSERT INTO pairing_create_idempotency (
                    actor_user_id,actor_device_id,idempotency_key,request_digest,pairing_session_id,capacity_current,expires_at
                ) VALUES (?,?,?,?,?,?,CURRENT_TIMESTAMP + INTERVAL '5 minutes')""",
                UUID.randomUUID(),
                UUID.randomUUID(),
                "unknown-actor",
                ByteArray(32),
                pairingId,
                0,
            )
        }.isInstanceOf(DataAccessException::class.java)
        assertThatThrownBy {
            jdbcTemplate.update(
                """INSERT INTO pairing_sessions (
                    pairing_session_id,initiator_user_id,initiator_device_id,initiator_public_key,initiator_key_version,initiator_key_fingerprint,
                    code_hash,challenge,expires_at
                ) VALUES (?,?,?,?,?,?,?,?,CURRENT_TIMESTAMP + INTERVAL '5 minutes')""",
                UUID.randomUUID(),
                userId,
                deviceId,
                ByteArray(32),
                2,
                "fingerprint",
                ByteArray(32),
                ByteArray(32),
            )
        }.isInstanceOf(DataAccessException::class.java)
        assertThatThrownBy {
            jdbcTemplate.update(
                """INSERT INTO pairing_idempotency (
                    pairing_session_id,actor_user_id,actor_device_id,operation,idempotency_key,resulting_state,
                    request_digest,response_snapshot,failure_code,expires_at
                ) VALUES (?,?,?,?,?,'FAILED',?,CAST(? AS jsonb),'UNSAFE_FAILURE',CURRENT_TIMESTAMP + INTERVAL '5 minutes')""",
                pairingId,
                userId,
                deviceId,
                "CONFIRM",
                "bad-failure-code",
                ByteArray(32),
                "{}",
            )
        }.isInstanceOf(DataAccessException::class.java)
        assertThatThrownBy {
            jdbcTemplate.update(
                """INSERT INTO pairing_sessions (
                    pairing_session_id,initiator_user_id,initiator_device_id,initiator_public_key,initiator_key_version,
                    code_hash,challenge,state,expires_at
                ) VALUES (?,?,?,?,?,?,?,'REJECTED',CURRENT_TIMESTAMP + INTERVAL '5 minutes')""",
                UUID.randomUUID(),
                userId,
                deviceId,
                ByteArray(32),
                1,
                ByteArray(32),
                ByteArray(32),
            )
        }.isInstanceOf(DataAccessException::class.java)
    }

    @Test
    fun `audit events are append only`() {
        val auditEventId = securityAuditRepository.append("DEVICE_REGISTERED", "SUCCESS")

        assertThatThrownBy {
            jdbcTemplate.update(
                "UPDATE security_audit_events SET event_type = 'MUTATED' WHERE audit_event_id = ?",
                auditEventId,
            )
        }.isInstanceOf(DataAccessException::class.java)
        assertThatThrownBy {
            jdbcTemplate.update(
                "DELETE FROM security_audit_events WHERE audit_event_id = ?",
                auditEventId,
            )
        }.isInstanceOf(DataAccessException::class.java)
        assertThat(
            jdbcTemplate.queryForObject(
                "SELECT count(*) FROM security_audit_events WHERE audit_event_id = ?",
                Int::class.java,
                auditEventId,
            ),
        ).isEqualTo(1)
    }

    private fun registerDeviceWithKey(
        userId: UUID,
        role: String,
    ): UUID =
        deviceRepository.registerActiveDevice(userId, role).also { deviceId ->
            deviceRepository.addKeyVersion(userId, deviceId, 1)
        }

    private fun relayInput(
        userId: UUID,
        senderDeviceId: UUID,
        recipientDeviceId: UUID,
        messageId: UUID,
        digest: ByteArray = ByteArray(32) { 42 },
        senderKeyVersion: Int = 1,
        nonce: ByteArray = ByteArray(12) { 4 },
        signature: ByteArray = ByteArray(64) { 5 },
    ): RelayEnvelopeInput =
        RelayEnvelopeInput(
            senderUserId = userId,
            senderDeviceId = senderDeviceId,
            recipientUserId = userId,
            recipientDeviceId = recipientDeviceId,
            messageId = messageId,
            protocolVersion = 1,
            messageType = "SYNC_EVENT",
            clientCreatedAt = OffsetDateTime.now().minusMinutes(1),
            senderKeyVersion = senderKeyVersion,
            recipientKeyVersion = 1,
            nonce = nonce,
            ciphertext = ByteArray(16) { 6 },
            associatedData = ByteArray(8) { 7 },
            signature = signature,
            envelopeDigest = digest,
        )

    private fun submitConcurrent(
        taskCount: Int,
        action: () -> UUID,
    ): List<Throwable?> {
        val executor = Executors.newFixedThreadPool(taskCount)
        return try {
            executor
                .invokeAll(List(taskCount) { Callable { action() } })
                .map { future ->
                    try {
                        future.get()
                        null
                    } catch (exception: Exception) {
                        exception
                    }
                }
        } finally {
            executor.shutdownNow()
        }
    }

    companion object {
        @Container
        @ServiceConnection
        @JvmStatic
        val postgres = PostgreSQLContainer("postgres:18-alpine")
    }
}
