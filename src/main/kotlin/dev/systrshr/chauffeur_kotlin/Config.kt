package dev.systrshr.chauffeur_kotlin

import com.sksamuel.hoplite.ConfigLoaderBuilder
import com.sksamuel.hoplite.addEnvironmentSource
import com.sksamuel.hoplite.addFileSource
import dev.systrshr.chauffeur_kotlin.command.route.GoogleCloud
import dev.systrshr.chauffeur_kotlin.db.MigrationConfig

data class Config(
    val googleCloud: GoogleCloud,
    val migration: MigrationConfig,
    val database: dev.systrshr.chauffeur_kotlin.db.Config
) {
    companion object {
        // TODO: turn this into a singleton
        fun build(): Config? {
            return ConfigLoaderBuilder.default()
                .addEnvironmentSource()
                .apply { addFileSource("config.toml", optional = true) }
                .build()
                .loadConfig<Config>().fold(
                    ifInvalid = { return@fold null },
                    ifValid = { return@fold it }
                )
        }
    }
}
