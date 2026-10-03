plugins {
    kotlin("jvm") version "2.4.10"
    application
    id("org.graalvm.buildtools.native") version "1.1.14"
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
//    implementation("org.jetbrains.exposed:exposed-migration-core:1.5.0")
//    implementation("org.jetbrains.exposed:exposed-migration-jdbc:1.5.0")
//    implementation("org.jetbrains.exposed:exposed-migration-r2dbc:1.5.0")
//    implementation("org.postgresql:r2dbc-postgresql:1.1.3.RELEASE")
//    implementation("org.jetbrains.exposed:exposed-json:1.5.0")

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

tasks.withType<Test> {
    testLogging {
        showStandardStreams = true
    }
}

graalvmNative {
    binaries {
        named("main") {
            buildArgs.add("-H:ReflectionConfigurationFiles=${layout.projectDirectory}/src/main/resources/META-INF/native-image/dev/systrshr/chauffeur-kotlin/reflect-config.json")
        }
    }
}