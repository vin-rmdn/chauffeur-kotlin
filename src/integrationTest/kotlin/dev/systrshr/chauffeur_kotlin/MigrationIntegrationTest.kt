package dev.systrshr.chauffeur_kotlin

import com.github.ajalt.clikt.testing.test
import dev.systrshr.chauffeur_kotlin.db.Migration
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals

class MigrationIntegrationTest {
    @BeforeEach
    fun emptyDatabase() = TestDb.wipe()

    private fun scalar(sql: String): String? = TestDb.connection { c ->
        c.createStatement().use { s -> s.executeQuery(sql).use { if (it.next()) it.getString(1) else null } }
    }

    private fun appliedMigrations() =
        scalar("SELECT count(*) FROM flyway_schema_history WHERE success")?.toInt()

    @Test
    fun `migration command creates the routes table`() {
        val result = Migration { TestDb.flyway() }.test("")

        assertEquals(0, result.statusCode)
        assertEquals("routes", scalar("SELECT to_regclass('public.routes')::text"))
        assertEquals(1, appliedMigrations())
    }

    @Test
    fun `running the migration twice is a no-op`() {
        Migration { TestDb.flyway() }.test("")
        val second = Migration { TestDb.flyway() }.test("")

        assertEquals(0, second.statusCode)
        assertEquals(1, appliedMigrations())
    }

    @Test
    fun `routes table has the expected key and time zone aware timestamp`() {
        TestDb.flyway().migrate()

        assertEquals(
            "timestamp with time zone",
            scalar("SELECT data_type FROM information_schema.columns WHERE table_name = 'routes' AND column_name = 'estimate_time'"),
        )
        assertEquals(
            "5",
            scalar("SELECT count(*) FROM information_schema.key_column_usage WHERE constraint_name = 'pk_routes'"),
        )
    }
}
