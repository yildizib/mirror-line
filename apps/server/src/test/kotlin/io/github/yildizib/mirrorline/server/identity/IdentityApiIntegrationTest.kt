package io.github.yildizib.mirrorline.server.identity

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import io.github.yildizib.mirrorline.server.bootstrap.MirrorLineServerApplication
import io.github.yildizib.mirrorline.server.shared.protocolv1.CanonicalJson
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.context.TestConfiguration
import org.springframework.boot.testcontainers.service.connection.ServiceConnection
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Import
import org.springframework.context.annotation.Primary
import org.springframework.http.MediaType
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.delete
import org.springframework.test.web.servlet.post
import org.testcontainers.containers.PostgreSQLContainer
import org.testcontainers.junit.jupiter.Container
import org.testcontainers.junit.jupiter.Testcontainers
import java.security.KeyPairGenerator
import java.security.Signature
import java.time.OffsetDateTime
import java.util.Base64
import java.util.UUID

@SpringBootTest(classes = [MirrorLineServerApplication::class])
@AutoConfigureMockMvc
@Testcontainers
@Import(IdentityApiIntegrationTest.MailConfiguration::class)
class IdentityApiIntegrationTest {
    @Autowired
    lateinit var mockMvc: MockMvc

    @Autowired
    lateinit var objectMapper: ObjectMapper

    @Autowired
    lateinit var mail: RecordingMailGateway

    @Autowired
    lateinit var jdbcTemplate: JdbcTemplate

    @Autowired
    lateinit var sessionRepository: SessionRepository

    @BeforeEach
    fun resetMail() = mail.clear()

    @Test
    fun `registration normalizes email and sends only a one use verification token`() {
        val email = uniqueEmail()
        register(email.replace("identity-", "Identity-")).andExpect { status { isAccepted() } }
        val duplicateCorrelation = UUID.randomUUID()
        mockMvc
            .post("/v1/auth/register") {
                header("X-Correlation-Id", duplicateCorrelation.toString())
                contentType = MediaType.APPLICATION_JSON
                content = """{"email":"$email","password":"A-valid-password-123"}"""
            }.andExpect { status { isBadRequest() } }
        assertThat(auditCount("ACCOUNT_REGISTERED", "FAILURE", duplicateCorrelation)).isEqualTo(1)
        val token = mail.verificationFor(email)
        verify(token).andExpect { status { isNoContent() } }
        verify(token).andExpect { status { isBadRequest() } }
        assertThat(
            jdbcTemplate.queryForObject("SELECT octet_length(token_hash) FROM account_action_tokens LIMIT 1", Int::class.java),
        ).isEqualTo(32)
    }

    @Test
    fun `verification tokens expire before use`() {
        val email = uniqueEmail()
        register(email).andExpect { status { isAccepted() } }
        val token = mail.verificationFor(email)
        jdbcTemplate.update(
            "UPDATE account_action_tokens SET expires_at = created_at + INTERVAL '1 microsecond' WHERE token_hash = ?",
            AccountFacade.hash(token),
        )
        verify(token).andExpect {
            status { isBadRequest() }
            jsonPath("$.code") { value("VALIDATION_FAILED") }
        }
    }

    @Test
    fun `reset and enrollment action tokens are one use and expire`() {
        val email = verifiedAccount()
        mockMvc
            .post("/v1/auth/forgot-password") {
                contentType = MediaType.APPLICATION_JSON
                content = """{"email":"$email"}"""
            }.andExpect { status { isAccepted() } }
        val reset = mail.resetFor(email)
        jdbcTemplate.update(
            "UPDATE account_action_tokens SET expires_at = created_at + INTERVAL '1 microsecond' WHERE token_hash = ?",
            AccountFacade.hash(reset),
        )
        mockMvc
            .post("/v1/auth/reset-password") {
                contentType = MediaType.APPLICATION_JSON
                content = """{"token":"$reset","password":"A-new-password-123"}"""
            }.andExpect { status { isBadRequest() } }

        val grant = loginForEnrollment(email)
        val payload = enrollmentPayload(grant, "MAIN")
        mockMvc
            .post("/v1/devices/enroll") {
                contentType = MediaType.APPLICATION_JSON
                content = payload
            }.andExpect { status { isOk() } }
        mockMvc
            .post("/v1/devices/enroll") {
                contentType = MediaType.APPLICATION_JSON
                content = payload
            }.andExpect {
                status { isForbidden() }
                jsonPath("$.code") { value("AUTH_FORBIDDEN") }
            }
        val expiringGrant = loginForEnrollment(email)
        jdbcTemplate.update(
            "UPDATE account_action_tokens SET expires_at = created_at + INTERVAL '1 microsecond' WHERE token_hash = ?",
            AccountFacade.hash(expiringGrant["enrollmentToken"].asText()),
        )
        mockMvc
            .post("/v1/devices/enroll") {
                contentType = MediaType.APPLICATION_JSON
                content = enrollmentPayload(expiringGrant, "SOURCE")
            }.andExpect {
                status { isForbidden() }
                jsonPath("$.code") { value("AUTH_FORBIDDEN") }
            }
    }

