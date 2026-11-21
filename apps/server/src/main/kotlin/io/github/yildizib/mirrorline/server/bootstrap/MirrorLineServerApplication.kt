package io.github.yildizib.mirrorline.server.bootstrap

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.context.properties.ConfigurationPropertiesScan
import org.springframework.boot.runApplication

@SpringBootApplication(scanBasePackages = ["io.github.yildizib.mirrorline.server"])
@ConfigurationPropertiesScan("io.github.yildizib.mirrorline.server")
class MirrorLineServerApplication

fun main(args: Array<String>) {
    runApplication<MirrorLineServerApplication>(*args)
}
