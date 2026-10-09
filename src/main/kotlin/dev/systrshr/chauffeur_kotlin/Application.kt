package dev.systrshr.chauffeur_kotlin

import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.core.main
import com.github.ajalt.clikt.core.subcommands
import dev.systrshr.chauffeur_kotlin.command.route.Command
import dev.systrshr.chauffeur_kotlin.command.route.RouteService
import dev.systrshr.chauffeur_kotlin.db.Migration

class Application : CliktCommand("chauffeur-kotlin") {
    override fun run() = Unit
}

fun main(args: Array<String>) {
    val routeCommand = Command { return@Command RouteService() }

    Application().subcommands(routeCommand, Migration()).main(args)
}