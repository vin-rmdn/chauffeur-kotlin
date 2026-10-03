package dev.systrshr.chauffeur_kotlin.command.route

import com.github.ajalt.clikt.testing.test
import com.google.maps.routing.v2.ComputeRoutesResponse
import com.google.maps.routing.v2.Location
import com.google.maps.routing.v2.Route
import com.google.maps.routing.v2.RouteLeg
import com.google.protobuf.Duration
import com.google.type.LatLng
import io.mockk.confirmVerified
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import kotlin.test.assertEquals

// TODO: move away remaining Mockito mocks to MockK

class RouteServiceTest {
    val mockRouteClient = mockk<RouteClient>()
    val mockRepository = mockk<Repository>()

    val classInTest = RouteService(mockRouteClient, mockRepository)

    @Test
    fun `with improper origin coordinate format, throw an exception`() {
        val exception = assertThrows<IllegalArgumentException> { classInTest.test("-- -6.0-106.0 hi_there") }

        assertEquals("-6.0-106.0 is not a valid coordinate (1 axes)", exception.message)

        confirmVerified(mockRouteClient)
    }

    @Test
    fun `with not a number value, throw an exception`() {
        val exception = assertThrows<IllegalArgumentException> { classInTest.test("-- -6.0,hi hi-there") }

        assertEquals("-6.0,hi is not a double floating value: For input string: \"hi\"", exception.message)

        confirmVerified(mockRouteClient)
    }


    @Test
    fun `if leg is empty, throw an exception`() {
        val stubRoute = Route.newBuilder().build()
        val stubResponse = ComputeRoutesResponse.newBuilder().addRoutes(stubRoute).build()

        every { mockRouteClient.directions(any(), any()) } returns stubResponse

        val actualException = assertThrows<Exception> { classInTest.test("-- -6.0,106.0 -6.1,106.1") }
        assertEquals("empty legs", actualException.message)

        verify { mockRouteClient.directions(any(), any()) }
        confirmVerified(mockRouteClient)
    }


    @Test
    fun `route command should work properly`() {
        val originLatLong = LatLng.newBuilder().apply {
            latitude = -6.0
            longitude = 106.0
        }
        val destinationLatLong = LatLng.newBuilder().apply {
            latitude = -6.1
            longitude = 106.1
        }
        val stubRoute = Route.newBuilder()
            .addLegs(RouteLeg.newBuilder().setStartLocation(Location.newBuilder().setLatLng(originLatLong)).build())
            .addLegs(RouteLeg.newBuilder().setEndLocation(Location.newBuilder().setLatLng(destinationLatLong)).build())
            .setDuration(Duration.newBuilder().setSeconds(30 * 60).build())
            .setStaticDuration(Duration.newBuilder().setSeconds(30 * 60).build())
            .setDistanceMeters(30)
            .build()
        val stubResponse = ComputeRoutesResponse.newBuilder().addRoutes(stubRoute).build()

        every { mockRouteClient.directions(any(), any()) } returns stubResponse
        every { mockRepository.insert(any()) } returns Unit
        val result = classInTest.test("-- -6.0,106.0 -6.1,106.1")

        assertEquals(0, result.statusCode)
        verify { mockRouteClient.directions(any(), any()) }
        verify { mockRepository.insert(any()) }
        confirmVerified(mockRouteClient)
        confirmVerified(mockRepository)
    }
}