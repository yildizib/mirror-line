# Domain presentation separation

## Requirements

- CallEvent and SmsMessage MUST remain locale-independent data models.
- Localization and display/status formatting MUST be performed by presentation services or mappers.
- Peer MUST NOT depend on a concrete crypto manager; verification-code generation MUST be injectable.
