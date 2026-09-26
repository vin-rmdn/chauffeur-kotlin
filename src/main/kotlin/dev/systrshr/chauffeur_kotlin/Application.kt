package dev.systrshr.chauffeur_kotlin

import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.core.main
import com.github.ajalt.clikt.core.subcommands
import dev.systrshr.chauffeur_kotlin.command.route.Route

class Application: CliktCommand("chauffeur-kotlin") {
    override fun run() = Unit
}

fun main(args: Array<String>) {
    Application().subcommands(Route()).main(args)
}