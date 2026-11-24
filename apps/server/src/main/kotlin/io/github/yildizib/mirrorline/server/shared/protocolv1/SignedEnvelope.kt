package io.github.yildizib.mirrorline.server.shared.protocolv1

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import java.nio.charset.StandardCharsets.UTF_8
import java.util.Base64

data class SignedEnvelope(
    val protocolVersion: Int,
    val senderUserId: String,
    val senderDeviceId: String,
    val recipientUserId: String,
    val recipientDeviceId: String,
    val senderKeyVersion: Int,
    val recipientKeyVersion: Int,
    val messageId: String,
    val messageType: String,
    val createdAt: Long,
    val nonce: String,
    val ciphertext: String,
    val signature: String,
) {
    fun authenticatedMetadataBytes(): ByteArray =
        CanonicalJson
            .encode(
                mapOf(
                    "createdAt" to createdAt,
                    "messageId" to messageId,
                    "messageType" to messageType,
                    "nonce" to nonce,
                    "protocolVersion" to protocolVersion,
                    "recipientDeviceId" to recipientDeviceId,
                    "recipientKeyVersion" to recipientKeyVersion,
                    "recipientUserId" to recipientUserId,
                    "senderDeviceId" to senderDeviceId,
                    "senderKeyVersion" to senderKeyVersion,
                    "senderUserId" to senderUserId,
                ),
            ).toByteArray(UTF_8)

    fun signingBytes(): ByteArray = domainSeparatedBytes("mirrorline.envelope.v1", unsignedValues())

    fun encode(): String = CanonicalJson.encode(unsignedValues() + ("signature" to signature))

    fun nonceBytes(): ByteArray = decodeBase64(nonce, NONCE_LENGTH, "nonce", exact = true)

    fun ciphertextBytes(): ByteArray = decodeBase64(ciphertext, MAX_CIPHERTEXT_SIZE, "ciphertext")

    fun signatureBytes(): ByteArray = decodeBase64(signature, SIGNATURE_LENGTH, "signature", exact = true)

    fun validate(requireSignature: Boolean = true) {
        if (protocolVersion != VERSION) {
            throw ProtocolException(ProtocolErrorCode.UNSUPPORTED_VERSION, "Unsupported protocol version.")
        }
        listOf(senderUserId, senderDeviceId, recipientUserId, recipientDeviceId, messageId, messageType).forEach {
            if (it.isEmpty() || it.length > MAX_IDENTIFIER_LENGTH) malformed()
        }
        if (senderKeyVersion < 1 || recipientKeyVersion < 1 || createdAt < 0) malformed()
        nonceBytes()
        val encrypted = ciphertextBytes()
        if (requireSignature && encrypted.size < 16) malformed()
        if (requireSignature) signatureBytes()
    }

    private fun unsignedValues(): Map<String, Any> =
        mapOf(
            "ciphertext" to ciphertext,
            "createdAt" to createdAt,
            "messageId" to messageId,
            "messageType" to messageType,
            "nonce" to nonce,
            "protocolVersion" to protocolVersion,
            "recipientDeviceId" to recipientDeviceId,
            "recipientKeyVersion" to recipientKeyVersion,
            "recipientUserId" to recipientUserId,
            "senderDeviceId" to senderDeviceId,
            "senderKeyVersion" to senderKeyVersion,
            "senderUserId" to senderUserId,
        )

    companion object {
        const val VERSION = 1
        const val MAX_ENCODED_SIZE = 16 * 1024
        const val MAX_CIPHERTEXT_SIZE = 8 * 1024
        const val NONCE_LENGTH = 12
        const val SIGNATURE_LENGTH = 64
        private const val MAX_IDENTIFIER_LENGTH = 256
        private val base64Pattern = Regex("^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$")
        private val mapper = jacksonObjectMapper()
        private val requiredFields =
            setOf(
                "protocolVersion",
                "senderUserId",
                "senderDeviceId",
                "recipientUserId",
                "recipientDeviceId",
                "senderKeyVersion",
                "recipientKeyVersion",
                "messageId",
                "messageType",
                "createdAt",
                "nonce",
                "ciphertext",
                "signature",
            )

        fun decode(encoded: String): SignedEnvelope {
            if (encoded.length > MAX_ENCODED_SIZE) {
                throw ProtocolException(ProtocolErrorCode.OVERSIZED_INPUT, "Envelope exceeds the protocol size limit.")
            }
            try {
                val root = mapper.readTree(encoded)
                if (!root.isObject || root.fieldNames().asSequence().toSet() != requiredFields) malformed()
                val envelope =
                    SignedEnvelope(
                        protocolVersion = int(root, "protocolVersion"),
                        senderUserId = string(root, "senderUserId"),
                        senderDeviceId = string(root, "senderDeviceId"),
                        recipientUserId = string(root, "recipientUserId"),
                        recipientDeviceId = string(root, "recipientDeviceId"),
                        senderKeyVersion = int(root, "senderKeyVersion"),
                        recipientKeyVersion = int(root, "recipientKeyVersion"),
                        messageId = string(root, "messageId"),
                        messageType = string(root, "messageType"),
                        createdAt = long(root, "createdAt"),
                        nonce = string(root, "nonce"),
                        ciphertext = string(root, "ciphertext"),
                        signature = string(root, "signature"),
                    )
                envelope.validate()
                return envelope
            } catch (exception: ProtocolException) {
                throw exception
            } catch (_: Exception) {
                malformed()
            }
        }

        internal fun domainSeparatedBytes(
            domain: String,
            values: Map<String, Any>,
        ): ByteArray = (domain.toByteArray(UTF_8) + byteArrayOf(0) + CanonicalJson.encode(values).toByteArray(UTF_8))

        private fun string(
            root: com.fasterxml.jackson.databind.JsonNode,
            name: String,
        ): String = root[name]?.takeIf { it.isTextual }?.textValue() ?: malformed()

        private fun int(
            root: com.fasterxml.jackson.databind.JsonNode,
            name: String,
        ): Int = root[name]?.takeIf { it.isInt }?.intValue() ?: malformed()

        private fun long(
            root: com.fasterxml.jackson.databind.JsonNode,
            name: String,
        ): Long = root[name]?.takeIf { it.isIntegralNumber }?.longValue() ?: malformed()

        private fun decodeBase64(
            value: String,
            maxLength: Int,
            field: String,
            exact: Boolean = false,
        ): ByteArray {
            if (value.length > ((maxLength + 2) / 3) * 4) {
                throw ProtocolException(ProtocolErrorCode.OVERSIZED_INPUT, "$field exceeds the protocol size limit.")
            }
            if (!base64Pattern.matches(value)) malformed()
            val decoded =
                try {
                    Base64.getDecoder().decode(value)
                } catch (_: IllegalArgumentException) {
                    malformed()
                }
            if (decoded.size > maxLength) {
                throw ProtocolException(ProtocolErrorCode.OVERSIZED_INPUT, "$field exceeds the protocol size limit.")
            }
            if (exact && decoded.size != maxLength) {
                throw ProtocolException(ProtocolErrorCode.MALFORMED_INPUT, "Invalid $field length.")
            }
            return decoded
        }

        private fun malformed(): Nothing = throw ProtocolException(ProtocolErrorCode.MALFORMED_INPUT, "Malformed protocol envelope.")
    }
}
