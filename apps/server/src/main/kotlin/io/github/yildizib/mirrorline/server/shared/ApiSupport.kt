package io.github.yildizib.mirrorline.server.shared

import jakarta.servlet.FilterChain
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.http.converter.HttpMessageNotReadableException
import org.springframework.stereotype.Component
import org.springframework.web.bind.MethodArgumentNotValidException
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice
import org.springframework.web.filter.OncePerRequestFilter
import java.util.UUID

object CorrelationIds {
    private val current = ThreadLocal<UUID>()

    fun current(): UUID = current.get() ?: UUID.randomUUID()

    fun clear() = current.remove()

    fun set(value: UUID) = current.set(value)
}

@Component
class CorrelationIdFilter : OncePerRequestFilter() {
    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain,
    ) {
        val correlationId = request.getHeader("X-Correlation-Id")?.let(::parseUuid) ?: UUID.randomUUID()
        CorrelationIds.set(correlationId)
        response.setHeader("X-Correlation-Id", correlationId.toString())
        try {
            filterChain.doFilter(request, response)
        } finally {
            CorrelationIds.clear()
        }
    }

    private fun parseUuid(value: String): UUID? = runCatching { UUID.fromString(value) }.getOrNull()
}

data class ApiError(
    val code: String,
    val message: String,
    val correlationId: UUID,
    val fieldDetails: Map<String, String>? = null,
)

class ApiException(
    val status: HttpStatus,
    val code: String,
    override val message: String,
    val fields: Map<String, String>? = null,
) : RuntimeException(message)

@RestControllerAdvice
class ApiExceptionHandler {
    @ExceptionHandler(MethodArgumentNotValidException::class, HttpMessageNotReadableException::class)
    fun invalidRequest(): ResponseEntity<ApiError> =
        ResponseEntity.status(HttpStatus.BAD_REQUEST).body(
            ApiError("VALIDATION_FAILED", "The request is not valid.", CorrelationIds.current()),
        )

    @ExceptionHandler(ApiException::class)
    fun apiException(exception: ApiException): ResponseEntity<ApiError> =
        ResponseEntity.status(exception.status).body(
            ApiError(exception.code, exception.message, CorrelationIds.current(), exception.fields),
        )

    @ExceptionHandler(Exception::class)
    fun unknown(): ResponseEntity<ApiError> =
        ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(
            ApiError("SERVICE_UNAVAILABLE", "The service could not complete the request.", CorrelationIds.current()),
        )
}
