package dev.systrshr.chauffeur_kotlin.command.route

import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.parameters.arguments.argument
import com.google.maps.routing.v2.RoutesClient
import com.google.maps.routing.v2.RoutesSettings
import com.google.type.LatLng
import com.sksamuel.hoplite.ConfigLoaderBuilder
import com.sksamuel.hoplite.addResourceSource

class RouteService(
    private val routeClient: RouteClient = buildRepository(),
) : CliktCommand("route") {
    val origin: String by argument()
    val destination: String by argument()

    override fun run() {
        val response = routeClient.directions(latLngFromString(origin), latLngFromString(destination))
        println("Response: ${response.toString()}")
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
}

private fun buildRepository(): RouteClient {
    val conf = ConfigLoaderBuilder.default().addResourceSource("/config.toml").build().loadConfigOrThrow<Config>()
    val settings = RoutesSettings.newBuilder().setApiKey(conf.googleCloud.mapsApiKey).setHeaderProvider {
        mapOf<String, String>("X-Goog-FieldMask" to "*")
    }.build()
    return RouteClient(RoutesClient.create(settings))
}