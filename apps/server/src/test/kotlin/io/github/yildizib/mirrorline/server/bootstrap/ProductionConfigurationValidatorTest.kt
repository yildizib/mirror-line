package io.github.yildizib.mirrorline.server.bootstrap

import org.assertj.core.api.Assertions.assertThatThrownBy
import org.junit.jupiter.api.Test
import org.springframework.boot.DefaultApplicationArguments

class ProductionConfigurationValidatorTest {
    @Test
    fun `production requires public domain`() {
        val validator = ProductionConfigurationValidator(MirrorLineProperties())
        assertThatThrownBy { validator.run(DefaultApplicationArguments()) }
            .isInstanceOf(IllegalArgumentException::class.java)
            .hasMessageContaining("MIRRORLINE_PUBLIC_DOMAIN")
    }

    @Test
    fun `production rejects absent malformed and short pairing HMAC keys`() {
        listOf("", "not base64!", "AA").forEach { key ->
            val validator = ProductionConfigurationValidator(MirrorLineProperties("mirrorline.example", key))
            assertThatThrownBy { validator.run(DefaultApplicationArguments()) }
                .isInstanceOf(IllegalArgumentException::class.java)
                .hasMessageContaining("MIRRORLINE_PAIRING_CODE_HMAC_KEY")
        }
    }
}
