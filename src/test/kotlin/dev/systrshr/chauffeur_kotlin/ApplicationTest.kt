package dev.systrshr.chauffeur_kotlin

import com.github.ajalt.clikt.testing.test
import org.junit.jupiter.api.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals

// Help output must never require configuration: the container smoke test relies on it.
class ApplicationTest {
    @Test
    fun `help lists the subcommands without loading config`() {
        val result = buildApplication().test("--help")

        assertEquals(0, result.statusCode)
        assertContains(result.output, "route")
        assertContains(result.output, "migration")
    }

    @Test
    fun `route help works without loading config`() {
        val result = buildApplication().test("route --help")

        assertEquals(0, result.statusCode)
        assertContains(result.output, "origin")
        assertContains(result.output, "destination")
    }

    @Test
    fun `migration help works without loading config`() {
        val result = buildApplication().test("migration --help")

        assertEquals(0, result.statusCode)
    }
}
