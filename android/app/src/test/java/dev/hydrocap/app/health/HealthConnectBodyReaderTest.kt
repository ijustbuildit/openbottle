package dev.hydrocap.app.health

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import java.time.Instant

@OptIn(ExperimentalCoroutinesApi::class)
class HealthConnectBodyReaderTest {
    private val now=Instant.parse("2026-09-30T10:00:00Z")
    private class Gateway(var grants:Set<String>,val pages:List<WeightPage>):HealthBodyGateway {
        var calls=0; var from:Instant?=null
        override fun availability()=HealthConnectSupport.Availability.AVAILABLE
        override suspend fun permissions()=grants
        override suspend fun weights(from:Instant,to:Instant,token:String?):WeightPage {this.from=from; return pages[(calls++).coerceAtMost(pages.lastIndex)]}
    }
    private fun permissions()=HealthConnectBodyReader.ONBOARDING_PERMISSIONS
    @Test fun writeGrantDoesNotRequireWeightAndNoReadWithoutOptionalGrant()=runTest {
        val gateway=Gateway(setOf(HealthConnectSupport.HYDRATION_WRITE_PERMISSION),emptyList())
        val result=HealthConnectBodyReader(gateway).read(now)
        assertTrue(result.hydrationPermission); assertFalse(result.weightPermission); assertNull(result.weightKg); assertEquals(0,gateway.calls)
    }
    @Test fun weightReadIsIndependentOfDeniedWaterWriteAndFiltersFutureInvalidValues()=runTest {
        val gateway=Gateway(setOf(HealthConnectBodyReader.READ_WEIGHT),listOf(WeightPage(listOf(WeightValue(now.plusSeconds(1),80.0),WeightValue(now,Double.NaN),WeightValue(now.minusSeconds(1),0.0),WeightValue(now.minusSeconds(2),72.5)),"")))
        val result=HealthConnectBodyReader(gateway).read(now)
        assertTrue(result.weightPermission); assertFalse(result.hydrationPermission); assertEquals(72.5,result.weightKg!!,0.0)
        assertEquals(now.minusSeconds(30L*86400),gateway.from)
    }
    @Test fun emptyStringTerminatesAndroid12ProviderPagination()=runTest {
        val gateway=Gateway(permissions(),listOf(WeightPage(emptyList(),"")))
        val result=HealthConnectBodyReader(gateway).read(now)
        assertNull(result.weightKg); assertNull(result.error); assertTrue(result.weightPermission); assertEquals(1,gateway.calls)
    }
    @Test fun repeatedTokenCannotHoldOnboardingIndefinitely()=runTest {
        val gateway=Gateway(permissions(),listOf(WeightPage(emptyList(),"same-token")))
        val result=HealthConnectBodyReader(gateway).read(now)
        assertNull(result.weightKg); assertNotNull(result.error); assertEquals(2,gateway.calls)
    }
    @Test fun noDataIsDistinctFromPermissionMissing()=runTest {
        val result=HealthConnectBodyReader(Gateway(permissions(),listOf(WeightPage(emptyList(),null)))).read(now)
        assertTrue(result.weightPermission); assertNull(result.error); assertEquals("No weight in the last 30 days",result.weightStatus)
    }
    @Test fun hungProviderTimesOutWithGrantedFieldsPreserved()=runTest {
        val gateway=object:HealthBodyGateway {
            override fun availability()=HealthConnectSupport.Availability.AVAILABLE
            override suspend fun permissions()=HealthConnectBodyReader.ONBOARDING_PERMISSIONS
            override suspend fun weights(from:Instant,to:Instant,token:String?):WeightPage {delay(100_000); return WeightPage(emptyList(),null)}
        }
        val result=HealthConnectBodyReader(gateway,100).read(now)
        assertTrue(result.weightPermission); assertTrue(result.hydrationPermission); assertNull(result.weightKg); assertNotNull(result.error)
    }
}
