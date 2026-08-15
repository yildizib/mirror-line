package io.github.yildizib.mirrorline

data class SmsPart(val address: String, val body: String, val timestampMs: Long)
data class AssembledSms(val address: String, val body: String, val timestampMs: Long) {
    val fingerprint: String = "$address\u0000$timestampMs\u0000$body"
}

object SmsAssembler {
    fun assemble(parts: List<SmsPart>): List<AssembledSms> = parts
        .groupByTo(linkedMapOf()) { it.address }
        .map { (address, messageParts) ->
            AssembledSms(
                address,
                messageParts.joinToString("") { it.body },
                messageParts.first().timestampMs,
            )
        }
}

class ExactFingerprintCache(private val capacity: Int = 64) {
    private val fingerprints = LinkedHashSet<String>()

    @Synchronized
    fun addIfNew(fingerprint: String): Boolean {
        if (!fingerprints.add(fingerprint)) return false
        while (fingerprints.size > capacity) fingerprints.remove(fingerprints.first())
        return true
    }

    @Synchronized
    fun remove(fingerprint: String) {
        fingerprints.remove(fingerprint)
    }
}
