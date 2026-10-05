package dev.systrshr.chauffeur_kotlin.db

import com.github.ajalt.clikt.core.CliktCommand
import dev.systrshr.chauffeur_kotlin.Config
import org.flywaydb.core.Flyway

class Migration(
    val flyway: Flyway = loadFlyway(loadConfig())
) : CliktCommand("migration") {
    companion object {
        private fun loadConfig(): MigrationConfig {
            return Config.build().migration
        }

        private fun loadFlyway(config: MigrationConfig): Flyway {
            return Flyway.configure().dataSource(jdbcUrl(config), config.user, config.password)
                .locations("filesystem:${config.directory}").baselineOnMigrate(true).load()
        }

        private fun jdbcUrl(config: MigrationConfig): String {
            return "jdbc:postgresql://${config.host}:${config.port}/${config.name}"
        }
    }

    override fun run(): Unit {
        val result = flyway.migrate()
        print(result)
    }
}
