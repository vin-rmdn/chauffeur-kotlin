package dev.systrshr.chauffeur_kotlin.command.route

import com.google.maps.routing.v2.ComputeRoutesResponse
import com.google.maps.routing.v2.RoutesClient
import com.google.type.LatLng
import org.junit.jupiter.api.Test
import org.mockito.ArgumentMatchers.any
import org.mockito.Mockito
import org.mockito.Mockito.mock
import kotlin.test.assertNotNull

class RepositoryTest {
    val mockRouteClient: RoutesClient = mock(RoutesClient::class.java)

    var classInTest: Repository = Repository(mockRouteClient)

    @Test
    fun `route should run successfully`() {
        val origin = LatLng.newBuilder().apply {
            latitude = -6.36957522389822
            longitude = 106.89421407439198
        }.build()
        val destination = LatLng.newBuilder().apply {
            latitude = -6.243468379073277
            longitude = 106.80196622795371
        }.build()

        Mockito.`when`(mockRouteClient.computeRoutes(any())).thenReturn(ComputeRoutesResponse.newBuilder().build())

        val directions = classInTest.directions(origin, destination)
        assertNotNull(directions)
    }
}