# Design

UI yalnızca feature controller/gateway sözleşmelerine erişir. Platform channel, permission, notification router ve key store implementasyonları infrastructure adapter olarak kalır.

Domain modelleri localization veya presentation formatlaması bilmez. Localization, verification-code sunumu ve durum etiketleri presentation servislerine taşınır.

Facade’lar transport/message-routing portlarına bağlanır; socket manager ve concrete crypto implementasyonları composition root/infrastructure tarafında sağlanır. Wire payload, queue/retry ve persistence davranışı değişmez.