    @Test
    fun `password policy accepts complete passwords and rejects incomplete registration and reset passwords`() {
        val rejectedEmail = uniqueEmail()
        mockMvc
            .post("/v1/auth/register") {
                contentType = MediaType.APPLICATION_JSON
                content = """{"email":"$rejectedEmail","password":"alllowercase-password"}"""
            }.andExpect {
                status { isBadRequest() }
                jsonPath("$.code") { value("VALIDATION_FAILED") }
            }
        val email = verifiedAccount()
        mockMvc
            .post("/v1/auth/forgot-password") {
                contentType = MediaType.APPLICATION_JSON
                content = """{"email":"$email"}"""
            }.andExpect { status { isAccepted() } }
        mockMvc
            .post("/v1/auth/reset-password") {
                contentType = MediaType.APPLICATION_JSON
                content = """{"token":"${mail.resetFor(email)}","password":"alllowercase-password"}"""
            }.andExpect {
                status { isBadRequest() }
                jsonPath("$.code") { value("VALIDATION_FAILED") }
            }
    }

    @Test
    fun `wrong credentials are neutral and do not overwrite last successful login`() {
        val email = verifiedAccount()
        val device = enroll(loginForEnrollment(email), "MAIN")
        loginForDevice(email, device["deviceId"].asText())
        val successfulLogin =
            jdbcTemplate.queryForObject(
                "SELECT last_successful_login_at FROM users WHERE email_normalized = ?",
                OffsetDateTime::class.java,
                email,
            )!!
        val failureCorrelation = UUID.randomUUID()
        mockMvc
            .post("/v1/auth/login") {
                header("X-Correlation-Id", failureCorrelation.toString())
                contentType = MediaType.APPLICATION_JSON
                content = """{"email":"$email","password":"incorrect-password"}"""
            }.andExpect {
                status { isUnauthorized() }
                jsonPath("$.code") { value("AUTH_INVALID_CREDENTIALS") }
            }
        assertThat(auditCount("LOGIN", "FAILURE", failureCorrelation)).isEqualTo(1)
        assertThat(
            jdbcTemplate.queryForObject(
                "SELECT last_successful_login_at FROM users WHERE email_normalized = ?",
                OffsetDateTime::class.java,
                email,
            ),
        ).isEqualTo(successfulLogin)
    }

