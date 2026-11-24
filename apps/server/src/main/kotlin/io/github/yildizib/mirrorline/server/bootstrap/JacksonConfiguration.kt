package io.github.yildizib.mirrorline.server.bootstrap

import com.fasterxml.jackson.databind.DeserializationFeature
import com.fasterxml.jackson.databind.ObjectMapper
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration

@Configuration
class JacksonConfiguration {
    /**
     * The server protocol still uses Jackson 2 (`com.fasterxml`) while Boot 4's web
     * stack supplies Jackson 3 (`tools.jackson`). Keep this mapper explicit until
     * the protocol implementation is migrated as one compatible unit.
     */
    @Bean
    fun objectMapper(): ObjectMapper =
        ObjectMapper()
            .findAndRegisterModules()
            .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, true)
}
