package dev.systrshr.chauffeur_kotlin.command.route

import com.github.ajalt.clikt.testing.test
import io.mockk.confirmVerified
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import org.junit.jupiter.api.Test

class CommandTest {
    val mockService = mockk<RouteService>()
    val classInTest = Command() {
        return@Command mockService
    }

    @Test
    fun `when input is provided, parameter should be provided to service and run normally`() {
        every { mockService.run("origin", "destination") } returns Unit

        classInTest.test("origin destination")

        verify { mockService.run("origin", "destination") }
        confirmVerified(mockService)
    }
}