    @Test
    fun `enrollment creates server device id key version and opaque session`() {
        val login = loginForEnrollment(verifiedAccount())
        val enrolled = enroll(login, "MAIN")
        assertThat(enrolled["userId"].asText()).matches("[0-9a-f-]{36}")
        assertThat(enrolled["deviceId"].asText()).matches("[0-9a-f-]{36}")
        assertThat(enrolled["keyVersion"].asInt()).isEqualTo(1)
        assertThat(
            jdbcTemplate.queryForObject(
                "SELECT octet_length(access_token_hash) FROM sessions ORDER BY issued_at DESC LIMIT 1",
                Int::class.java,
            ),
        ).isEqualTo(32)
        assertThat(
            jdbcTemplate.queryForObject(
                "SELECT EXTRACT(EPOCH FROM access_expires_at - issued_at)::int FROM sessions WHERE device_id = ?",
                Int::class.java,
                UUID.fromString(enrolled["deviceId"].asText()),
            ),
        ).isEqualTo(15 * 60)
        assertThat(
            jdbcTemplate.queryForObject(
                "SELECT EXTRACT(EPOCH FROM refresh_expires_at - issued_at)::int FROM sessions WHERE device_id = ?",
                Int::class.java,
                UUID.fromString(enrolled["deviceId"].asText()),
            ),
        ).isEqualTo(30 * 24 * 60 * 60)
        assertThat(
            jdbcTemplate.queryForObject(
                "SELECT password_hash FROM users WHERE user_id = ?",
                String::class.java,
                UUID.fromString(enrolled["userId"].asText()),
            ),
        ).startsWith("\$2a\$12\$")
        assertThat(
            jdbcTemplate.queryForObject(
                "SELECT count(*) FROM sessions WHERE access_token_hash = ? OR refresh_token_hash = ?",
                Int::class.java,
                enrolled["accessToken"].asText().toByteArray(),
                enrolled["refreshToken"].asText().toByteArray(),
            ),
        ).isZero()
        assertThat(
            jdbcTemplate.queryForObject(
                "SELECT last_successful_login_at IS NOT NULL FROM users ORDER BY created_at DESC LIMIT 1",
                Boolean::class.java,
            ),
        ).isTrue()
    }

    @Test
    fun `refresh rotates tokens and reset revokes active sessions without revealing email existence`() {
        val email = verifiedAccount()
        val enrollment = enroll(loginForEnrollment(email), "MAIN")
        val refresh = enrollment["refreshToken"].asText()
        val rotated =
            read(
                refresh(refresh)
                    .andExpect { status { isOk() } }
                    .andReturn()
                    .response.contentAsString,
            )
        assertThat(rotated["userId"].asText()).isEqualTo(enrollment["userId"].asText())
        assertThat(rotated["deviceId"].asText()).isEqualTo(enrollment["deviceId"].asText())
        refresh(refresh).andExpect { status { isUnauthorized() } }
        mockMvc
            .post("/v1/auth/forgot-password") {
                contentType = MediaType.APPLICATION_JSON
                content = """{"email":"missing-${System.nanoTime()}@example.test"}"""
            }.andExpect { status { isAccepted() } }
        mockMvc
            .post("/v1/auth/forgot-password") {
                contentType = MediaType.APPLICATION_JSON
                content = """{"email":"$email"}"""
            }.andExpect { status { isAccepted() } }
        val reset = mail.resetFor(email)
        mockMvc
            .post("/v1/auth/reset-password") {
                contentType = MediaType.APPLICATION_JSON
                content = """{"token":"$reset","password":"A-new-password-123"}"""
            }.andExpect { status { isNoContent() } }
        mockMvc
            .post("/v1/auth/reset-password") {
                contentType = MediaType.APPLICATION_JSON
                content = """{"token":"$reset","password":"A-new-password-123"}"""
            }.andExpect {
                status { isBadRequest() }
                jsonPath("$.code") { value("VALIDATION_FAILED") }
            }
        assertThat(
            jdbcTemplate.queryForObject(
                "SELECT count(*) FROM sessions s JOIN users u ON s.user_id = u.user_id WHERE u.email_normalized = ? AND s.status = 'ACTIVE'",
                Int::class.java,
                email,
            ),
        ).isZero()
        refresh(rotated["refreshToken"].asText()).andExpect { status { isUnauthorized() } }
    }

    @Test
    fun `session repository rotates a hashed opaque refresh token`() {
        val enrolled = enroll(loginForEnrollment(verifiedAccount()), "MAIN")
        val rotated =
            sessionRepository.rotateRefresh(
                AccountFacade.hash(enrolled["refreshToken"].asText()),
                AccountFacade.hash(AccountFacade.randomToken()),
                OffsetDateTime.now().plusMinutes(15),
                AccountFacade.hash(AccountFacade.randomToken()),
                OffsetDateTime.now().plusDays(30),
            )
        assertThat(rotated).isNotNull
    }

