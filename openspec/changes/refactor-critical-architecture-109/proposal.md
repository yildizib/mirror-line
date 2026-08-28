# Refactor critical Clean Architecture boundaries

Issue #109 kapsamında UI, domain ve infrastructure bağımlılıklarını sınırlandırırken mevcut socket protokolü, persistence formatı ve veritabanı şeması korunur.

Kapsam; UI gateway/controller sözleşmeleri, presentation mapper’ları, crypto/transport abstraction’ları ve bu sınırları doğrulayan testlerdir. Tam klasör migrasyonu ve tüm facade’ların yeniden yazılması kapsam dışıdır.
