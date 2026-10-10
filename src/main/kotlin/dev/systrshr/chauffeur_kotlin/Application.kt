package dev.systrshr.chauffeur_kotlin

import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.core.main
import com.github.ajalt.clikt.core.subcommands
import dev.systrshr.chauffeur_kotlin.command.route.Command
import dev.systrshr.chauffeur_kotlin.command.route.RouteService
import dev.systrshr.chauffeur_kotlin.db.Migration
import org.flywaydb.core.Flyway

class Application : CliktCommand("chauffeur-kotlin") {
    override fun run() = Unit
}

fun main(args: Array<String>) {
    val routeCommand = Command { return@Command RouteService() }
    val migrationCommand = Migration {
        val config = ConfigBuilder.build()

        return@Migration Flyway.configure().dataSource(config.migration.jdbcUrl(), config.migration.user, config.migration.password)
            .locations("filesystem:${config.migration.directory}").baselineOnMigrate(true).load()
    }

    Application().subcommands(routeCommand, migrationCommand).main(args)
}