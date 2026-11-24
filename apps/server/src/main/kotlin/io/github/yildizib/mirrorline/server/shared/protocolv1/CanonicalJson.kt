package io.github.yildizib.mirrorline.server.shared.protocolv1

/**
 * RFC 8785-compatible serialization for the protocol's deliberately limited
 * value domain. Floating point values are excluded from signed protocol data.
 */
object CanonicalJson {
    fun encode(value: Any?): String = buildString { write(value) }

    private fun StringBuilder.write(value: Any?) {
        when (value) {
            null -> append("null")
            is Boolean -> append(if (value) "true" else "false")
            is Byte, is Short, is Int, is Long -> append(value.toString())
            is String -> appendJsonString(value)
            is List<*> -> {
                append('[')
                value.forEachIndexed { index, element ->
                    if (index > 0) append(',')
                    write(element)
                }
                append(']')
            }
            is Map<*, *> -> {
                if (value.keys.any { it !is String }) malformed()
                append('{')
                value.keys.filterIsInstance<String>().sorted().forEachIndexed { index, key ->
                    if (index > 0) append(',')
                    appendJsonString(key)
                    append(':')
                    write(value[key])
                }
                append('}')
            }
            is Float, is Double -> malformed()
            else -> malformed()
        }
    }

    private fun StringBuilder.appendJsonString(value: String) {
        append('"')
        value.forEach { character ->
            when (character) {
                '"' -> append("\\\"")
                '\\' -> append("\\\\")
                '\b' -> append("\\b")
                '\u000c' -> append("\\f")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> {
                    if (character.code < 0x20) {
                        append("\\u")
                        append(character.code.toString(16).padStart(4, '0'))
                    } else {
                        append(character)
                    }
                }
            }
        }
        append('"')
    }

    private fun malformed(): Nothing = throw ProtocolException(ProtocolErrorCode.MALFORMED_INPUT, "Unsupported protocol JSON value.")
}
