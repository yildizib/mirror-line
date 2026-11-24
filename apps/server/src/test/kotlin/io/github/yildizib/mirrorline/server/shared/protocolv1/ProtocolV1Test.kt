package io.github.yildizib.mirrorline.server.shared.protocolv1

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import org.assertj.core.api.Assertions.assertThat
import org.assertj.core.api.Assertions.assertThatThrownBy
import org.junit.jupiter.api.Test
import java.io.File
import java.nio.charset.StandardCharsets.UTF_8
import java.util.Base64

class ProtocolV1Test {
    private val root =
        jacksonObjectMapper().readTree(File("../../protocol-fixtures/v1-golden.json"))
    private val envelope = SignedEnvelope.decode(root["envelope"].toString())

    @Test
    fun `matches protocol v1 cross-runtime golden vector`() {
        assertThat(envelope.authenticatedMetadataBytes().toString(UTF_8))
            .isEqualTo(root["aad"].textValue())
        val derivedKey =
            ProtocolCrypto.deriveDirectionalKey(
                hex(root["x25519SharedSecretHex"].textValue()),
                envelope.senderUserId,
                envelope.senderDeviceId,
                envelope.recipientUserId,
                envelope.recipientDeviceId,
                envelope.senderKeyVersion,
                envelope.recipientKeyVersion,
                envelope.messageId,
            )
        assertThat(derivedKey.toList())
            .isEqualTo(hex(root["derivedKeyHex"].textValue()).toList())
        val changedKeyVersion =
            ProtocolCrypto.deriveDirectionalKey(
                hex(root["x25519SharedSecretHex"].textValue()),
                envelope.senderUserId,
                envelope.senderDeviceId,
                envelope.recipientUserId,
                envelope.recipientDeviceId,
                envelope.senderKeyVersion + 1,
                envelope.recipientKeyVersion,
                envelope.messageId,
            )
        assertThat(changedKeyVersion.toList())
            .isNotEqualTo(hex(root["derivedKeyHex"].textValue()).toList())
        val changedMessageId =
            ProtocolCrypto.deriveDirectionalKey(
                hex(root["x25519SharedSecretHex"].textValue()),
                envelope.senderUserId,
                envelope.senderDeviceId,
                envelope.recipientUserId,
                envelope.recipientDeviceId,
                envelope.senderKeyVersion,
                envelope.recipientKeyVersion,
                "other-message",
            )
        assertThat(changedMessageId.toList())
            .isNotEqualTo(hex(root["derivedKeyHex"].textValue()).toList())
        val x25519SharedSecret =
            ProtocolCrypto.x25519SharedSecret(
                hex(root["x25519AlicePrivateKeyHex"].textValue()),
                hex(root["x25519BobPublicKeyHex"].textValue()),
            )
        assertThat(x25519SharedSecret.toList())
            .isEqualTo(hex(root["x25519SharedSecretHex"].textValue()).toList())
        val encrypted =
            ProtocolCrypto.encryptAesGcm(
                hex(root["derivedKeyHex"].textValue()),
                root["plaintext"].textValue().toByteArray(UTF_8),
                envelope,
            )
        assertThat(Base64.getEncoder().encodeToString(encrypted.ciphertext + encrypted.tag))
            .isEqualTo(root["envelope"]["ciphertext"].textValue())
        val decrypted =
            ProtocolCrypto.decryptAesGcm(hex(root["derivedKeyHex"].textValue()), envelope).toString(UTF_8)
        assertThat(decrypted).isEqualTo(root["plaintext"].textValue())
        val signed =
            ProtocolCrypto.signEnvelope(
                envelope.copy(signature = ""),
                hex(root["ed25519PrivateKeyHex"].textValue()),
            )
        assertThat(signed.signature).isEqualTo(envelope.signature)
        assertThat(
            ProtocolCrypto.verifyEnvelope(envelope, hex(root["ed25519PublicKeyHex"].textValue())),
        ).isTrue()
    }

    @Test
    fun `rejects altered values and bounded invalid inputs`() {
        val key = hex(root["derivedKeyHex"].textValue())
        val publicKey = hex(root["ed25519PublicKeyHex"].textValue())
        val altered =
            listOf(
                envelope.copy(signature = envelope.signature.dropLast(1) + "A"),
                envelope.copy(senderUserId = "other-user"),
                envelope.copy(senderDeviceId = "other-device"),
                envelope.copy(senderKeyVersion = envelope.senderKeyVersion + 1),
                envelope.copy(messageId = "other-message"),
                envelope.copy(nonce = "AAECAwQFBgcICQoM"),
                envelope.copy(ciphertext = "AttAwGcWtZTX1IdggN0ouSZ4e2c95qRZykiZqdvsLCmOVr4="),
            )
        altered.forEach {
            assertThat(ProtocolCrypto.verifyEnvelope(it, publicKey)).isFalse()
            assertThatThrownBy { ProtocolCrypto.decryptAesGcm(key, it) }
                .isInstanceOf(ProtocolException::class.java)
        }
        assertThatThrownBy {
            SignedEnvelope.decode(envelope.copy(protocolVersion = 2).encode())
        }.extracting("code")
            .isEqualTo(ProtocolErrorCode.UNSUPPORTED_VERSION)
        assertThatThrownBy {
            SignedEnvelope.decode(envelope.encode().replace(envelope.nonce, "!!!"))
        }.isInstanceOf(ProtocolException::class.java)
        assertThatThrownBy {
            SignedEnvelope.decode(envelope.encode() + " ".repeat(SignedEnvelope.MAX_ENCODED_SIZE))
        }.extracting("code")
            .isEqualTo(ProtocolErrorCode.OVERSIZED_INPUT)
    }

    private fun hex(value: String): ByteArray = value.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
}