    @Test
    fun `device APIs deny cross user updates and reject malformed or tampered enrollment`() {
        val first = enroll(loginForEnrollment(verifiedAccount()), "MAIN")
        val second = enroll(loginForEnrollment(verifiedAccount()), "MAIN")
        mockMvc
            .post("/v1/devices/${second["deviceId"].asText()}/fcm-token") {
                header("Authorization", "Bearer ${first["accessToken"].asText()}")
                contentType = MediaType.APPLICATION_JSON
                content = """{"fcmToken":"not-logged"}"""
            }.andExpect { status { isForbidden() } }
        val login = loginForEnrollment(verifiedAccount())
        val proofCorrelation = UUID.randomUUID()
        mockMvc
            .post("/v1/devices/enroll") {
                header("X-Correlation-Id", proofCorrelation.toString())
                contentType = MediaType.APPLICATION_JSON
                content =
                    """{"enrollmentToken":"${login["enrollmentToken"].asText()}","role":"MAIN","platform":"android","appVersion":"1","displayName":"bad","signingPublicKey":"AA","encryptionPublicKey":"AA","proofSignature":"AA","signingPrivateKey":"never"}"""
            }.andExpect {
                status { isBadRequest() }
                jsonPath("$.code") { value("VALIDATION_FAILED") }
                jsonPath("$.correlationId") { exists() }
                header { exists("X-Correlation-Id") }
            }

        val tampered = loginForEnrollment(verifiedAccount())
        val keys = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()
        val signing =
            keys.public.encoded
                .takeLast(32)
                .toByteArray()
        mockMvc
            .post("/v1/devices/enroll") {
                contentType = MediaType.APPLICATION_JSON
                content =
                    objectMapper.writeValueAsString(
                        mapOf(
                            "enrollmentToken" to tampered["enrollmentToken"].asText(),
                            "role" to "MAIN",
                            "platform" to "android",
                            "appVersion" to "1.0",
                            "displayName" to "Tampered proof",
                            "signingPublicKey" to encode(signing),
                            "encryptionPublicKey" to encode(ByteArray(32) { 3 }),
                            "proofSignature" to encode(ByteArray(64) { 7 }),
                        ),
                    )
            }.andExpect {
                status { isForbidden() }
                jsonPath("$.code") { value("PAIRING_PROOF_INVALID") }
            }
        val tamperedUserId = UUID.fromString(tampered["userId"].asText())
        assertThat(auditCount("DEVICE_REGISTRATION", "FAILURE", userId = tamperedUserId)).isEqualTo(1)
        assertThat(auditCount("DEVICE_REGISTERED", "SUCCESS", userId = tamperedUserId)).isZero()
    }

    @Test
    fun `unpaired Sources are pending and cannot obtain normal product sessions`() {
        val email = verifiedAccount()
        val main = enroll(loginForEnrollment(email), "MAIN")
        val source = enroll(loginForEnrollment(email), "SOURCE")
        mockMvc
            .post("/v1/auth/login") {
                contentType = MediaType.APPLICATION_JSON
                content = """{"email":"$email","password":"A-valid-password-123","deviceId":"${source["deviceId"].asText()}"}"""
            }.andExpect {
                status { isForbidden() }
                jsonPath("$.code") { value("DEVICE_REVOKED") }
            }
        mockMvc
            .delete("/v1/devices/${source["deviceId"].asText()}") {
                header("Authorization", "Bearer ${source["accessToken"].asText()}")
                header("Idempotency-Key", "source-revoke-main")
            }.andExpect {
                status { isForbidden() }
                jsonPath("$.code") { value("AUTH_FORBIDDEN") }
            }
        val otherMain = enroll(loginForEnrollment(verifiedAccount()), "MAIN")
        mockMvc
            .delete("/v1/devices/${source["deviceId"].asText()}") {
                header("Authorization", "Bearer ${otherMain["accessToken"].asText()}")
                header("Idempotency-Key", "cross-account-revoke")
            }.andExpect {
                status { isNotFound() }
                jsonPath("$.code") { value("DEVICE_NOT_FOUND") }
            }
        mockMvc
            .delete("/v1/devices/${source["deviceId"].asText()}") {
                header("Authorization", "Bearer ${main["accessToken"].asText()}")
                header("Idempotency-Key", "main-revoke-source")
            }.andExpect { status { isNoContent() } }
        mockMvc
            .delete("/v1/devices/${source["deviceId"].asText()}") {
                header("Authorization", "Bearer ${main["accessToken"].asText()}")
                header("Idempotency-Key", "main-revoke-source")
            }.andExpect { status { isNoContent() } }
        mockMvc
            .delete("/v1/devices/${main["deviceId"].asText()}") {
                header("Authorization", "Bearer ${main["accessToken"].asText()}")
                header("Idempotency-Key", "main-revoke-source")
            }.andExpect {
                status { isConflict() }
                jsonPath("$.code") { value("PAIRING_STATE_INVALID") }
            }
        assertThat(
            jdbcTemplate.queryForObject(
                "SELECT status::text FROM devices WHERE user_id = ? AND device_id = ?",
                String::class.java,
                UUID.fromString(source["userId"].asText()),
                UUID.fromString(source["deviceId"].asText()),
            ),
        ).isEqualTo("REVOKED")
    }

