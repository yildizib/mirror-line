package io.github.yildizib.mirrorline.server.identity

import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Repository
import java.util.UUID

/** Low-level identity storage primitive; authentication flows are deliberately deferred. */
@Repository
class UserPersistenceRepository(
    private val jdbcTemplate: JdbcTemplate,
) {
    fun createUser(): UUID =
        jdbcTemplate.queryForObject(
            "INSERT INTO users DEFAULT VALUES RETURNING user_id",
            UUID::class.java,
        )!!
}
