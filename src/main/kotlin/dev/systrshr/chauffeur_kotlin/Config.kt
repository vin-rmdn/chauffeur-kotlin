package dev.systrshr.chauffeur_kotlin

import com.sksamuel.hoplite.ConfigLoaderBuilder
import com.sksamuel.hoplite.addEnvironmentSource
import com.sksamuel.hoplite.addFileSource
import dev.systrshr.chauffeur_kotlin.command.route.GoogleCloud
import dev.systrshr.chauffeur_kotlin.db.MigrationConfig
import kotlin.concurrent.Volatile

data class Config(
    val googleCloud: GoogleCloud,
    val migration: MigrationConfig,
    val database: dev.systrshr.chauffeur_kotlin.db.Config
)

object ConfigBuilder {
    @Volatile
    private var instance: Config? = null

    fun build(): Config {
        return instance ?: synchronized(this) {
            this.instance ?: ConfigLoaderBuilder.default()
                .addEnvironmentSource()
                .apply { addFileSource("config.toml", optional = true) }
                .build()
                .loadConfigOrThrow<Config>().also { instance = it }
        }
    }
}
