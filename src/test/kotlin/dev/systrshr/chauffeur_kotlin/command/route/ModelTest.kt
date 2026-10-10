package dev.systrshr.chauffeur_kotlin.command.route

import com.google.maps.routing.v2.ComputeRoutesResponse
import com.google.maps.routing.v2.Location
import com.google.maps.routing.v2.Route
import com.google.maps.routing.v2.RouteLeg
import com.google.protobuf.Duration
import com.google.type.LatLng
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.time.Clock
import kotlin.time.Duration.Companion.minutes
import kotlin.time.DurationUnit

class ModelTest {
    @Test
    fun `converting compute routes to routes should be as expected`() {
        val response = ComputeRoutesResponse.newBuilder().addRoutes(
            Route.newBuilder().setDuration(Duration.newBuilder().setSeconds(30.minutes.toLong(DurationUnit.SECONDS)))
                .setStaticDuration(Duration.newBuilder().setSeconds(30.minutes.toLong(DurationUnit.SECONDS)))
                .addLegs(
                    RouteLeg.newBuilder().setStartLocation(
                        Location.newBuilder()
                            .setLatLng(LatLng.newBuilder().setLatitude(-6.0).setLongitude(106.0).build())
                            .build()
                    ).build()
                )
                .addLegs(
                    RouteLeg.newBuilder().setEndLocation(
                        Location.newBuilder()
                            .setLatLng(LatLng.newBuilder().setLatitude(-6.1).setLongitude(106.1).build())
                            .build()
                    ).build()
                )
                .setDistanceMeters(20_000)
                .build()
        ).build()

        val currentTime = Clock.System.now()
        val actual = response.toRoutes(currentTime)

        assertEquals(listOf(
            Route(
                Coordinate(-6.0, 106.0),
                Coordinate(-6.1, 106.1),
                currentTime,
                30.minutes,
                30.minutes,
             20_000,
            )
        ), actual)
    }
}