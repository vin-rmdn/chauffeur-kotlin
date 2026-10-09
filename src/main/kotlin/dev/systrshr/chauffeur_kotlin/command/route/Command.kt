package dev.systrshr.chauffeur_kotlin.command.route

import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.parameters.arguments.argument

class Command(val serviceConstructor: () -> RouteService): CliktCommand("route") {
    val origin by argument()
    val destination by argument()

    override fun run() {
        val service = serviceConstructor()
        service.run(origin, destination)
    }
}