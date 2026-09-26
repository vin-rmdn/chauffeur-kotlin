plugins {
    kotlin("jvm") version "2.4.10"
}

group = "dev.systrshr"
version = "1.0-SNAPSHOT"

repositories {
    mavenCentral()
}

dependencies {
    implementation("com.google.maps:google-maps-routing:1.83.0")

    testImplementation(kotlin("test"))
    testImplementation("org.mockito:mockito-core:5.+")
    testImplementation("org.mockito:mockito-junit-jupiter:5.+")
    testImplementation("net.bytebuddy:byte-buddy-agent:1.14.+")
}

kotlin {
    jvmToolchain(25)
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