package dev.systrshr.chauffeur_kotlin.command.route

import kotlin.time.Duration
import kotlin.time.Instant

data class Coordinate(val latitude: Double, val longitude: Double)

data class Route(
    val origin: Coordinate,
    val destination: Coordinate,
    val estimateTime: Instant,
    val duration: Duration,
    val staticDuration: Duration,
    val distance: Int
)
