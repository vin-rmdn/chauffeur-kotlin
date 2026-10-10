package dev.systrshr.chauffeur_kotlin

import com.google.maps.routing.v2.ComputeRoutesResponse
import com.google.maps.routing.v2.Location
import com.google.maps.routing.v2.Route
import com.google.maps.routing.v2.RouteLeg
import com.google.protobuf.Duration
import com.google.type.LatLng
import dev.systrshr.chauffeur_kotlin.command.route.Repository
import dev.systrshr.chauffeur_kotlin.command.route.Repository.RoutesTable
import dev.systrshr.chauffeur_kotlin.command.route.RouteClient
import dev.systrshr.chauffeur_kotlin.command.route.RouteService
import io.mockk.every
import io.mockk.mockk
import org.jetbrains.exposed.v1.jdbc.selectAll
import org.jetbrains.exposed.v1.jdbc.transactions.transaction
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

// Real RouteService + real Repository + real Postgres; only the Google call is stubbed.
class RouteServiceIntegrationTest {
    private val routeClient = mockk<RouteClient>()
    private val service = RouteService(routeClient, Repository(TestDb.database))

    @BeforeEach
    fun migratedDatabase() = TestDb.reset()

    private fun latLng(lat: Double, lng: Double) = LatLng.newBuilder().setLatitude(lat).setLongitude(lng).build()

    private fun leg(start: LatLng? = null, end: LatLng? = null): RouteLeg {
        val builder = RouteLeg.newBuilder()
        start?.let { builder.setStartLocation(Location.newBuilder().setLatLng(it)) }
        end?.let { builder.setEndLocation(Location.newBuilder().setLatLng(it)) }
        return builder.build()
    }

    @Test
    fun `a route returned by google is stored with correct duration and distance`() {
        val response = ComputeRoutesResponse.newBuilder().addRoutes(
            Route.newBuilder()
                .addLegs(leg(start = latLng(-6.0, 106.0)))
                .addLegs(leg(end = latLng(-6.1, 106.1)))
                .setDuration(Duration.newBuilder().setSeconds(1_800).setNanos(500_000_000))
                .setStaticDuration(Duration.newBuilder().setSeconds(1_500))
                .setDistanceMeters(12_345)
        ).build()
        every { routeClient.directions(any(), any()) } returns response

        service.run("-6.0,106.0", "-6.1,106.1")

        val rows = transaction(TestDb.database) { RoutesTable.selectAll().toList() }
        assertEquals(1, rows.size)
        val row = rows.single()
        assertEquals(-6.0, row[RoutesTable.originLatitude])
        assertEquals(106.1, row[RoutesTable.destinationLongitude])
        assertEquals(1_800.seconds + 500.milliseconds, row[RoutesTable.duration])
        assertEquals(1_500.seconds, row[RoutesTable.staticDuration])
        assertEquals(12_345, row[RoutesTable.distance])
    }

    @Test
    fun `nothing is stored when google returns no routes`() {
        every { routeClient.directions(any(), any()) } returns ComputeRoutesResponse.getDefaultInstance()

        service.run("-6.0,106.0", "-6.1,106.1")

        assertEquals(0, transaction(TestDb.database) { RoutesTable.selectAll().count() })
    }
}
