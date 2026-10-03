package dev.systrshr.chauffeur_kotlin.command.route

import dev.systrshr.chauffeur_kotlin.Config
import org.jetbrains.exposed.v1.core.Table
import org.jetbrains.exposed.v1.datetime.duration
import org.jetbrains.exposed.v1.datetime.timestamp
import org.jetbrains.exposed.v1.jdbc.Database
import org.jetbrains.exposed.v1.jdbc.insert
import org.jetbrains.exposed.v1.jdbc.transactions.transaction

class Repository(val db: Database = buildDatabase()) {
    object RoutesTable : Table("routes") {
        val originLatitude = double("origin_latitude")
        val originLongitude = double("origin_longitude")
        val destinationLatitude = double("destination_latitude")
        val destinationLongitude = double("destination_longitude")

        val estimateTime = timestamp("estimate_time")
        val duration = duration("duration")
        val staticDuration = duration("static_duration")

        val distance = integer(name = "distance")

        // TODO: add raw_response as jsonb

        override val primaryKey =
            PrimaryKey(estimateTime, originLatitude, originLongitude, destinationLatitude, destinationLongitude)
    }

    fun insert(route: Route) {
        transaction(db) {
            RoutesTable.insert {
                it[originLatitude] = route.origin.latitude
                it[originLongitude] = route.origin.longitude
                it[destinationLatitude] = route.destination.latitude
                it[destinationLongitude] = route.destination.longitude
                it[estimateTime] = route.estimateTime
                it[duration] = route.duration
                it[staticDuration] = route.staticDuration
                it[distance] = route.distance
            }
        }
    }

    companion object {
        private fun buildDatabase(): Database {
            val config = Config.build().database
            val db = Database.connect(
                config.jdbcUrl(),
                driver = "org.postgresql.Driver",
                user = config.user,
                password = config.password
            )

            return db
        }
    }
}
