package io.github.yildizib.mirrorline.server.identity

import com.fasterxml.jackson.databind.ObjectMapper
import io.github.yildizib.mirrorline.server.shared.ApiError
import io.github.yildizib.mirrorline.server.shared.CorrelationIds
import jakarta.servlet.FilterChain
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.springframework.http.MediaType
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken
import org.springframework.security.core.authority.AuthorityUtils
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.security.core.userdetails.UserDetails
import org.springframework.stereotype.Component
import org.springframework.web.filter.OncePerRequestFilter
import java.util.UUID

data class AuthenticatedPrincipal(
    val userId: UUID,
    val deviceId: UUID,
    val sessionId: UUID,
    val deviceStatus: String = "ACTIVE",
) : UserDetails {
    override fun getAuthorities() = AuthorityUtils.NO_AUTHORITIES

    override fun getPassword() = ""

    override fun getUsername() = userId.toString()

    override fun isAccountNonExpired() = true

    override fun isAccountNonLocked() = true

    override fun isCredentialsNonExpired() = true

    override fun isEnabled() = true
}

@Component
class BearerAuthenticationFilter(
    private val accounts: AccountFacade,
    private val objectMapper: ObjectMapper,
) : OncePerRequestFilter() {
    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain,
    ) {
        val header = request.getHeader("Authorization")
        if (header?.startsWith("Bearer ") == true) {
            val session = accounts.authenticate(header.removePrefix("Bearer "))
            if (session == null) {
                response.status = HttpServletResponse.SC_UNAUTHORIZED
                response.contentType = MediaType.APPLICATION_JSON_VALUE
                objectMapper.writeValue(
                    response.outputStream,
                    ApiError("AUTH_SESSION_EXPIRED", "Session is unavailable.", CorrelationIds.current()),
                )
                return
            }
            val path = request.requestURI.substringBefore('?')
            val pairingRoute = path == "/v1/pairings" || path.startsWith("/v1/pairings/")
            if (session.deviceStatus != "ACTIVE" && !pairingRoute) {
                response.status = HttpServletResponse.SC_FORBIDDEN
                response.contentType = MediaType.APPLICATION_JSON_VALUE
                objectMapper.writeValue(
                    response.outputStream,
                    ApiError("AUTH_FORBIDDEN", "The request is not permitted.", CorrelationIds.current()),
                )
                return
            }
            val principal = AuthenticatedPrincipal(session.userId, session.deviceId, session.sessionId, session.deviceStatus)
            SecurityContextHolder.getContext().authentication = UsernamePasswordAuthenticationToken(principal, null, principal.authorities)
        }
        filterChain.doFilter(request, response)
    }
}
