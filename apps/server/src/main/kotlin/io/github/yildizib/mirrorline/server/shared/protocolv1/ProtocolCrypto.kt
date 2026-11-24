package io.github.yildizib.mirrorline.server.shared.protocolv1

import java.nio.charset.StandardCharsets.UTF_8
import java.security.KeyFactory
import java.security.PrivateKey
import java.security.PublicKey
import java.security.Signature
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

data class ProtocolCiphertext(
    val ciphertext: ByteArray,
    val tag: ByteArray,
)

/** Java 21/JCA implementation of the protocol-v1 cryptographic primitives. */
object ProtocolCrypto {
    private val ed25519PublicPrefix = hex("302a300506032b6570032100")
    private val ed25519PrivatePrefix = hex("302e020100300506032b657004220420")
    private val x25519PublicPrefix = hex("302a300506032b656e032100")
    private val x25519PrivatePrefix = hex("302e020100300506032b656e04220420")

    fun signEnvelope(
        envelope: SignedEnvelope,
        privateKey: ByteArray,
    ): SignedEnvelope {
        envelope.validate(requireSignature = false)
        val signer = Signature.getInstance("Ed25519")
        signer.initSign(ed25519PrivateKey(privateKey))
        signer.update(envelope.signingBytes())
        return envelope.copy(signature = Base64.getEncoder().encodeToString(signer.sign()))
    }

    fun verifyEnvelope(
        envelope: SignedEnvelope,
        publicKey: ByteArray,
    ): Boolean =
        try {
            envelope.validate()
            val verifier = Signature.getInstance("Ed25519")
            verifier.initVerify(ed25519PublicKey(publicKey))
            verifier.update(envelope.signingBytes())
            verifier.verify(envelope.signatureBytes())
        } catch (_: ProtocolException) {
            false
        } catch (_: Exception) {
            false
        }

    fun x25519SharedSecret(
        privateKey: ByteArray,
        publicKey: ByteArray,
    ): ByteArray {
        val agreement = KeyAgreement.getInstance("X25519")
        agreement.init(x25519PrivateKey(privateKey))
        agreement.doPhase(x25519PublicKey(publicKey), true)
        return agreement.generateSecret()
    }

    fun deriveDirectionalKey(
        sharedSecret: ByteArray,
        senderUserId: String,
        senderDeviceId: String,
        recipientUserId: String,
        recipientDeviceId: String,
        senderKeyVersion: Int,
        recipientKeyVersion: Int,
        messageId: String,
    ): ByteArray {
        exactKey(sharedSecret)
        val info =
            "mirrorline.envelope.v1.hkdf\u0000".toByteArray(UTF_8) +
                CanonicalJson
                    .encode(
                        mapOf(
                            "messageId" to messageId,
                            "recipientDeviceId" to recipientDeviceId,
                            "recipientKeyVersion" to recipientKeyVersion,
                            "recipientUserId" to recipientUserId,
                            "senderDeviceId" to senderDeviceId,
                            "senderKeyVersion" to senderKeyVersion,
                            "senderUserId" to senderUserId,
                        ),
                    ).toByteArray(UTF_8)
        val prk = hmacSha256(ByteArray(32), sharedSecret)
        return hmacSha256(prk, info + byteArrayOf(1)).copyOf(32)
    }

    fun encryptAesGcm(
        key: ByteArray,
        plaintext: ByteArray,
        envelope: SignedEnvelope,
    ): ProtocolCiphertext {
        envelope.validate(requireSignature = false)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, aes256Key(key), GCMParameterSpec(128, envelope.nonceBytes()))
        cipher.updateAAD(envelope.authenticatedMetadataBytes())
        val joined = cipher.doFinal(plaintext)
        return ProtocolCiphertext(joined.copyOfRange(0, joined.size - 16), joined.copyOfRange(joined.size - 16, joined.size))
    }

    fun decryptAesGcm(
        key: ByteArray,
        envelope: SignedEnvelope,
    ): ByteArray =
        try {
            envelope.validate()
            val joined = envelope.ciphertextBytes()
            if (joined.size < 16) malformedCiphertext()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, aes256Key(key), GCMParameterSpec(128, envelope.nonceBytes()))
            cipher.updateAAD(envelope.authenticatedMetadataBytes())
            cipher.doFinal(joined)
        } catch (exception: ProtocolException) {
            throw exception
        } catch (_: Exception) {
            throw ProtocolException(ProtocolErrorCode.AUTHENTICATION_FAILED, "Envelope authentication failed.")
        }

    fun pairingTranscriptBytes(payload: Map<String, Any>): ByteArray = domainSeparatedBytes("mirrorline.pairing.v1", payload)

    fun keyRotationPayloadBytes(payload: Map<String, Any>): ByteArray = domainSeparatedBytes("mirrorline.key-rotation.v1", payload)

    private fun domainSeparatedBytes(
        domain: String,
        payload: Map<String, Any>,
    ): ByteArray = domain.toByteArray(UTF_8) + byteArrayOf(0) + CanonicalJson.encode(payload).toByteArray(UTF_8)

    private fun hmacSha256(
        key: ByteArray,
        input: ByteArray,
    ): ByteArray =
        Mac.getInstance("HmacSHA256").run {
            init(SecretKeySpec(key, "HmacSHA256"))
            doFinal(input)
        }

    private fun ed25519PrivateKey(raw: ByteArray): PrivateKey =
        KeyFactory.getInstance("Ed25519").generatePrivate(PKCS8EncodedKeySpec(ed25519PrivatePrefix + exactKey(raw)))

    private fun ed25519PublicKey(raw: ByteArray): PublicKey =
        KeyFactory.getInstance("Ed25519").generatePublic(X509EncodedKeySpec(ed25519PublicPrefix + exactKey(raw)))

    private fun x25519PrivateKey(raw: ByteArray): PrivateKey =
        KeyFactory.getInstance("X25519").generatePrivate(PKCS8EncodedKeySpec(x25519PrivatePrefix + exactKey(raw)))

    private fun x25519PublicKey(raw: ByteArray): PublicKey =
        KeyFactory.getInstance("X25519").generatePublic(X509EncodedKeySpec(x25519PublicPrefix + exactKey(raw)))

    private fun exactKey(raw: ByteArray): ByteArray {
        if (raw.size != 32) throw ProtocolException(ProtocolErrorCode.MALFORMED_INPUT, "Invalid key length.")
        return raw
    }

    private fun aes256Key(raw: ByteArray): SecretKeySpec = SecretKeySpec(exactKey(raw), "AES")

    private fun malformedCiphertext(): Nothing =
        throw ProtocolException(ProtocolErrorCode.MALFORMED_INPUT, "Ciphertext is missing an authentication tag.")

    private fun hex(value: String): ByteArray = value.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
}
