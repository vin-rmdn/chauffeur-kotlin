package dev.systrshr.chauffeur_kotlin.db

data class MigrationConfig(
    val user: String,
    val password: String,
    val name: String,
    val host: String,
    val port: Int,
    val directory: String
)