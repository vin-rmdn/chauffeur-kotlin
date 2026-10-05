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
        private val isNativeImage = System.getProperty("org.graalvm.nativeimage.imagecode").equals("runtime")

        // TODO: turn this into a singleton
        fun build(): Config {
            return ConfigLoaderBuilder.default()
                .addEnvironmentSource()
                .apply { if (!isNativeImage) addFileSource("config.toml", optional = true) }
                .build()
                .loadConfigOrThrow<Config>()
        }
    }
}
