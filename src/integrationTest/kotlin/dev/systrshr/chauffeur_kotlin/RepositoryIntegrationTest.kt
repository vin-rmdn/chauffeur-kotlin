package dev.systrshr.chauffeur_kotlin

import dev.systrshr.chauffeur_kotlin.command.route.Coordinate
import dev.systrshr.chauffeur_kotlin.command.route.Repository
import dev.systrshr.chauffeur_kotlin.command.route.Repository.RoutesTable
import dev.systrshr.chauffeur_kotlin.command.route.Route
import org.jetbrains.exposed.v1.jdbc.selectAll
import org.jetbrains.exposed.v1.jdbc.transactions.transaction
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import kotlin.test.assertEquals
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Instant

class RepositoryIntegrationTest {
    private val repository by lazy { Repository(TestDb.database) }

    private val route = Route(
        origin = Coordinate(-6.36957522389822, 106.89421407439198),
        destination = Coordinate(-6.243468379073277, 106.80196622795371),
        estimateTime = Instant.fromEpochSeconds(1_790_000_000),
        duration = 31.minutes + 12.seconds,
        staticDuration = 28.minutes,
        distance = 15_342,
    )

    @BeforeEach
    fun migratedDatabase() = TestDb.reset()

    private fun storedRoutes(): List<Route> = transaction(TestDb.database) {
        RoutesTable.selectAll().map {
            Route(
                Coordinate(it[RoutesTable.originLatitude], it[RoutesTable.originLongitude]),
                Coordinate(it[RoutesTable.destinationLatitude], it[RoutesTable.destinationLongitude]),
                it[RoutesTable.estimateTime],
                it[RoutesTable.duration],
                it[RoutesTable.staticDuration],
                it[RoutesTable.distance],
            )
        }
    }

    @Test
    fun `an inserted route is read back unchanged`() {
        repository.insert(route)

        assertEquals(listOf(route), storedRoutes())
    }

    @Test
    fun `inserting the same route and estimate time twice is rejected`() {
        repository.insert(route)

        assertThrows<Exception> { repository.insert(route) }
        assertEquals(1, storedRoutes().size)
    }

    @Test
    fun `the same route at a later estimate time is a new row`() {
        repository.insert(route)
        repository.insert(route.copy(estimateTime = route.estimateTime + 15.minutes))

        assertEquals(2, storedRoutes().size)
    }
}
