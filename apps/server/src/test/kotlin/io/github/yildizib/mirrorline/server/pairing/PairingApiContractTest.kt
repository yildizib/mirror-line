package io.github.yildizib.mirrorline.server.pairing

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import io.github.yildizib.mirrorline.server.bootstrap.JacksonConfiguration
import io.github.yildizib.mirrorline.server.devices.DeviceView
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import java.io.File

class PairingApiContractTest {
    private val mapper: ObjectMapper = JacksonConfiguration().objectMapper()
    private val fixture =
        mapper.readTree(File("../../protocol-fixtures/pairing-api-v1.json"))

    @Test
    fun `pairing API responses serialize to the shared v1 contract`() {
        val transactions = fixture["transactions"]
        val created = mapper.treeToValue(transactions["created"], PairingCreated::class.java)
        assertThat(mapper.readTree(mapper.writeValueAsString(created)))
            .isEqualTo(transactions["created"])

        listOf(
            "redeemed",
            "proofsVerified",
            "comparisonConfirmed",
            "completed",
            "expired",
            "cancelled",
            "rejected",
            "failed",
        ).forEach { name ->
            val view = mapper.treeToValue(transactions[name], PairingView::class.java)
            assertThat(mapper.readTree(mapper.writeValueAsString(view)))
                .isEqualTo(transactions[name])
        }

        transactions.forEach { assertTransactionFields(it) }

        assertThat(transactions["created"]["comparisonValue"].isNull).isTrue()
        assertThat(transactions["created"]["transcript"].isNull).isTrue()
        assertThat(transactions["redeemed"]["comparisonValue"].isNull).isTrue()
        assertThat(transactions["expired"]["transcript"].isNull).isTrue()
    }

    @Test
    fun `device API responses serialize UTC timestamps in the shared contract`() {
        fixture["devices"].forEach { expected ->
            val device = mapper.treeToValue(expected, DeviceView::class.java)
            assertThat(mapper.readTree(mapper.writeValueAsString(device))).isEqualTo(expected)
            assertThat(expected["deviceId"].textValue()).matches(uuidV4.pattern)
            assertThat(expected["role"].textValue()).isIn("MAIN", "SOURCE")
            assertThat(expected["status"].textValue()).isIn("ACTIVE", "PENDING", "REVOKED", "RETIRED")
            assertThat(expected["createdAt"].textValue()).endsWith("Z")
        }
    }

    private fun assertTransactionFields(transaction: JsonNode) {
        assertThat(transaction["pairingId"].textValue()).matches(uuidV4.pattern)
        assertThat(transaction["state"].textValue())
            .isIn(
                "created",
                "redeemed",
                "proofs_verified",
                "comparison_confirmed",
                "completed",
                "expired",
                "cancelled",
                "rejected",
                "failed",
            )
        assertThat(transaction["localRole"].textValue()).isIn("MAIN", "SOURCE")
        assertThat(transaction["capacity"]["current"].intValue()).isBetween(0, 5)
        assertThat(transaction["capacity"]["max"].intValue()).isEqualTo(5)
        assertThat(transaction["expiresAt"].textValue()).endsWith("Z")
    }

    private companion object {
        val uuidV4 = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
    }
}
