package dev.systrshr.chauffeur_kotlin.command.route

import org.jetbrains.exposed.v1.core.Table
import org.jetbrains.exposed.v1.datetime.duration
import org.jetbrains.exposed.v1.datetime.timestamp

class Repository() {
    object RoutesTable : Table("routes") {
        val origin = float("origin")
        val destination = float("destination")

        val estimateTime = timestamp("estimate_time")
        val duration = duration("duration")
        val staticDuration = duration("static_duration")

        val distance = integer(name = "distance")

        // TODO: add raw_response as jsonb

        override val primaryKey = PrimaryKey(estimateTime, origin, destination)
    }
}