    @Test
    fun `Source enrollment remains pending until pairing completion and does not consume quota`() {
        val email = verifiedAccount()
        enroll(loginForEnrollment(email), "MAIN")
        repeat(6) { enroll(loginForEnrollment(email), "SOURCE") }
        assertThat(
            jdbcTemplate.queryForObject(
                "SELECT count(*) FROM devices d JOIN users u ON d.user_id=u.user_id WHERE u.email_normalized=? AND d.role='SOURCE' AND d.status='ACTIVE'",
                Int::class.java,
                email,
            ),
        ).isZero()
        assertThat(
            jdbcTemplate.queryForObject(
                "SELECT count(*) FROM devices d JOIN users u ON d.user_id=u.user_id WHERE u.email_normalized=? AND d.role='SOURCE' AND d.status='PENDING'",
                Int::class.java,
                email,
            ),
        ).isEqualTo(6)
    }

    @Test
    fun `second main and cross user session revocation are denied without enumeration`() {
        val firstEmail = verifiedAccount()
        val first = enroll(loginForEnrollment(firstEmail), "MAIN")
        val secondMainLogin = loginForEnrollment(firstEmail)
        mockMvc
            .post("/v1/devices/enroll") {
                contentType = MediaType.APPLICATION_JSON
                content = enrollmentPayload(secondMainLogin, "MAIN")
            }.andExpect {
                status { isForbidden() }
                jsonPath("$.code") { value("DEVICE_ROLE_CONFLICT") }
            }

        val other = enroll(loginForEnrollment(verifiedAccount()), "MAIN")
        val otherSessionId =
            jdbcTemplate.queryForObject(
                "SELECT session_id FROM sessions WHERE user_id = ? ORDER BY issued_at DESC LIMIT 1",
                UUID::class.java,
                UUID.fromString(other["userId"].asText()),
            )!!
        mockMvc
            .delete("/v1/sessions/$otherSessionId") {
                header("Authorization", "Bearer ${first["accessToken"].asText()}")
            }.andExpect {
                status { isNotFound() }
                jsonPath("$.code") { value("AUTH_SESSION_EXPIRED") }
            }
    }

    private fun verifiedAccount(): String {
        val email = uniqueEmail()
        register(email).andExpect { status { isAccepted() } }
        verify(mail.verificationFor(email))
        return email
    }

    private fun register(email: String) =
        mockMvc
            .post("/v1/auth/register") {
                contentType = MediaType.APPLICATION_JSON
                content = """{"email":"$email","password":"A-valid-password-123"}"""
            }

    private fun verify(token: String) =
        mockMvc.post("/v1/auth/verify-email") {
            contentType = MediaType.APPLICATION_JSON
            content = """{"token":"$token"}"""
        }

    private fun loginForEnrollment(email: String): JsonNode =
        read(
            mockMvc
                .post("/v1/auth/login") {
                    contentType = MediaType.APPLICATION_JSON
                    content = """{"email":"$email","password":"A-valid-password-123"}"""
                }.andExpect { status { isOk() } }
                .andReturn()
                .response.contentAsString,
        )["enrollment"]

