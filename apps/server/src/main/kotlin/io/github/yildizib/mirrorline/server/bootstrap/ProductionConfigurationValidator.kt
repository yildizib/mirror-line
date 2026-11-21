package io.github.yildizib.mirrorline.server.bootstrap

import org.springframework.boot.ApplicationArguments
import org.springframework.boot.ApplicationRunner
import org.springframework.context.annotation.Profile
import org.springframework.stereotype.Component

@Component
@Profile("prod")
class ProductionConfigurationValidator(
    private val properties: MirrorLineProperties,
) : ApplicationRunner {
    override fun run(args: ApplicationArguments) {
        require(properties.publicDomain.isNotBlank()) {
            "MIRRORLINE_PUBLIC_DOMAIN must be configured in the prod profile"
        }
    }
}
