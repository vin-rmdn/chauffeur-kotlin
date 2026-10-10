package dev.systrshr.chauffeur_kotlin

import dev.systrshr.chauffeur_kotlin.db.MigrationConfig
import org.flywaydb.core.Flyway
import org.jetbrains.exposed.v1.jdbc.Database
import org.testcontainers.postgresql.PostgreSQLContainer
import java.sql.Connection
import java.sql.DriverManager

/**
 * One Postgres container shared by every integration test in the JVM. It starts on first use and is
 * stopped by Testcontainers' reaper when the JVM exits.
 */
object TestDb {
    private val container: PostgreSQLContainer = PostgreSQLContainer("postgres:18-alpine").also { it.start() }

    val migrationConfig: MigrationConfig by lazy {
        MigrationConfig(
            user = container.username,
            password = container.password,
            name = container.databaseName,
            host = container.host,
            port = container.firstMappedPort,
            // Same files that the Docker image copies to /opt/chauffeur-kotlin/migration.
            directory = "src/main/resources/db/migration",
        )
    }

    val database: Database by lazy {
        Database.connect(
            migrationConfig.jdbcUrl(),
            driver = "org.postgresql.Driver",
            user = container.username,
            password = container.password,
        )
    }

    fun flyway(): Flyway = flywayFrom(migrationConfig)

    fun <T> connection(block: (Connection) -> T): T =
        DriverManager.getConnection(migrationConfig.jdbcUrl(), container.username, container.password).use(block)

    /** Back to an empty database, so that tests are independent of each other. */
    fun wipe() {
        connection { c -> c.createStatement().use { it.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;") } }
    }

    /** Empty database with the real migrations applied. */
    fun reset() {
        wipe()
        flyway().migrate()
    }
}
