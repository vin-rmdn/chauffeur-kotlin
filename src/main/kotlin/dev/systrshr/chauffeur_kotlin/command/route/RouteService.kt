package dev.systrshr.chauffeur_kotlin.command.route

import com.google.maps.routing.v2.RoutesClient
import com.google.maps.routing.v2.RoutesSettings
import com.google.type.LatLng
import dev.systrshr.chauffeur_kotlin.Config
import kotlin.time.Clock

class RouteService(
    private var routeClient: RouteClient = buildClient(),
    private var repository: Repository = buildRepository()
) {
    fun run(origin: String, destination: String) {
        val response = routeClient.directions(latLngFromString(origin), latLngFromString(destination))

        val routes = response.toRoutes(Clock.System.now())
        for (route in routes) repository.insert(route)
    }

    private fun latLngFromString(input: String): LatLng {
        val o = input.split(',')
        if (o.size != 2) throw IllegalArgumentException("$input is not a valid coordinate (${o.size} axes)")

        val lat: Double
        val long: Double
        try {
            lat = o[0].toDouble()
            long = o[1].toDouble()
        } catch (e: NumberFormatException) {
            throw IllegalArgumentException("$input is not a double floating value: ${e.message}")
        }

        val latLng = LatLng.newBuilder().apply {
            latitude = lat
            longitude = long
        }.build()

        return latLng
    }

    companion object {
        private fun buildClient(): RouteClient {
            val config = Config.build()
            val settings = RoutesSettings.newBuilder().setApiKey(config.googleCloud.mapsApiKey).setHeaderProvider {
                mapOf("X-Goog-FieldMask" to "routes.distanceMeters,routes.legs.startLocation,routes.legs.endLocation,routes.duration,routes.staticDuration")
            }.build()
            return RouteClient(RoutesClient.create(settings))
        }

        private fun buildRepository(): Repository {
            return Repository()
        }
    }
}
