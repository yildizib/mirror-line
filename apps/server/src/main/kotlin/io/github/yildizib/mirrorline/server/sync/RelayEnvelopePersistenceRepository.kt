package io.github.yildizib.mirrorline.server.sync

import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Repository
import java.time.OffsetDateTime
import java.util.UUID

/** Persists opaque relay envelopes and removes payload bytes after a recipient acknowledgement. */
@Repository
class RelayEnvelopePersistenceRepository(
    private val jdbcTemplate: JdbcTemplate,
) {
    fun accept(input: RelayEnvelopeInput): RelayEnvelopeAcceptance {
        val insertedEnvelopeId =
            jdbcTemplate
                .query(
                    """
                    INSERT INTO relay_envelopes (
                        sender_user_id,
                        sender_device_id,
                        recipient_user_id,
                        recipient_device_id,
                        message_id,
                        protocol_version,
                        message_type,
                        client_created_at,
                        sender_key_version,
                        recipient_key_version,
                        nonce,
                        ciphertext,
                        associated_data,
                        signature,
                        envelope_digest
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT (sender_user_id, sender_device_id, message_id) DO NOTHING
                    RETURNING envelope_id
                    """.trimIndent(),
                    { resultSet, _ -> resultSet.getObject("envelope_id", UUID::class.java) },
                    input.senderUserId,
                    input.senderDeviceId,
                    input.recipientUserId,
                    input.recipientDeviceId,
                    input.messageId,
                    input.protocolVersion,
                    input.messageType,
                    input.clientCreatedAt,
                    input.senderKeyVersion,
                    input.recipientKeyVersion,
                    input.nonce,
                    input.ciphertext,
                    input.associatedData,
                    input.signature,
                    input.envelopeDigest,
                ).singleOrNull()

        if (insertedEnvelopeId != null) {
            return RelayEnvelopeAcceptance(insertedEnvelopeId, idempotent = false)
        }
        val existing =
            jdbcTemplate.queryForMap(
                """
                SELECT envelope_id, envelope_digest
                FROM relay_envelopes
                WHERE sender_user_id = ?
                  AND sender_device_id = ?
                  AND message_id = ?
                """.trimIndent(),
                input.senderUserId,
                input.senderDeviceId,
                input.messageId,
            )
        val existingDigest = existing.getValue("envelope_digest") as ByteArray
        check(existingDigest.contentEquals(input.envelopeDigest)) {
            "message ID is already bound to a different envelope"
        }
        return RelayEnvelopeAcceptance(existing.getValue("envelope_id") as UUID, idempotent = true)
    }

    fun acknowledgeAndPurge(envelopeId: UUID): Int =
        jdbcTemplate.update(
            """
            UPDATE relay_envelopes
            SET status = 'ACKNOWLEDGED',
                acknowledged_at = CURRENT_TIMESTAMP,
                payload_purged_at = CURRENT_TIMESTAMP,
                nonce = NULL,
                ciphertext = NULL,
                associated_data = NULL,
                signature = NULL
            WHERE envelope_id = ?
              AND payload_purged_at IS NULL
            """.trimIndent(),
            envelopeId,
        )
}

data class RelayEnvelopeInput(
    val senderUserId: UUID,
    val senderDeviceId: UUID,
    val recipientUserId: UUID,
    val recipientDeviceId: UUID,
    val messageId: UUID,
    val protocolVersion: Short,
    val messageType: String,
    val clientCreatedAt: OffsetDateTime,
    val senderKeyVersion: Int,
    val recipientKeyVersion: Int,
    val nonce: ByteArray,
    val ciphertext: ByteArray,
    val associatedData: ByteArray?,
    val signature: ByteArray,
    val envelopeDigest: ByteArray,
)

data class RelayEnvelopeAcceptance(
    val envelopeId: UUID,
    val idempotent: Boolean,
)
