package dev.systrshr.chauffeur_kotlin.command.route

import com.github.ajalt.clikt.testing.test
import com.google.maps.routing.v2.ComputeRoutesResponse
import io.mockk.confirmVerified
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import kotlin.test.assertEquals

// TODO: move away remaining Mockito mocks to MockK

class RouteTest {
    val mockRepository = mockk<Repository>()
    val classInTest = Route(repository = mockRepository)

    @Test
    fun `with improper origin coordinate format, throw an exception`() {
        val exception = assertThrows<IllegalArgumentException> { classInTest.test("-- -6.0-106.0 hi_there") }

        assertEquals("-6.0-106.0 is not a valid coordinate (1 axes)", exception.message)

        confirmVerified(mockRepository)
    }

    @Test
    fun `with not a number value, throw an exception`() {
        val exception = assertThrows<IllegalArgumentException> { classInTest.test("-- -6.0,hi hi-there") }

        assertEquals("-6.0,hi is not a double floating value: For input string: \"hi\"" ,exception.message)

        confirmVerified(mockRepository)
    }


    @Test
    fun `route command should work properly`() {
        every { mockRepository.directions(any(), any()) } returns ComputeRoutesResponse.newBuilder().build()
        val result = classInTest.test("-- -6.0,106.0 -6.1,106.1")

        assertEquals(0, result.statusCode)
        verify { mockRepository.directions(any(), any()) }
        confirmVerified(mockRepository)
    }
}