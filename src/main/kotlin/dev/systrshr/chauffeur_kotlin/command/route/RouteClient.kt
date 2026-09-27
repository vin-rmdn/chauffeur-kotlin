package dev.systrshr.chauffeur_kotlin.command.route

import com.google.maps.routing.v2.ComputeRoutesRequest
import com.google.maps.routing.v2.ComputeRoutesResponse
import com.google.maps.routing.v2.Location
import com.google.maps.routing.v2.RouteTravelMode
import com.google.maps.routing.v2.RoutesClient
import com.google.maps.routing.v2.RoutingPreference
import com.google.maps.routing.v2.Waypoint
import com.google.type.LatLng

class RouteClient(var client: RoutesClient) {
    fun directions(origin: LatLng, destination: LatLng): ComputeRoutesResponse {
        val request =
            ComputeRoutesRequest.newBuilder().setOrigin(origin.toWaypoint()).setDestination(destination.toWaypoint())
                .setRoutingPreference(RoutingPreference.TRAFFIC_AWARE).setTravelMode(RouteTravelMode.DRIVE).build()
        val response = client.computeRoutes(request)

        return response
    }

    fun LatLng.toWaypoint(): Waypoint {
        val location = Location.newBuilder().setLatLng(this).build()

        return Waypoint.newBuilder().setLocation(location).build()
    }
}