    private fun loginForDevice(
        email: String,
        deviceId: String,
    ): JsonNode =
        read(
            mockMvc
                .post("/v1/auth/login") {
                    contentType = MediaType.APPLICATION_JSON
                    content = """{"email":"$email","password":"A-valid-password-123","deviceId":"$deviceId"}"""
                }.andExpect { status { isOk() } }
                .andReturn()
                .response.contentAsString,
        )["tokens"]

    private fun enroll(
        login: JsonNode,
        role: String,
    ): JsonNode =
        read(
            mockMvc
                .post("/v1/devices/enroll") {
                    contentType = MediaType.APPLICATION_JSON
                    content = enrollmentPayload(login, role)
                }.andExpect { status { isOk() } }
                .andReturn()
                .response.contentAsString,
        )

    private fun enrollmentPayload(
        login: JsonNode,
        role: String,
    ): String {
        val keys = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()
        val signing =
            keys.public.encoded
                .takeLast(32)
                .toByteArray()
        val encryption = ByteArray(32) { (it + 10).toByte() }
        val challenge = decode(login["enrollmentChallenge"].asText())
        val payload = canonical(challenge, role, "android", "1.0", "Test device", signing, encryption)
        val signature =
            Signature.getInstance("Ed25519").run {
                initSign(keys.private)
                update(payload)
                sign()
            }
        return objectMapper.writeValueAsString(
            mapOf(
                "enrollmentToken" to login["enrollmentToken"].asText(),
                "role" to role,
                "platform" to "android",
                "appVersion" to "1.0",
                "displayName" to "Test device",
                "signingPublicKey" to encode(signing),
                "encryptionPublicKey" to encode(encryption),
                "proofSignature" to encode(signature),
            ),
        )
    }

    private fun refresh(token: String) =
        mockMvc.post("/v1/auth/refresh") {
            contentType = MediaType.APPLICATION_JSON
            content = """{"refreshToken":"$token"}"""
        }

    private fun canonical(
        challenge: ByteArray,
        role: String,
        platform: String,
        version: String,
        name: String,
        signing: ByteArray,
        encryption: ByteArray,
    ): ByteArray =
        CanonicalJson
            .encode(
                mapOf(
                    "appVersion" to version,
                    "challenge" to encode(challenge),
                    "displayName" to name,
                    "encryptionPublicKey" to encode(encryption),
                    "platform" to platform,
                    "purpose" to "mirrorline-device-enrollment-v1",
                    "role" to role,
                    "signingPublicKey" to encode(signing),
                ),
            ).toByteArray()

    private fun read(value: String): JsonNode = objectMapper.readTree(value)

    private fun decode(value: String): ByteArray = Base64.getUrlDecoder().decode(value)

    private fun encode(value: ByteArray): String = Base64.getUrlEncoder().withoutPadding().encodeToString(value)

    private fun uniqueEmail(): String = "identity-${System.nanoTime()}@example.test"

    private fun auditCount(
        eventType: String,
        result: String,
        correlationId: UUID? = null,
        userId: UUID? = null,
    ): Int =
        jdbcTemplate.queryForObject(
            """
            SELECT count(*) FROM security_audit_events
            WHERE event_type = ? AND result::text = ?
              AND (?::uuid IS NULL OR correlation_id = ?)
              AND (?::uuid IS NULL OR user_id = ?)
            """.trimIndent(),
            Int::class.java,
            eventType,
            result,
            correlationId,
            correlationId,
            userId,
            userId,
        )!!

    @TestConfiguration
    class MailConfiguration {
        @Bean
        @Primary
        fun recordingMailGateway() = RecordingMailGateway()
    }

    class RecordingMailGateway : AccountMailGateway {
        private val verification = mutableMapOf<String, String>()
        private val reset = mutableMapOf<String, String>()

        override fun sendVerification(
            email: String,
            rawToken: String,
        ) {
            verification[email] = rawToken
        }

        override fun sendPasswordReset(
            email: String,
            rawToken: String,
        ) {
            reset[email] = rawToken
        }

        fun verificationFor(email: String): String = verification.getValue(email)

        fun resetFor(email: String): String = reset.getValue(email)

        fun clear() {
            verification.clear()
            reset.clear()
        }
    }

    companion object {
        @Container
        @ServiceConnection
        @JvmStatic
        val postgres = PostgreSQLContainer("postgres:18-alpine")
    }
}
