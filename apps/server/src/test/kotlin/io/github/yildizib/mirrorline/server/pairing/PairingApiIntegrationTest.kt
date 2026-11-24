package io.github.yildizib.mirrorline.server.pairing

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import io.github.yildizib.mirrorline.server.bootstrap.MirrorLineServerApplication
import io.github.yildizib.mirrorline.server.identity.AuthenticatedPrincipal
import io.github.yildizib.mirrorline.server.identity.IdentityApiIntegrationTest
import io.github.yildizib.mirrorline.server.shared.protocolv1.CanonicalJson
import io.github.yildizib.mirrorline.server.shared.protocolv1.ProtocolCrypto
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.testcontainers.service.connection.ServiceConnection
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.context.annotation.Import
import org.springframework.http.MediaType
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.test.context.TestPropertySource
import org.springframework.test.web.servlet.MockHttpServletRequestDsl
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.delete
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.post
import org.testcontainers.containers.PostgreSQLContainer
import org.testcontainers.junit.jupiter.Container
import org.testcontainers.junit.jupiter.Testcontainers
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.Signature
import java.util.Base64
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

@SpringBootTest(classes = [MirrorLineServerApplication::class])
@AutoConfigureMockMvc
@Testcontainers(disabledWithoutDocker = true)
@Import(IdentityApiIntegrationTest.MailConfiguration::class)
@TestPropertySource(
    properties = [
        "mirrorline.pairing-code-hmac-key=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    ],
)
class PairingApiIntegrationTest {
    @Autowired
    lateinit var mockMvc: MockMvc

    @Autowired
    lateinit var mapper: ObjectMapper

    @Autowired
    lateinit var jdbc: JdbcTemplate

    @Autowired
    lateinit var pairs: PairingRepository

    @Autowired
    lateinit var pairingFacade: PairingFacade

    @Autowired
    lateinit var mail: IdentityApiIntegrationTest.RecordingMailGateway

    @Test
    fun `create requires main active bearer idempotency and returns a replay safe code`() {
        val main = mainAccount()
        val correlation = UUID.randomUUID()
        mockMvc
            .post("/v1/pairings") {
                header("X-Correlation-Id", correlation.toString())
            }.andExpect {
                status { isUnauthorized() }
                jsonPath("$.code") { value("AUTH_SESSION_EXPIRED") }
                jsonPath("$.correlationId") { value(correlation.toString()) }
            }
        val key = "create-replay"
        val first = create(main, key)
        val replay = create(main, key)
        val devices =
            read(
                mockMvc
                    .get("/v1/devices") { bearer(main.token) }
                    .andExpect { status { isOk() } }
                    .andReturn()
                    .response.contentAsString,
            )
        assertThat(replay).isEqualTo(first)
        assertThat(first["state"].asText()).isEqualTo("created")
        assertThat(first["localRole"].asText()).isEqualTo("MAIN")
        assertThat(first["comparisonValue"].isNull).isTrue()
        assertThat(first["transcript"].isNull).isTrue()
        assertThat(first["expiresAt"].asText()).endsWith("Z")
        assertThat(devices[0]["createdAt"].asText()).endsWith("Z")
        assertThat(first["capacity"]["max"].asInt()).isEqualTo(5)
        assertThat(first["code"].asText()).matches("[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{10}")
        val pairingId = UUID.fromString(first["pairingId"].asText())
        assertThat(
            jdbc.queryForObject(
                "SELECT code_hash = ? FROM pairing_sessions WHERE pairing_session_id=?",
                Boolean::class.java,
                first["code"].asText().toByteArray(),
                pairingId,
            ),
        ).isFalse()
        assertThat(audit(pairingId, "PAIRING_CREATED", "SUCCESS")).isEqualTo(1)
    }

    @Test
    fun `concurrent identical create idempotency requests converge on one transaction`() {
        val main = mainAccount()
        val executor = Executors.newFixedThreadPool(2)
        try {
            val responses =
                executor
                    .invokeAll(
                        List(2) {
                            Callable {
                                mockMvc
                                    .post("/v1/pairings") {
                                        bearer(main.token)
                                        header("Idempotency-Key", "concurrent-create")
                                    }.andReturn()
                                    .response
                                    .contentAsString
                            }
                        },
                    ).map { read(it.get()) }
            assertThat(responses.map { it["pairingId"].asText() }.toSet()).hasSize(1)
            assertThat(responses.map { it["code"].asText() }.toSet()).hasSize(1)
            assertThat(
                jdbc.queryForObject(
                    "SELECT count(*) FROM pairing_create_idempotency WHERE actor_user_id=? AND actor_device_id=? AND idempotency_key=?",
                    Int::class.java,
                    main.userId,
                    main.deviceId,
                    "concurrent-create",
                ),
            ).isEqualTo(1)
        } finally {
            executor.shutdownNow()
        }
    }

    @Test
    fun `create replay remains available after active Source capacity later fills`() {
        val main = mainAccount()
        val original = create(main, "create-before-capacity")
        List(5) { sourceFor(main.email) }.forEach { source ->
            jdbc.update("UPDATE devices SET status='ACTIVE' WHERE user_id=? AND device_id=?", source.userId, source.deviceId)
        }
        assertThat(create(main, "create-before-capacity")).isEqualTo(original)
    }

    @Test
    fun `repository reads a newly created pairing without a Source`() {
        val main = mainAccount()
        val id = UUID.randomUUID()
        jdbc.update(
            """INSERT INTO pairing_sessions (pairing_session_id,initiator_user_id,initiator_device_id,initiator_public_key,initiator_key_version,initiator_key_fingerprint,code_hash,challenge,expires_at)
            VALUES (?,?,?,?,?,?,?,?,CURRENT_TIMESTAMP + INTERVAL '5 minutes')""",
            id,
            main.userId,
            main.deviceId,
            main.keys.public.encoded
                .takeLast(32)
                .toByteArray(),
            1,
            "fingerprint",
            ByteArray(32),
            ByteArray(32),
        )
        assertThat(pairs.get(id)).isNotNull
    }

    @Test
    fun `repository reports a transfer code hash collision without a database error`() {
        val main = mainAccount()
        val device = requireNotNull(pairs.device(main.userId, main.deviceId))
        val hash = ByteArray(32) { 7 }
        assertThat(pairs.create(UUID.randomUUID(), device, hash, ByteArray(32))).isNotNull()
        assertThat(pairs.create(UUID.randomUUID(), device, hash, ByteArray(32))).isNull()
    }

    @Test
    fun `repository cancellation writes a durable idempotent snapshot`() {
        val main = mainAccount()
        val created = create(main, "create-direct-cancel")
        val view =
            pairingFacade.cancel(
                AuthenticatedPrincipal(main.userId, main.deviceId, main.sessionId),
                UUID.fromString(created["pairingId"].asText()),
                "cancel-direct",
            )
        assertThat(view.state).isEqualTo("cancelled")
    }

    @Test
    fun `pending source is pairing only and both canonical proofs complete activation`() {
        val main = mainAccount()
        val source = sourceFor(main.email)
        mockMvc
            .get("/v1/devices") {
                bearer(source.token)
            }.andExpect {
                status { isForbidden() }
                jsonPath("$.code") { value("AUTH_FORBIDDEN") }
            }
        val created = create(main, "create-flow")
        val id = created["pairingId"].asText()
        val redeemed = redeem(source, id, created["code"].asText(), "redeem-flow")
        assertThat(redeemed["state"].asText()).isEqualTo("redeemed")
        assertThat(redeemed["transcript"]["main"]["role"].asText()).isEqualTo("MAIN")
        assertThat(redeemed["transcript"]["source"]["role"].asText()).isEqualTo("SOURCE")
        val mainProof = proof(main, id, redeemed["transcript"], "proof-main")
        assertThat(mainProof["comparisonValue"].isNull).isTrue()
        val sourceProof = proof(source, id, redeemed["transcript"], "proof-source")
        assertThat(sourceProof["state"].asText()).isEqualTo("proofs_verified")
        assertThat(sourceProof["comparisonValue"].asText()).matches("\\d{6}")
        assertThat(confirm(main, id, true, "confirm-main")["state"].asText()).isEqualTo("comparison_confirmed")
        assertThat(confirm(main, id, true, "confirm-main")["state"].asText()).isEqualTo("comparison_confirmed")
        val completed = confirm(source, id, true, "confirm-source")
        assertThat(completed["state"].asText()).isEqualTo("completed")
        assertThat(confirm(main, id, true, "confirm-main")["state"].asText()).isEqualTo("completed")
        assertThat(
            jdbc.queryForObject(
                "SELECT status::text FROM devices WHERE user_id=? AND device_id=?",
                String::class.java,
                source.userId,
                source.deviceId,
            ),
        ).isEqualTo("ACTIVE")
        assertThat(audit(UUID.fromString(id), "PAIRING_PROOF_ACCEPTED", "SUCCESS")).isEqualTo(2)
        assertThat(audit(UUID.fromString(id), "PAIRING_CONFIRMATION", "SUCCESS")).isEqualTo(2)
        assertThat(redeem(source, id, created["code"].asText(), "redeem-flow")["state"].asText()).isEqualTo("completed")
        assertThat(proof(main, id, redeemed["transcript"], "proof-main")["state"].asText()).isEqualTo("completed")
    }

    @Test
    fun `redeem is same account one use participant only and idempotency detects changed payload`() {
        val main = mainAccount()
        val source = sourceFor(main.email)
        val created = create(main, "create-redeem")
        val id = created["pairingId"].asText()
        val redeemed = redeem(source, id, created["code"].asText(), "redeem-idempotent")
        assertThat(redeem(source, id, created["code"].asText(), "redeem-idempotent")).isEqualTo(redeemed)
        mockMvc
            .post("/v1/pairings") {
                bearer(main.token)
                header("Idempotency-Key", "create-redeem")
            }.andExpect {
                status { isConflict() }
                jsonPath("$.code") { value("PAIRING_STATE_INVALID") }
            }.andReturn()
            .also {
                assertThat(it.response.contentAsString).doesNotContain(created["code"].asText())
            }
        mockMvc
            .post("/v1/pairings/$id/redeem") {
                bearer(source.token)
                header("Idempotency-Key", "redeem-idempotent")
                contentType = MediaType.APPLICATION_JSON
                content = """{"code":"ABCDEFGHJK"}"""
            }.andExpect {
                status { isConflict() }
                jsonPath("$.code") { value("PAIRING_STATE_INVALID") }
            }
        val another = sourceFor(main.email)
        mockMvc
            .post("/v1/pairings/$id/redeem") {
                bearer(another.token)
                header("Idempotency-Key", "different-source")
                contentType = MediaType.APPLICATION_JSON
                content = """{"code":"${created["code"].asText()}"}"""
            }.andExpect {
                status { isNotFound() }
                jsonPath("$.code") { value("PAIRING_NOT_FOUND") }
            }
        val otherMain = mainAccount()
        val otherSource = sourceFor(otherMain.email)
        mockMvc
            .post("/v1/pairings/$id/redeem") {
                bearer(otherSource.token)
                header("Idempotency-Key", "cross-account")
                contentType = MediaType.APPLICATION_JSON
                content = """{"code":"${created["code"].asText()}"}"""
            }.andExpect {
                status { isNotFound() }
                jsonPath("$.code") { value("PAIRING_NOT_FOUND") }
            }
        mockMvc
            .get("/v1/pairings/$id") {
                bearer(otherMain.token)
            }.andExpect {
                status { isNotFound() }
                jsonPath("$.code") { value("PAIRING_NOT_FOUND") }
            }
    }

    @Test
    fun `proof tamper mismatch and terminal states cannot reopen`() {
        val main = mainAccount()
        val source = sourceFor(main.email)
        val created = create(main, "create-rejected")
        val id = created["pairingId"].asText()
        val redeemed = redeem(source, id, created["code"].asText(), "redeem-rejected")
        mockMvc
            .post("/v1/pairings/$id/proofs") {
                bearer(main.token)
                header("Idempotency-Key", "invalid-proof")
                contentType = MediaType.APPLICATION_JSON
                content = """{"signature":"${encode(ByteArray(64) { 9 })}"}"""
            }.andExpect {
                status { isForbidden() }
                jsonPath("$.code") { value("PAIRING_PROOF_INVALID") }
            }
        assertThat(audit(UUID.fromString(id), "PAIRING_PROOF_REJECTED", "FAILURE")).isEqualTo(1)
        proof(main, id, redeemed["transcript"], "proof-reject-main")
        proof(source, id, redeemed["transcript"], "proof-reject-source")
        assertThat(confirm(source, id, false, "mismatch")["state"].asText()).isEqualTo("rejected")
        assertThat(confirm(source, id, false, "mismatch")["state"].asText()).isEqualTo("rejected")
        mockMvc
            .post("/v1/pairings/$id/comparison-confirmations") {
                bearer(main.token)
                header("Idempotency-Key", "late-match")
                contentType = MediaType.APPLICATION_JSON
                content = """{"matches":true}"""
            }.andExpect {
                status { isForbidden() }
                jsonPath("$.code") { value("PAIRING_STATE_INVALID") }
            }
        assertThat(
            jdbc.queryForObject(
                "SELECT state::text FROM pairing_sessions WHERE pairing_session_id=?",
                String::class.java,
                UUID.fromString(id),
            ),
        ).isEqualTo("REJECTED")
    }

    @Test
    fun `proof verification remains bound to the pairing-time public key snapshot`() {
        val main = mainAccount()
        val source = sourceFor(main.email)
        val created = create(main, "create-key-snapshot")
        val id = created["pairingId"].asText()
        val redeemed = redeem(source, id, created["code"].asText(), "redeem-key-snapshot")
        val replacement = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()
        jdbc.update(
            "UPDATE device_key_versions SET status='RETIRING',retiring_at=CURRENT_TIMESTAMP WHERE user_id=? AND device_id=? AND key_version=1",
            main.userId,
            main.deviceId,
        )
        jdbc.update(
            """INSERT INTO device_key_versions (user_id,device_id,key_version,previous_key_version,status,signing_public_key,encryption_public_key,certificate_binding_material,key_fingerprint,activated_at)
            VALUES (?,?,2,1,'ACTIVE',?,?,?,?,CURRENT_TIMESTAMP)""",
            main.userId,
            main.deviceId,
            replacement.public.encoded
                .takeLast(32)
                .toByteArray(),
            ByteArray(32) { 2 },
            ByteArray(32) { 3 },
            "rotated",
        )
        jdbc.update("UPDATE devices SET active_key_version=2 WHERE user_id=? AND device_id=?", main.userId, main.deviceId)
        val replacementSignature =
            Signature.getInstance("Ed25519").run {
                initSign(replacement.private)
                update(transcriptBytes(redeemed["transcript"]))
                sign()
            }
        mockMvc
            .post("/v1/pairings/$id/proofs") {
                bearer(main.token)
                header("Idempotency-Key", "proof-rotated-key")
                contentType = MediaType.APPLICATION_JSON
                content = """{"signature":"${encode(replacementSignature)}"}"""
            }.andExpect {
                status { isForbidden() }
                jsonPath("$.code") { value("PAIRING_PROOF_INVALID") }
            }
        assertThat(proof(main, id, redeemed["transcript"], "proof-pairing-key")["state"].asText()).isEqualTo("redeemed")
    }

    @Test
    fun `validation revoked bearer cancellation and expiry remain safe and terminal`() {
        val main = mainAccount()
        val created = create(main, "create-validation")
        val id = created["pairingId"].asText()
        mockMvc
            .post("/v1/pairings/$id/redeem") {
                bearer(main.token)
                header("Idempotency-Key", "x".repeat(129))
                contentType = MediaType.APPLICATION_JSON
                content = """{"code":"${created["code"].asText()}","unknown":true}"""
            }.andExpect {
                status { isBadRequest() }
                jsonPath("$.code") { value("VALIDATION_FAILED") }
                header { exists("X-Correlation-Id") }
            }
        mockMvc
            .delete("/v1/pairings/$id") {
                bearer(main.token)
                header("Idempotency-Key", "cancel")
            }.andExpect {
                status { isOk() }
                jsonPath("$.state") { value("cancelled") }
            }
        mockMvc
            .delete("/v1/pairings/$id") {
                bearer(main.token)
                header("Idempotency-Key", "cancel-late")
            }.andExpect { status { isForbidden() } }

        val expiring = create(main, "create-expiry")
        val expiringId = UUID.fromString(expiring["pairingId"].asText())
        val expiringSource = sourceFor(main.email)
        redeem(expiringSource, expiringId.toString(), expiring["code"].asText(), "expiry-redeem")
        jdbc.update("UPDATE pairing_sessions SET expires_at=CURRENT_TIMESTAMP WHERE pairing_session_id=?", expiringId)
        repeat(2) {
            mockMvc
                .post("/v1/pairings/$expiringId/redeem") {
                    bearer(expiringSource.token)
                    header("Idempotency-Key", "expiry-redeem")
                    contentType = MediaType.APPLICATION_JSON
                    content = """{"code":"${expiring["code"].asText()}"}"""
                }.andExpect {
                    status { isForbidden() }
                    jsonPath("$.code") { value("PAIRING_CODE_EXPIRED") }
                }
        }
        mockMvc
            .get("/v1/pairings/$expiringId") {
                bearer(main.token)
            }.andExpect {
                status { isOk() }
                jsonPath("$.state") { value("expired") }
            }
        assertThat(
            jdbc.queryForObject(
                "SELECT state::text FROM pairing_sessions WHERE pairing_session_id=?",
                String::class.java,
                expiringId,
            ),
        ).isEqualTo("EXPIRED")
        val cancelBoundary = create(main, "create-cancel-boundary")
        val cancelBoundaryId = UUID.fromString(cancelBoundary["pairingId"].asText())
        jdbc.update("UPDATE pairing_sessions SET expires_at=CURRENT_TIMESTAMP WHERE pairing_session_id=?", cancelBoundaryId)
        mockMvc
            .delete("/v1/pairings/$cancelBoundaryId") {
                bearer(main.token)
                header("Idempotency-Key", "expired-cancel")
            }.andExpect {
                status { isForbidden() }
                jsonPath("$.code") { value("PAIRING_CODE_EXPIRED") }
            }
        assertThat(
            jdbc.queryForObject(
                "SELECT state::text FROM pairing_sessions WHERE pairing_session_id=?",
                String::class.java,
                cancelBoundaryId,
            ),
        ).isEqualTo("EXPIRED")
        jdbc.update("UPDATE sessions SET status='REVOKED',revoked_at=CURRENT_TIMESTAMP WHERE session_id=?", main.sessionId)
        mockMvc
            .get("/v1/pairings/$expiringId") {
                bearer(main.token)
            }.andExpect { status { isUnauthorized() } }
    }

    @Test
    fun `expired confirm and cancel retries retain their original terminal error`() {
        val main = mainAccount()
        val source = sourceFor(main.email)
        val confirmation = prepare(main, source, "expiry-confirm")
        jdbc.update("UPDATE pairing_sessions SET expires_at=CURRENT_TIMESTAMP WHERE pairing_session_id=?", UUID.fromString(confirmation.id))
        repeat(2) {
            mockMvc
                .post("/v1/pairings/${confirmation.id}/comparison-confirmations") {
                    bearer(source.token)
                    header("Idempotency-Key", "expiry-confirm")
                    contentType = MediaType.APPLICATION_JSON
                    content = """{"matches":true}"""
                }.andExpect {
                    status { isForbidden() }
                    jsonPath("$.code") { value("PAIRING_CODE_EXPIRED") }
                }
        }
        val cancelled = create(main, "expiry-cancel")
        val cancelId = cancelled["pairingId"].asText()
        jdbc.update("UPDATE pairing_sessions SET expires_at=CURRENT_TIMESTAMP WHERE pairing_session_id=?", UUID.fromString(cancelId))
        repeat(2) {
            mockMvc
                .delete("/v1/pairings/$cancelId") {
                    bearer(main.token)
                    header("Idempotency-Key", "expiry-cancel")
                }.andExpect {
                    status { isForbidden() }
                    jsonPath("$.code") { value("PAIRING_CODE_EXPIRED") }
                }
        }
    }

    @Test
    fun `status expiry converts a prior successful redeem replay into a stable expiry tombstone`() {
        val main = mainAccount()
        val source = sourceFor(main.email)
        val created = create(main, "status-expiry")
        val id = created["pairingId"].asText()
        redeem(source, id, created["code"].asText(), "status-expiry-redeem")
        jdbc.update("UPDATE pairing_sessions SET expires_at=CURRENT_TIMESTAMP WHERE pairing_session_id=?", UUID.fromString(id))
        mockMvc
            .get("/v1/pairings/$id") { bearer(main.token) }
            .andExpect {
                status { isOk() }
                jsonPath("$.state") { value("expired") }
            }
        repeat(2) {
            mockMvc
                .post("/v1/pairings/$id/redeem") {
                    bearer(source.token)
                    header("Idempotency-Key", "status-expiry-redeem")
                    contentType = MediaType.APPLICATION_JSON
                    content = """{"code":"${created["code"].asText()}"}"""
                }.andExpect {
                    status { isForbidden() }
                    jsonPath("$.code") { value("PAIRING_CODE_EXPIRED") }
                }
        }
        mockMvc
            .post("/v1/pairings/$id/redeem") {
                bearer(source.token)
                header("Idempotency-Key", "status-expiry-redeem")
                contentType = MediaType.APPLICATION_JSON
                content = """{"code":"ABCDEFGHJK"}"""
            }.andExpect {
                status { isConflict() }
                jsonPath("$.code") { value("PAIRING_STATE_INVALID") }
            }
    }

    @Test
    fun `expiry cannot overwrite an idempotency key used by a different confirmation request`() {
        val main = mainAccount()
        val source = sourceFor(main.email)
        val prepared = prepare(main, source, "expiry-digest-conflict")
        confirm(main, prepared.id, true, "confirmation-key")
        val before =
            jdbc.queryForObject(
                "SELECT request_digest FROM pairing_idempotency WHERE pairing_session_id=? AND actor_device_id=? AND operation='CONFIRM' AND idempotency_key=?",
                ByteArray::class.java,
                UUID.fromString(prepared.id),
                main.deviceId,
                "confirmation-key",
            )!!
        jdbc.update("UPDATE pairing_sessions SET expires_at=CURRENT_TIMESTAMP WHERE pairing_session_id=?", UUID.fromString(prepared.id))
        mockMvc
            .post("/v1/pairings/${prepared.id}/comparison-confirmations") {
                bearer(main.token)
                header("Idempotency-Key", "confirmation-key")
                contentType = MediaType.APPLICATION_JSON
                content = """{"matches":false}"""
            }.andExpect {
                status { isConflict() }
                jsonPath("$.code") { value("PAIRING_STATE_INVALID") }
            }
        val after =
            jdbc.queryForObject(
                "SELECT request_digest FROM pairing_idempotency WHERE pairing_session_id=? AND actor_device_id=? AND operation='CONFIRM' AND idempotency_key=?",
                ByteArray::class.java,
                UUID.fromString(prepared.id),
                main.deviceId,
                "confirmation-key",
            )!!
        assertThat(after).isEqualTo(before)
    }

    @Test
    fun `all pairing routes require bearer and proof input has exact safe validation`() {
        val main = mainAccount()
        val source = sourceFor(main.email)
        val created = create(main, "create-auth-matrix")
        val id = created["pairingId"].asText()
        mockMvc.get("/v1/pairings/$id").andExpect { status { isUnauthorized() } }
        mockMvc
            .post("/v1/pairings/$id/redeem") {
                header("Idempotency-Key", "missing-redeem")
                contentType = MediaType.APPLICATION_JSON
                content = """{"code":"${created["code"].asText()}"}"""
            }.andExpect { status { isUnauthorized() } }
        mockMvc
            .post("/v1/pairings/$id/proofs") {
                header("Idempotency-Key", "missing-proof")
                contentType = MediaType.APPLICATION_JSON
                content = """{"signature":"${encode(ByteArray(64))}"}"""
            }.andExpect { status { isUnauthorized() } }
        mockMvc
            .post("/v1/pairings/$id/comparison-confirmations") {
                header("Idempotency-Key", "missing-confirm")
                contentType = MediaType.APPLICATION_JSON
                content = """{"matches":true}"""
            }.andExpect { status { isUnauthorized() } }
        mockMvc
            .delete("/v1/pairings/$id") {
                header("Idempotency-Key", "missing-cancel")
            }.andExpect { status { isUnauthorized() } }

        redeem(source, id, created["code"].asText(), "redeem-auth-matrix")
        listOf(ByteArray(0), ByteArray(63), ByteArray(65)).forEachIndexed { index, signature ->
            mockMvc
                .post("/v1/pairings/$id/proofs") {
                    bearer(main.token)
                    header("Idempotency-Key", "bad-length-$index")
                    contentType = MediaType.APPLICATION_JSON
                    content = """{"signature":"${encode(signature)}"}"""
                }.andExpect {
                    status { isBadRequest() }
                    jsonPath("$.code") { value("VALIDATION_FAILED") }
                }
        }
        mockMvc
            .post("/v1/pairings/$id/proofs") {
                bearer(main.token)
                header("Idempotency-Key", "bad-base64")
                contentType = MediaType.APPLICATION_JSON
                content = """{"signature":"not-base64***"}"""
            }.andExpect {
                status { isBadRequest() }
                jsonPath("$.code") { value("VALIDATION_FAILED") }
            }
        val padded = "${encode(ByteArray(64))}=="
        val nonCanonical = "${encode(ByteArray(64)).dropLast(1)}B"
        listOf(padded, nonCanonical).forEachIndexed { index, signature ->
            mockMvc
                .post("/v1/pairings/$id/proofs") {
                    bearer(main.token)
                    header("Idempotency-Key", "noncanonical-$index")
                    contentType = MediaType.APPLICATION_JSON
                    content = """{"signature":"$signature"}"""
                }.andExpect {
                    status { isBadRequest() }
                    jsonPath("$.code") { value("VALIDATION_FAILED") }
                }
        }
    }

    @Test
    fun `revoked Main or pending Source cannot complete a pairing`() {
        val main = mainAccount()
        val source = sourceFor(main.email)
        val mainRevoked = prepare(main, source, "main-revoked")
        confirm(main, mainRevoked.id, true, "main-revoked-confirm")
        mockMvc
            .delete("/v1/devices/${main.deviceId}") {
                bearer(main.token)
                header("Idempotency-Key", "revoke-main")
            }.andExpect { status { isNoContent() } }
        mockMvc
            .post("/v1/pairings/${mainRevoked.id}/comparison-confirmations") {
                bearer(source.token)
                header("Idempotency-Key", "main-revoked-source-confirm")
                contentType = MediaType.APPLICATION_JSON
                content = """{"matches":true}"""
            }.andExpect {
                status { isForbidden() }
                jsonPath("$.code") { value("PAIRING_STATE_INVALID") }
            }
        assertThat(pairingCount(mainRevoked.id)).isZero()

        val secondMain = mainAccount()
        val pendingSource = sourceFor(secondMain.email)
        val sourceRevoked = prepare(secondMain, pendingSource, "source-revoked")
        confirm(secondMain, sourceRevoked.id, true, "source-revoked-confirm")
        mockMvc
            .delete("/v1/devices/${pendingSource.deviceId}") {
                bearer(secondMain.token)
                header("Idempotency-Key", "revoke-pending-source")
            }.andExpect { status { isNoContent() } }
        mockMvc
            .post("/v1/pairings/${sourceRevoked.id}/comparison-confirmations") {
                bearer(secondMain.token)
                header("Idempotency-Key", "source-revoked-recheck")
                contentType = MediaType.APPLICATION_JSON
                content = """{"matches":true}"""
            }.andExpect {
                status { isForbidden() }
                jsonPath("$.code") { value("PAIRING_STATE_INVALID") }
            }
        assertThat(pairingCount(sourceRevoked.id)).isZero()
    }

    @Test
    fun `revoke racing final confirmation never returns 500 or completes after revocation wins`() {
        val main = mainAccount()
        val source = sourceFor(main.email)
        val prepared = prepare(main, source, "revoke-race")
        confirm(main, prepared.id, true, "revoke-race-main")
        val gate = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(2)
        try {
            val confirmation =
                executor.submit(
                    Callable {
                        gate.await(2, TimeUnit.SECONDS)
                        mockMvc
                            .post("/v1/pairings/${prepared.id}/comparison-confirmations") {
                                bearer(source.token)
                                header("Idempotency-Key", "revoke-race-source")
                                contentType = MediaType.APPLICATION_JSON
                                content = """{"matches":true}"""
                            }.andReturn()
                            .response.status
                    },
                )
            val revoke =
                executor.submit(
                    Callable {
                        gate.await(2, TimeUnit.SECONDS)
                        mockMvc
                            .delete("/v1/devices/${source.deviceId}") {
                                bearer(main.token)
                                header("Idempotency-Key", "revoke-race")
                            }.andReturn()
                            .response.status
                    },
                )
            gate.countDown()
            val confirmationStatus = confirmation.get(10, TimeUnit.SECONDS)
            assertThat(revoke.get(10, TimeUnit.SECONDS)).isEqualTo(204)
            assertThat(confirmationStatus).isNotEqualTo(500)
            if (confirmationStatus != 200) {
                assertThat(pairingCount(prepared.id)).isZero()
            }
        } finally {
            gate.countDown()
            executor.shutdownNow()
        }
    }

    @Test
    fun `unauthorized mutation does not contend on a locked pairing while participant proceeds`() {
        val main = mainAccount()
        val source = sourceFor(main.email)
        val outsiderMain = mainAccount()
        val outsider = sourceFor(outsiderMain.email)
        val created = create(main, "create-lock")
        val id = created["pairingId"].asText()
        val locked = CountDownLatch(1)
        val release = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(3)
        try {
            val holder =
                executor.submit {
                    jdbc.dataSource!!.connection.use { connection ->
                        connection.autoCommit = false
                        connection
                            .prepareStatement(
                                "SELECT pairing_session_id FROM pairing_sessions WHERE pairing_session_id=? FOR UPDATE",
                            ).use { statement ->
                                statement.setObject(1, UUID.fromString(id))
                                statement.executeQuery().use { }
                            }
                        locked.countDown()
                        release.await(5, TimeUnit.SECONDS)
                        connection.commit()
                    }
                }
            assertThat(locked.await(2, TimeUnit.SECONDS)).isTrue()
            val denied =
                executor.submit(
                    Callable {
                        mockMvc
                            .post("/v1/pairings/$id/redeem") {
                                bearer(outsider.token)
                                header("Idempotency-Key", "outsider")
                                contentType = MediaType.APPLICATION_JSON
                                content = """{"code":"${created["code"].asText()}"}"""
                            }.andReturn()
                            .response.status
                    },
                )
            val legitimate =
                executor.submit(
                    Callable {
                        mockMvc
                            .post("/v1/pairings/$id/redeem") {
                                bearer(source.token)
                                header("Idempotency-Key", "participant")
                                contentType = MediaType.APPLICATION_JSON
                                content = """{"code":"${created["code"].asText()}"}"""
                            }.andReturn()
                            .response.status
                    },
                )
            assertThat(denied.get(1, TimeUnit.SECONDS)).isEqualTo(404)
            release.countDown()
            assertThat(legitimate.get(5, TimeUnit.SECONDS)).isEqualTo(200)
            holder.get(5, TimeUnit.SECONDS)
        } finally {
            release.countDown()
            executor.shutdownNow()
        }
    }

    @Test
    fun `concurrent final source slots complete one pairing and durably fail the loser`() {
        val main = mainAccount()
        val sources = List(6) { sourceFor(main.email) }
        sources.take(4).forEach { source ->
            jdbc.update("UPDATE devices SET status='ACTIVE' WHERE user_id=? AND device_id=?", source.userId, source.deviceId)
        }
        val first = prepare(main, sources[4], "first")
        val second = prepare(main, sources[5], "second")
        confirm(main, first.id, true, "first-main")
        confirm(main, second.id, true, "second-main")
        val executor = Executors.newFixedThreadPool(2)
        try {
            val outcomes =
                listOf(first to sources[4], second to sources[5])
                    .mapIndexed { index, (pairing, source) ->
                        executor.submit(
                            Callable {
                                mockMvc
                                    .post("/v1/pairings/${pairing.id}/comparison-confirmations") {
                                        bearer(source.token)
                                        header("Idempotency-Key", "race-$index")
                                        contentType = MediaType.APPLICATION_JSON
                                        content = """{"matches":true}"""
                                    }.andReturn()
                                    .response.status
                            },
                        )
                    }.map { it.get(10, TimeUnit.SECONDS) }
            assertThat(outcomes.count { it == 200 }).isEqualTo(1)
            assertThat(outcomes.count { it == 409 }).isEqualTo(1)
        } finally {
            executor.shutdownNow()
        }
        val states =
            listOf(first.id, second.id).associateWith {
                jdbc.queryForObject(
                    "SELECT state::text FROM pairing_sessions WHERE pairing_session_id=?",
                    String::class.java,
                    UUID.fromString(it),
                )
            }
        assertThat(states.values).containsExactlyInAnyOrder("COMPLETED", "FAILED")
        val failedId = states.entries.first { it.value == "FAILED" }.key
        val failedIndex = listOf(first.id, second.id).indexOf(failedId)
        assertThat(audit(UUID.fromString(failedId), "PAIRING_COMPLETION", "FAILURE")).isEqualTo(1)
        mockMvc
            .post("/v1/pairings/$failedId/comparison-confirmations") {
                bearer(sources[4 + failedIndex].token)
                header("Idempotency-Key", "race-$failedIndex")
                contentType = MediaType.APPLICATION_JSON
                content = """{"matches":true}"""
            }.andExpect {
                status { isConflict() }
                jsonPath("$.code") { value("DEVICE_LIMIT_REACHED") }
            }
        assertThat(
            jdbc.queryForObject(
                "SELECT failure_code FROM pairing_idempotency WHERE pairing_session_id=? AND actor_device_id=? AND operation='CONFIRM'",
                String::class.java,
                UUID.fromString(failedId),
                sources[4 + failedIndex].deviceId,
            ),
        ).isEqualTo("DEVICE_LIMIT_REACHED")
        assertThat(
            jdbc.queryForObject(
                "SELECT count(*) FROM devices WHERE user_id=? AND role='SOURCE' AND status='ACTIVE'",
                Int::class.java,
                main.userId,
            ),
        ).isEqualTo(5)
    }

    private fun mainAccount(): Device = enroll(verifiedEmail(), "MAIN")

    private fun sourceFor(email: String): Device = enroll(email, "SOURCE")

    private fun verifiedEmail(): String {
        val email = "pairing-${System.nanoTime()}@example.test"
        mockMvc
            .post("/v1/auth/register") {
                contentType = MediaType.APPLICATION_JSON
                content = """{"email":"$email","password":"A-valid-password-123"}"""
            }.andExpect { status { isAccepted() } }
        mockMvc
            .post("/v1/auth/verify-email") {
                contentType = MediaType.APPLICATION_JSON
                content = """{"token":"${mail.verificationFor(email)}"}"""
            }.andExpect { status { isNoContent() } }
        return email
    }

    private fun enroll(
        email: String,
        role: String,
    ): Device {
        val grant =
            read(
                mockMvc
                    .post("/v1/auth/login") {
                        contentType = MediaType.APPLICATION_JSON
                        content = """{"email":"$email","password":"A-valid-password-123"}"""
                    }.andExpect { status { isOk() } }
                    .andReturn()
                    .response.contentAsString,
            )["enrollment"]
        val keys = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()
        val signing =
            keys.public.encoded
                .takeLast(32)
                .toByteArray()
        val encryption = ByteArray(32) { (it + 1).toByte() }
        val body =
            mapOf(
                "enrollmentToken" to grant["enrollmentToken"].asText(),
                "role" to role,
                "platform" to "android",
                "appVersion" to "1.0",
                "displayName" to "$role pairing device",
                "signingPublicKey" to encode(signing),
                "encryptionPublicKey" to encode(encryption),
                "proofSignature" to encode(signEnrollment(grant["enrollmentChallenge"].asText(), role, signing, encryption, keys)),
            )
        val response =
            read(
                mockMvc
                    .post("/v1/devices/enroll") {
                        contentType = MediaType.APPLICATION_JSON
                        content = mapper.writeValueAsString(body)
                    }.andExpect { status { isOk() } }
                    .andReturn()
                    .response.contentAsString,
            )
        return Device(
            email,
            UUID.fromString(response["userId"].asText()),
            UUID.fromString(response["deviceId"].asText()),
            response["accessToken"].asText(),
            sessionId(response["accessToken"].asText()),
            keys,
        )
    }

    private fun create(
        main: Device,
        key: String,
    ): JsonNode =
        read(
            mockMvc
                .post("/v1/pairings") {
                    bearer(main.token)
                    header("Idempotency-Key", key)
                }.andExpect { status { isOk() } }
                .andReturn()
                .response.contentAsString,
        )

    private fun redeem(
        source: Device,
        pairingId: String,
        code: String,
        key: String,
    ): JsonNode =
        read(
            mockMvc
                .post("/v1/pairings/$pairingId/redeem") {
                    bearer(source.token)
                    header("Idempotency-Key", key)
                    contentType = MediaType.APPLICATION_JSON
                    content = """{"code":"$code"}"""
                }.andExpect { status { isOk() } }
                .andReturn()
                .response.contentAsString,
        )

    private fun proof(
        device: Device,
        pairingId: String,
        transcript: JsonNode,
        key: String,
    ): JsonNode {
        val signature =
            Signature.getInstance("Ed25519").run {
                initSign(device.keys.private)
                update(transcriptBytes(transcript))
                sign()
            }
        return read(
            mockMvc
                .post("/v1/pairings/$pairingId/proofs") {
                    bearer(device.token)
                    header("Idempotency-Key", key)
                    contentType = MediaType.APPLICATION_JSON
                    content = """{"signature":"${encode(signature)}"}"""
                }.andExpect { status { isOk() } }
                .andReturn()
                .response.contentAsString,
        )
    }

    private fun confirm(
        device: Device,
        pairingId: String,
        matches: Boolean,
        key: String,
    ): JsonNode =
        read(
            mockMvc
                .post("/v1/pairings/$pairingId/comparison-confirmations") {
                    bearer(device.token)
                    header("Idempotency-Key", key)
                    contentType = MediaType.APPLICATION_JSON
                    content = """{"matches":$matches}"""
                }.andExpect { status { isOk() } }
                .andReturn()
                .response.contentAsString,
        )

    private fun prepare(
        main: Device,
        source: Device,
        label: String,
    ): PreparedPairing {
        val created = create(main, "create-$label")
        val id = created["pairingId"].asText()
        val redeemed = redeem(source, id, created["code"].asText(), "redeem-$label")
        proof(main, id, redeemed["transcript"], "proof-main-$label")
        proof(source, id, redeemed["transcript"], "proof-source-$label")
        return PreparedPairing(id)
    }

    private fun signEnrollment(
        encodedChallenge: String,
        role: String,
        signing: ByteArray,
        encryption: ByteArray,
        keys: KeyPair,
    ): ByteArray =
        Signature.getInstance("Ed25519").run {
            initSign(keys.private)
            update(
                CanonicalJson
                    .encode(
                        mapOf(
                            "appVersion" to "1.0",
                            "challenge" to encodedChallenge,
                            "displayName" to "$role pairing device",
                            "encryptionPublicKey" to encode(encryption),
                            "platform" to "android",
                            "purpose" to "mirrorline-device-enrollment-v1",
                            "role" to role,
                            "signingPublicKey" to encode(signing),
                        ),
                    ).toByteArray(),
            )
            sign()
        }

    private fun transcriptBytes(transcript: JsonNode): ByteArray =
        ProtocolCrypto.pairingTranscriptBytes(
            mapOf(
                "protocolVersion" to transcript["protocolVersion"].asInt(),
                "pairingId" to transcript["pairingId"].asText(),
                "challenge" to transcript["challenge"].asText(),
                "main" to transcriptIdentity(transcript["main"]),
                "source" to transcriptIdentity(transcript["source"]),
            ),
        )

    private fun transcriptIdentity(value: JsonNode): Map<String, Any> =
        mapOf(
            "userId" to value["userId"].asText(),
            "deviceId" to value["deviceId"].asText(),
            "role" to value["role"].asText(),
            "keyVersion" to value["keyVersion"].asInt(),
            "keyFingerprint" to value["keyFingerprint"].asText(),
        )

    private fun sessionId(access: String): UUID =
        jdbc.queryForObject(
            "SELECT session_id FROM sessions WHERE access_token_hash=?",
            UUID::class.java,
            sha256(access),
        )!!

    private fun pairingCount(pairingId: String): Int =
        jdbc.queryForObject(
            "SELECT count(*) FROM pairings WHERE pairing_session_id=?",
            Int::class.java,
            UUID.fromString(pairingId),
        )!!

    private fun audit(
        pairingId: UUID,
        type: String,
        result: String,
    ): Int =
        jdbc.queryForObject(
            "SELECT count(*) FROM security_audit_events WHERE pairing_session_id=? AND event_type=? AND result::text=?",
            Int::class.java,
            pairingId,
            type,
            result,
        )!!

    private fun sha256(value: String): ByteArray =
        java.security.MessageDigest
            .getInstance("SHA-256")
            .digest(value.toByteArray())

    private fun MockHttpServletRequestDsl.bearer(token: String) = header("Authorization", "Bearer $token")

    private fun read(value: String): JsonNode = mapper.readTree(value)

    private fun encode(value: ByteArray): String = Base64.getUrlEncoder().withoutPadding().encodeToString(value)

    data class Device(
        val email: String,
        val userId: UUID,
        val deviceId: UUID,
        val token: String,
        val sessionId: UUID,
        val keys: KeyPair,
    )

    data class PreparedPairing(
        val id: String,
    )

    companion object {
        @Container
        @ServiceConnection
        @JvmStatic
        val postgres = PostgreSQLContainer("postgres:18-alpine")
    }
}
