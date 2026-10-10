package dev.systrshr.chauffeur_kotlin

import com.sksamuel.hoplite.ConfigException
import com.sksamuel.hoplite.ConfigLoaderBuilder
import com.sksamuel.hoplite.sources.EnvironmentVariablesPropertySource
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import kotlin.test.assertContains
import kotlin.test.assertEquals

class ConfigTest {
    private val fullEnvironment = mapOf(
        "GOOGLE_CLOUD__MAPS_API_KEY" to "test-key",
        "DATABASE__USER" to "app",
        "DATABASE__PASSWORD" to "app-secret",
        "DATABASE__NAME" to "chauffeur",
        "DATABASE__HOST" to "database",
        "DATABASE__PORT" to "5432",
        "MIGRATION__USER" to "migrator",
        "MIGRATION__PASSWORD" to "migrator-secret",
        "MIGRATION__NAME" to "chauffeur",
        "MIGRATION__HOST" to "database",
        "MIGRATION__PORT" to "5432",
        "MIGRATION__DIRECTORY" to "/opt/chauffeur-kotlin/migration",
    )

    // Mirrors ConfigBuilder.defaultLoaderBuilder(), but reads a fake environment instead of the process one.
    private fun loaderFor(environment: Map<String, String>) = ConfigLoaderBuilder.empty()
        .addDefaults()
        .addPropertySource(
            EnvironmentVariablesPropertySource(
                useUnderscoresAsSeparator = true,
                allowUppercaseNames = true,
                environmentVariableMap = { environment },
            )
        )

    @Test
    fun `environment variables map onto the nested config`() {
        val config = ConfigBuilder.load(loaderFor(fullEnvironment))

        assertEquals("test-key", config.googleCloud.mapsApiKey)
        assertEquals("jdbc:postgresql://database:5432/chauffeur", config.database.jdbcUrl())
        assertEquals("app", config.database.user)
        assertEquals("migrator", config.migration.user)
        assertEquals("/opt/chauffeur-kotlin/migration", config.migration.directory)
    }

    @Test
    fun `a missing key fails with an error naming the key`() {
        val exception = assertThrows<ConfigException> {
            ConfigBuilder.load(loaderFor(fullEnvironment - "DATABASE__HOST"))
        }

        assertContains(exception.message ?: "", "host")
    }

    @Test
    fun `an empty environment fails instead of silently using defaults`() {
        assertThrows<ConfigException> { ConfigBuilder.load(loaderFor(emptyMap())) }
    }
}
