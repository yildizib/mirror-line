package io.github.yildizib.mirrorline

class KeyedDrainQueue<K, V> {
    private val entries = LinkedHashMap<K, V>()

    @Synchronized
    fun put(key: K, value: V) {
        entries[key] = value
    }

    @Synchronized
    fun poll(): V? {
        val first = entries.entries.firstOrNull() ?: return null
        entries.remove(first.key)
        return first.value
    }

    @Synchronized
    fun clear() = entries.clear()

    @Synchronized
    fun isEmpty(): Boolean = entries.isEmpty()

    @Synchronized
    fun size(): Int = entries.size
}
