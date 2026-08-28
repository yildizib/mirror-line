# Refactor critical Clean Architecture boundaries

Issue #109 limits dependencies between UI, domain, and infrastructure while preserving the existing socket protocol, persistence format, and database schema.

The scope includes UI gateway/controller contracts, presentation mappers, crypto/transport abstractions, and boundary tests. A complete folder migration and full facade rewrite are out of scope.
