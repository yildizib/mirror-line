package io.github.yildizib.mirrorline.server.bootstrap

import org.springframework.boot.context.properties.ConfigurationProperties

@ConfigurationProperties("mirrorline")
data class MirrorLineProperties(
    val publicDomain: String = "",
    val pairingCodeHmacKey: String = "",
)
