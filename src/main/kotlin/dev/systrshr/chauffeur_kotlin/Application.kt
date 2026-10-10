package dev.systrshr.chauffeur_kotlin

import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.core.main
import com.github.ajalt.clikt.core.subcommands
import dev.systrshr.chauffeur_kotlin.command.route.Command
import dev.systrshr.chauffeur_kotlin.command.route.RouteService
import dev.systrshr.chauffeur_kotlin.db.Migration
import dev.systrshr.chauffeur_kotlin.db.MigrationConfig
import org.flywaydb.core.Flyway

class Application : CliktCommand("chauffeur-kotlin") {
    override fun run() = Unit
}

fun flywayFrom(config: MigrationConfig): Flyway {
    return Flyway.configure()
        .dataSource(config.jdbcUrl(), config.user, config.password)
        .locations("filesystem:${config.directory}")
        .baselineOnMigrate(true)
        .load()
}

fun buildApplication(): CliktCommand {
    val routeCommand = Command { return@Command RouteService() }
    val migrationCommand = Migration { flywayFrom(ConfigBuilder.build().migration) }

    return Application().subcommands(routeCommand, migrationCommand)
}

fun main(args: Array<String>) {
    buildApplication().main(args)
}
