package dev.systrshr.chauffeur_kotlin.db

import com.github.ajalt.clikt.core.CliktCommand
import org.flywaydb.core.Flyway

class Migration(
    val flywayFactory: () -> Flyway
) : CliktCommand("migration") {
    override fun run(): Unit {
        val flyway = flywayFactory()
        val result = flyway.migrate()
        print(result)
    }
}
