plugins {
    kotlin("jvm") version "2.4.10"
    application
}

group = "dev.systrshr"
version = "1.0-SNAPSHOT"

repositories {
    mavenCentral()
}

dependencies {
    implementation("com.google.maps:google-maps-routing:1.83.0")
    implementation("com.sksamuel.hoplite:hoplite-core:2.9.0")
    implementation("com.sksamuel.hoplite:hoplite-toml:2.9.0")
    implementation("com.github.ajalt.clikt:clikt:5.1.0")
    implementation("org.jetbrains.exposed:exposed-core:1.5.0")
    implementation("org.jetbrains.exposed:exposed-kotlin-datetime:1.5.0")
    implementation("org.flywaydb:flyway-core:13.7.0")
    implementation("org.flywaydb:flyway-database-postgresql:13.7.0")
    implementation("org.postgresql:postgresql:42.7.12")
    implementation("org.jetbrains.exposed:exposed-jdbc:1.5.0")

    testImplementation(kotlin("test"))
    testImplementation("org.mockito:mockito-core:5.+")
    testImplementation("org.mockito:mockito-junit-jupiter:5.+")
    testImplementation("net.bytebuddy:byte-buddy-agent:1.14.+")
    testImplementation("io.mockk:mockk-jvm:1.14.11")
}

kotlin {
    jvmToolchain(25)
}

application {
    mainClass.set("dev.systrshr.chauffeur_kotlin.ApplicationKt")
    // Short-lived CLI on a small VPS: favour fast startup and a capped heap.
    applicationDefaultJvmArgs = listOf(
        "-Duser.timezone=UTC",
        "-XX:+UseSerialGC",
        "-XX:TieredStopAtLevel=1",
        "-Xshare:auto",
        "-Xmx192m",
        // JDK 24+ warn on every run about JNA (Flyway) and protobuf's Unsafe use; keep the journal clean.
        "--enable-native-access=ALL-UNNAMED",
        "--sun-misc-unsafe-memory-access=allow",
    )
}

abstract class MockitoAgentProvider : CommandLineArgumentProvider {
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val agentJar: ConfigurableFileCollection

    override fun asArguments(): Iterable<String> = agentJar.files.firstOrNull()?.let {
        listOf("-javaagent:${it.absolutePath}")
    } ?: emptyList()
}

tasks.test {
    jvmArgumentProviders.add(objects.newInstance<MockitoAgentProvider>().apply {
        agentJar.from(configurations.testRuntimeClasspath.get().filter { it.name.startsWith("byte-buddy-agent") })
    })
    useJUnitPlatform()
}

tasks.processResources {
    exclude("config*.toml", ".env*")
}

tasks.withType<Test> {
    testLogging {
        showStandardStreams = true
    }
}

testing {
    suites {
        // `./gradlew integrationTest` runs only these; `./gradlew test` stays Docker-free.
        register<JvmTestSuite>("integrationTest") {
            useJUnitJupiter()
            dependencies {
                implementation(project())
                implementation("org.jetbrains.kotlin:kotlin-test:2.4.10")
                implementation("io.mockk:mockk-jvm:1.14.11")
                implementation("org.testcontainers:testcontainers-postgresql:2.0.5")
                implementation("org.testcontainers:testcontainers-junit-jupiter:2.0.5")
            }
            targets.configureEach {
                testTask.configure {
                    testLogging { showStandardStreams = true }
                }
            }
        }
    }
}

// Integration tests see the same libraries as the application (Exposed, Flyway, protobuf types, ...).
configurations["integrationTestImplementation"].extendsFrom(configurations.implementation.get())

tasks.register("allTests") {
    description = "Runs unit and integration tests."
    group = "verification"
    dependsOn(tasks.test, tasks.named("integrationTest"))
}

tasks.check {
    dependsOn(tasks.named("integrationTest"))
}
