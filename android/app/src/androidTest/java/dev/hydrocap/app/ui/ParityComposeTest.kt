package dev.hydrocap.app.ui

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import dev.hydrocap.app.FloatingTabBar
import dev.hydrocap.app.data.*
import dev.hydrocap.app.domain.BottleProfile
import dev.hydrocap.app.ui.theme.HydroCapTheme
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import java.time.Instant

/** Synthetic rendered fixtures only; never clear app data, contact BLE or write Health records. */
class ParityComposeTest {
    @get:Rule val compose=createComposeRule()
    private fun syntheticSettings()=AppSettings("LARQ_synthetic","synthetic",10,5,false,BottleProfile.DEFAULT.id,null,null,null,emptySet(),false,null,null,0)
    @Test fun actualGaugeCardsHaveEqualHeightsAt360dpEmptyBattery() {
        compose.setContent { HydroCapTheme { Box(Modifier.width(360.dp).padding(16.dp)) { HomeGaugeCards(HomeUiState(settings=syntheticSettings(),fill=FillEstimate(480.0,70.0,50,10,1))) } } }
        val bottle=compose.onNodeWithTag("bottle-card").fetchSemanticsNode().boundsInRoot
        val battery=compose.onNodeWithTag("battery-card").fetchSemanticsNode().boundsInRoot
        assertEquals(bottle.height,battery.height,.1f); compose.onNodeWithText("No data").assertIsDisplayed()
    }
    @Test fun equalHeightIsPreservedInDarkModeAtLargeFontAndCriticalBattery() {
        compose.setContent { val density=LocalDensity.current; CompositionLocalProvider(LocalDensity provides Density(density.density,1.4f)) { HydroCapTheme(appearance="dark") { Box(Modifier.width(360.dp).padding(16.dp)) { HomeGaugeCards(HomeUiState(settings=syntheticSettings(),battery=BatterySample(1,4))) } } } }
        assertEquals(compose.onNodeWithTag("bottle-card").fetchSemanticsNode().boundsInRoot.height,compose.onNodeWithTag("battery-card").fetchSemanticsNode().boundsInRoot.height,.1f)
        compose.onNodeWithText("Charge now").assertIsDisplayed()
    }
    @Test fun welcomeStepAndActionsAreDistinctFullTargets() {
        compose.setContent { HydroCapTheme { Column(Modifier.width(360.dp)) { OnboardingStepIndicator(1); OnboardingWelcomeActions(true,false,{},{},{}) } } }
        compose.onNodeWithContentDescription("Step 1 of 3").assertIsDisplayed()
        val connect=compose.onNodeWithTag("connect-health").fetchSemanticsNode().boundsInRoot
        val skip=compose.onNodeWithTag("not-now").fetchSemanticsNode().boundsInRoot
        assertTrue(skip.height>=44*compose.density.density); assertTrue(skip.top>connect.bottom); assertTrue(skip.width>=connect.width)
    }
    @Test fun actualHomeHasNoSyncButtonAndShowAllAction() {
        var opened=false
        compose.setContent { HydroCapTheme { HomeScreen(HomeUiState(settings=syntheticSettings(),tofCount=1),{}, {opened=true}) } }
        compose.onNodeWithText("Sync now").assertDoesNotExist(); compose.onNodeWithText("Show all").performScrollTo().performClick(); assertTrue(opened)
    }
    @Test fun todayGoalAlignsToRightCardContentWhileMetricStaysTogether() {
        compose.setContent { HydroCapTheme { HomeScreen(HomeUiState(settings=syntheticSettings(),tofCount=1,todayMl=593.0),{}, {}) } }
        val card=compose.onNodeWithTag("today-card").fetchSemanticsNode().boundsInRoot
        val goal=compose.onNodeWithText("of 2.00 L").fetchSemanticsNode().boundsInRoot
        val number=compose.onNodeWithText("593").fetchSemanticsNode().boundsInRoot
        val unit=compose.onNodeWithText("ml").fetchSemanticsNode().boundsInRoot
        assertEquals(card.right-20*compose.density.density,goal.right,1f)
        assertTrue(unit.left>=number.right)
        assertTrue(unit.left-number.right<=7*compose.density.density)
    }
    @Test fun nativeTabsNavigateAndRetainSelectedSemantics() {
        compose.setContent { var screen by remember {mutableStateOf<Screen>(Screen.Home)}; HydroCapTheme { FloatingTabBar(screen) {screen=it} } }
        compose.onNodeWithContentDescription("Home").assertIsSelected(); compose.onNodeWithContentDescription("History").performClick().assertIsSelected(); compose.onNodeWithContentDescription("Settings").performClick().assertIsSelected()
    }
    @Test fun hourlyHistoryHidesFixedAxisChoiceAndOverridesLegacyPreference() {
        val now = Instant.parse("2026-09-30T12:00:00Z")
        val events = listOf(20.0, 50.0, 100.0).mapIndexed { i, amount -> DrinkEvent(now.minusSeconds((3 - i) * 3600L).epochSecond, amount, i.toLong(), "synthetic") }
        compose.setContent { HydroCapTheme {
            HistoryScreen(DrinkSnapshot(events, true), syntheticSettings().copy(historyRange = "1d", historyYAxis = "fixed"), now, 6000) { _, _, _ -> }
        } }
        compose.onNodeWithTag("history-chart").performScrollTo().assert(SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.StateDescription, "Y axis: 0 to 110 ml. Daily goal line hidden."))
        compose.onNodeWithTag("chart-menu").performScrollTo().performClick()
        compose.onNodeWithText("Y axis: Auto").assertIsNotEnabled()
        compose.onNodeWithText("Fixed to target", substring = true).assertDoesNotExist()
    }

    @Test fun longerAutoHistoryReportsOffScaleGoalWithoutClaimingADashedLine() {
        val now = Instant.parse("2026-09-30T12:00:00Z")
        compose.setContent { HydroCapTheme {
            HistoryScreen(DrinkSnapshot(listOf(DrinkEvent(now.minusSeconds(3600).epochSecond, 600.0, 1, "synthetic")), true), syntheticSettings().copy(historyRange = "7d", historyYAxis = "auto"), now, 2000) { _, _, _ -> }
        } }
        compose.onNodeWithTag("history-chart").performScrollTo().assert(SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.StateDescription, "Y axis: 0 to 660 ml. Daily goal line hidden."))
        compose.onNodeWithText("Daily goal: 2000 ml/day (above chart scale).", substring = true).performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Dashed line = daily goal", substring = true).assertDoesNotExist()
    }

    @Test fun nativeHistoryControlsAndGapsUseActualDrawnChart() {
        val now=Instant.parse("2026-09-30T12:00:00Z")
        compose.setContent { var settings by remember {mutableStateOf(syntheticSettings())}; HydroCapTheme {
            HistoryScreen(DrinkSnapshot(listOf(DrinkEvent(now.minusSeconds(3600).epochSecond,250.0,1,"synthetic")),true),settings,now,2000) {range,chart,axis -> settings=settings.copy(historyRange=range ?: settings.historyRange,historyChartType=chart ?: settings.historyChartType,historyYAxis=axis ?: settings.historyYAxis)}
        } }
        compose.onNodeWithText("1 D").performClick().assertIsSelected()
        compose.onNodeWithTag("chart-menu").performClick(); compose.onNodeWithText("Line").performClick()
        compose.onNodeWithTag("history-chart").performScrollTo().assertExists()
        val chart=compose.onNodeWithTag("history-chart").fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.ContentDescription].joinToString()
        assertTrue(chart.contains("no recorded drinks")); assertTrue(chart.contains("milliliters per hour"))
    }
}
