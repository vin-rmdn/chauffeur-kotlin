package dev.systrshr.chauffeur_kotlin.command.route

import com.google.maps.routing.v2.ComputeRoutesResponse
import com.google.type.LatLng
import kotlin.time.Duration
import kotlin.time.Duration.Companion.nanoseconds
import kotlin.time.Instant

data class Coordinate(val latitude: Double, val longitude: Double)

fun LatLng.toCoordinate(): Coordinate {
    return Coordinate(latitude, longitude)
}

data class Route(
    val origin: Coordinate,
    val destination: Coordinate,
    val estimateTime: Instant,
    val duration: Duration,
    val staticDuration: Duration,
    val distance: Int
)

fun ComputeRoutesResponse.toRoutes(estimateTime: Instant): List<Route> {
    val routes: MutableList<Route> = mutableListOf()

    for (googleRoute in this.routesList) {
        val legCount = googleRoute.legsCount
        val legs = googleRoute.legsList

        if (legs.isEmpty()) throw Exception("empty legs")

        routes.add(
            Route(
                legs[0].startLocation.latLng.toCoordinate(),
                legs[legCount - 1].endLocation.latLng.toCoordinate(),
                estimateTime,
                googleRoute.duration.nanos.nanoseconds,
                googleRoute.staticDuration.nanos.nanoseconds,
                googleRoute.distanceMeters,
            )
        )
    }

    return routes
}
