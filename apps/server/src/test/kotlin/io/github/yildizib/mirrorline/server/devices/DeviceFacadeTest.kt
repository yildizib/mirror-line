package io.github.yildizib.mirrorline.server.devices

import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.dao.DataAccessResourceFailureException
import org.springframework.dao.DataIntegrityViolationException

class DeviceFacadeTest {
    @Test
    fun `maps only recognized postgres device quota signatures`() {
        assertThat(
            DeviceFacade.enrollmentConstraintCode(
                DataIntegrityViolationException("an account may have no more than five active source devices"),
            ),
        ).isEqualTo("DEVICE_LIMIT_REACHED")
        assertThat(
            DeviceFacade.enrollmentConstraintCode(
                DataIntegrityViolationException("duplicate key value violates uq_devices_one_active_main_per_user"),
            ),
        ).isEqualTo("DEVICE_ROLE_CONFLICT")
        assertThat(DeviceFacade.enrollmentConstraintCode(DataAccessResourceFailureException("database unavailable"))).isNull()
    }
}
