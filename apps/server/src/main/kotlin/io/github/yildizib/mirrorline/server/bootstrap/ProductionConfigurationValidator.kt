package io.github.yildizib.mirrorline.server.bootstrap

import org.springframework.boot.ApplicationArguments
import org.springframework.boot.ApplicationRunner
import org.springframework.context.annotation.Profile
import org.springframework.stereotype.Component
import java.util.Base64

@Component
@Profile("prod")
class ProductionConfigurationValidator(
    private val properties: MirrorLineProperties,
) : ApplicationRunner {
    override fun run(args: ApplicationArguments) {
        require(properties.publicDomain.isNotBlank()) {
            "MIRRORLINE_PUBLIC_DOMAIN must be configured in the prod profile"
        }
        val pairingKeyLength = runCatching { Base64.getUrlDecoder().decode(properties.pairingCodeHmacKey) }.getOrNull()?.size ?: 0
        require(pairingKeyLength >= 32) {
            "MIRRORLINE_PAIRING_CODE_HMAC_KEY must be a base64url value of at least 32 bytes in the prod profile"
        }
    }
}
