package io.github.yildizib.mirrorline.server.identity

import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.jdbc.core.RowMapper
import org.springframework.stereotype.Repository
import java.sql.ResultSet
import java.time.OffsetDateTime
import java.util.UUID

data class AccountRecord(
    val userId: UUID,
    val email: String,
    val passwordHash: String,
    val verifiedAt: OffsetDateTime?,
    val status: String,
)

data class ActionTokenRecord(
    val userId: UUID,
    val challenge: ByteArray?,
)

@Repository
class AccountRepository(
    private val jdbcTemplate: JdbcTemplate,
) {
    fun create(
        email: String,
        passwordHash: String,
    ): UUID? =
        jdbcTemplate
            .query(
                """
                INSERT INTO users (email_normalized, password_hash)
                VALUES (?, ?)
                ON CONFLICT (email_normalized) WHERE email_normalized IS NOT NULL DO NOTHING
                RETURNING user_id
                """.trimIndent(),
                RowMapper { result, _ -> result.getObject("user_id", UUID::class.java) },
                email,
                passwordHash,
            ).firstOrNull()

    fun findByEmail(email: String): AccountRecord? =
        jdbcTemplate
            .query(
                """
                SELECT user_id, email_normalized, password_hash, email_verified_at, status::text
                FROM users WHERE email_normalized = ?
                """.trimIndent(),
                accountMapper,
                email,
            ).firstOrNull()

    fun markEmailVerified(userId: UUID) {
        jdbcTemplate.update(
            "UPDATE users SET email_verified_at = COALESCE(email_verified_at, CURRENT_TIMESTAMP) WHERE user_id = ?",
            userId,
        )
    }

    fun updatePassword(
        userId: UUID,
        passwordHash: String,
    ) {
        jdbcTemplate.update("UPDATE users SET password_hash = ? WHERE user_id = ?", passwordHash, userId)
    }

    fun recordSuccessfulLogin(userId: UUID) {
        jdbcTemplate.update("UPDATE users SET last_successful_login_at = CURRENT_TIMESTAMP WHERE user_id = ?", userId)
    }

    private companion object {
        val accountMapper =
            RowMapper { result: ResultSet, _: Int ->
                AccountRecord(
                    result.getObject("user_id", UUID::class.java),
                    result.getString("email_normalized"),
                    result.getString("password_hash"),
                    result.getObject("email_verified_at", OffsetDateTime::class.java),
                    result.getString("status"),
                )
            }
    }
}

@Repository
class AccountActionTokenRepository(
    private val jdbcTemplate: JdbcTemplate,
) {
    fun create(
        userId: UUID,
        kind: String,
        tokenHash: ByteArray,
        expiresAt: OffsetDateTime,
        challenge: ByteArray? = null,
    ) {
        jdbcTemplate.update(
            """
            INSERT INTO account_action_tokens (user_id, kind, token_hash, challenge, expires_at)
            VALUES (?, CAST(? AS account_token_kind), ?, ?, ?)
            """.trimIndent(),
            userId,
            kind,
            tokenHash,
            challenge,
            expiresAt,
        )
    }

    fun findActive(
        kind: String,
        tokenHash: ByteArray,
    ): ActionTokenRecord? =
        jdbcTemplate
            .query(
                """
                SELECT user_id, challenge FROM account_action_tokens
                WHERE kind = CAST(? AS account_token_kind) AND token_hash = ?
                  AND consumed_at IS NULL AND expires_at > CURRENT_TIMESTAMP
                """.trimIndent(),
                RowMapper { result, _ ->
                    ActionTokenRecord(result.getObject("user_id", UUID::class.java), result.getBytes("challenge"))
                },
                kind,
                tokenHash,
            ).firstOrNull()

    fun consume(
        kind: String,
        tokenHash: ByteArray,
    ): ActionTokenRecord? =
        jdbcTemplate
            .query(
                """
                UPDATE account_action_tokens SET consumed_at = CURRENT_TIMESTAMP
                WHERE kind = CAST(? AS account_token_kind) AND token_hash = ?
                  AND consumed_at IS NULL AND expires_at > CURRENT_TIMESTAMP
                RETURNING user_id, challenge
                """.trimIndent(),
                RowMapper { result, _ ->
                    ActionTokenRecord(result.getObject("user_id", UUID::class.java), result.getBytes("challenge"))
                },
                kind,
                tokenHash,
            ).firstOrNull()
}
