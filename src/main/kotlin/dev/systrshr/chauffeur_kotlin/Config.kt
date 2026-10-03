package dev.systrshr.chauffeur_kotlin

import dev.systrshr.chauffeur_kotlin.command.route.GoogleCloud
import dev.systrshr.chauffeur_kotlin.db.MigrationConfig

data class Config(
    val googleCloud: GoogleCloud,
    val migration: MigrationConfig
)
