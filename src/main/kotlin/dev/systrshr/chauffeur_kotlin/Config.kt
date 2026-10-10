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
            this.instance ?: load(defaultLoaderBuilder()).also { instance = it }
        }
    }

    /** Environment variables (`SECTION__KEY`) take precedence over an optional `config.toml` in the working directory. */
    fun defaultLoaderBuilder(): ConfigLoaderBuilder {
        return ConfigLoaderBuilder.default()
            .addEnvironmentSource()
            .addFileSource("config.toml", optional = true)
    }

    /** Seam for tests: loads [Config] from an arbitrary set of sources, bypassing the cached singleton. */
    fun load(builder: ConfigLoaderBuilder): Config {
        return builder.build().loadConfigOrThrow<Config>()
    }
}
