package io.github.yildizib.mirrorline.server.bootstrap

import com.fasterxml.jackson.databind.ObjectMapper
import io.github.yildizib.mirrorline.server.identity.BearerAuthenticationFilter
import io.github.yildizib.mirrorline.server.shared.ApiError
import io.github.yildizib.mirrorline.server.shared.CorrelationIdFilter
import io.github.yildizib.mirrorline.server.shared.CorrelationIds
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.http.MediaType
import org.springframework.security.config.annotation.web.builders.HttpSecurity
import org.springframework.security.config.http.SessionCreationPolicy
import org.springframework.security.web.SecurityFilterChain
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter

@Configuration
class SecurityConfiguration(
    private val bearerAuthenticationFilter: BearerAuthenticationFilter,
    private val correlationIdFilter: CorrelationIdFilter,
    private val objectMapper: ObjectMapper,
) {
    @Bean
    fun securityFilterChain(http: HttpSecurity): SecurityFilterChain =
        http
            .csrf { it.disable() }
            .sessionManagement { it.sessionCreationPolicy(SessionCreationPolicy.STATELESS) }
            .addFilterBefore(correlationIdFilter, UsernamePasswordAuthenticationFilter::class.java)
            .addFilterAfter(bearerAuthenticationFilter, CorrelationIdFilter::class.java)
            .exceptionHandling {
                it.authenticationEntryPoint { _, response, _ ->
                    response.status = 401
                    response.contentType = MediaType.APPLICATION_JSON_VALUE
                    objectMapper.writeValue(
                        response.outputStream,
                        ApiError("AUTH_SESSION_EXPIRED", "Session is unavailable.", CorrelationIds.current()),
                    )
                }
            }.authorizeHttpRequests {
                it
                    .requestMatchers(
                        "/actuator/health",
                        "/actuator/health/**",
                        "/v1/auth/register",
                        "/v1/auth/verify-email",
                        "/v1/auth/login",
                        "/v1/auth/refresh",
                        "/v1/auth/forgot-password",
                        "/v1/auth/reset-password",
                        "/v1/devices/enroll",
                    ).permitAll()
                it.requestMatchers("/v1/**").authenticated()
                it.anyRequest().denyAll()
            }.build()
}
