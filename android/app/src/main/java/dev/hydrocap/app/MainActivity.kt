package dev.hydrocap.app

import android.Manifest
import android.content.*
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.widget.Toast
import androidx.activity.*
import androidx.activity.compose.*
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.core.net.toUri
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import dev.hydrocap.app.ble.BleScanner
import dev.hydrocap.app.debug.DebugActions
import dev.hydrocap.app.health.*
import dev.hydrocap.app.sync.*
import dev.hydrocap.app.ui.*
import dev.hydrocap.app.ui.theme.*
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val container get() = (application as HydroCapApp).container
    private val model: MainViewModel by viewModels { MainViewModel.Factory(container) }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        handleDebugIntent(intent)
        setContent {
            val settings by model.settings.collectAsStateWithLifecycle()
            HydroCapTheme(appearance = settings?.appearance ?: "system") {
                val colors = MaterialTheme.colorScheme
                SideEffect {
                    val light = colors.background != androidx.compose.ui.graphics.Color.Black
                    WindowCompat.getInsetsController(window,window.decorView).apply { isAppearanceLightStatusBars=light; isAppearanceLightNavigationBars=light }
                }
                Scaffold(contentWindowInsets = WindowInsets.safeDrawing, containerColor=colors.background) { padding -> AppContent(Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding).imePadding()) }
            }
        }
    }
    override fun onResume() { super.onResume(); model.refreshForeground() }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); handleDebugIntent(intent) }
    private fun handleDebugIntent(intent: Intent?) {
        if (!BuildConfig.DEBUG || intent == null || !DebugActions.isDebugAction(intent.action ?: "")) return
        if (!AppPermissions.hasEssential(this)) { container.debugLog.log("debug","BLE permission missing"); return }
        model.navigate(Screen.Debug); DebugActions.handle(intent,this,container,lifecycleScope); intent.action=Intent.ACTION_MAIN
    }
    @Composable
    private fun AppContent(modifier: Modifier) {
        val screen by model.screen.collectAsStateWithLifecycle()
        val home by model.home.collectAsStateWithLifecycle()
        val state by model.settingsUi.collectAsStateWithLifecycle()
        val permission by model.permissions.collectAsStateWithLifecycle()
        val notice by model.notice.collectAsStateWithLifecycle()
        var healthFromWelcome by rememberSaveable { mutableStateOf(false) }
        var bluetoothFromWelcome by rememberSaveable { mutableStateOf(false) }
        var healthBusy by rememberSaveable { mutableStateOf(false) }
        val bluetoothLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
            model.refreshForeground()
            if (bluetoothFromWelcome) { bluetoothFromWelcome=false; model.advanceFromWelcome() }
            else if (AppPermissions.hasEssential(this)) model.startScan()
        }
        val notificationLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { model.refreshForeground() }
        fun finishWelcome() {
            if (AppPermissions.hasEssential(this)) model.advanceFromWelcome()
            else { bluetoothFromWelcome=true; bluetoothLauncher.launch(AppPermissions.essential().toTypedArray()) }
        }
        val healthLauncher = rememberLauncherForActivityResult(PermissionController.createRequestPermissionResultContract()) { granted ->
            healthBusy=false
            if (HealthConnectSupport.HYDRATION_WRITE_PERMISSION in granted) model.enableHealthSync() else model.onHealthPermissionDenied()
            // Always refresh body data, independently of hydration-write outcome.
            model.refreshForeground()
            if (healthFromWelcome) { healthFromWelcome=false; finishWelcome() }
        }
        fun requestHealth(welcome: Boolean = false, writeOnly: Boolean = false) {
            if (HealthConnectSupport.availability(this) != HealthConnectSupport.Availability.AVAILABLE) { openHealthSettings(); return }
            healthFromWelcome=welcome; healthBusy=true
            healthLauncher.launch(if (writeOnly) HealthConnectSupport.REQUIRED_PERMISSIONS else HealthConnectBodyReader.ONBOARDING_PERMISSIONS)
        }
        fun requestBluetooth() { bluetoothFromWelcome=false; bluetoothLauncher.launch(AppPermissions.essential().toTypedArray()) }
        fun requestNotifications() { if (android.os.Build.VERSION.SDK_INT >= 33) notificationLauncher.launch(Manifest.permission.POST_NOTIFICATIONS) else openAppSettings() }
        LaunchedEffect(screen,permission.bluetooth) {
            if (screen == Screen.Onboarding && permission.bluetooth && !model.scan.value.scanning) model.startScan()
            if (screen == Screen.Scan && permission.bluetooth && !model.scan.value.scanning && model.scan.value.pairingId == null) model.startScan()
        }
        val tabs = screen !in listOf(Screen.Loading,Screen.Onboarding,Screen.Optional,Screen.Scan)
        BackHandler(enabled = screen !in listOf(Screen.Home,Screen.Onboarding,Screen.Loading)) { model.back() }
        Box(modifier) {
            Column(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f)) {
                    when(screen) {
                        Screen.Loading -> Box(Modifier.fillMaxSize(),contentAlignment=Alignment.Center) { CircularProgressIndicator() }
                        Screen.Onboarding -> OnboardingScreen(state.body,healthBusy,{requestHealth(true)},{finishWelcome()},{openHealthSettings()})
                        Screen.Optional -> OptionalScreen(state,permission,{requestHealth()},{openHealthSettings()},{requestBluetooth()},{requestNotifications()},{openAppSettings()},model::setManualBody,model::findBottle)
                        Screen.Scan -> {
                            val scan by model.scan.collectAsStateWithLifecycle()
                            ScanScreen(scan,permission.bluetooth,state.settings?.hasPairedDevice == true,{model.startScan()},model::selectCap,{requestBluetooth()},{openAppSettings()},model::back)
                        }
                        Screen.Home -> HomeScreen(home,{ if (AppPermissions.hasEssential(this@MainActivity)) SyncService.start(this@MainActivity) else { Toast.makeText(this@MainActivity,"Allow Bluetooth access in Settings to sync.",Toast.LENGTH_SHORT).show() } },{model.navigate(Screen.AllDrinks)})
                        Screen.History -> {
                            val snapshot by model.allDrinks.collectAsStateWithLifecycle(); val now by model.clock.collectAsStateWithLifecycle()
                            HistoryScreen(snapshot,state.settings,now,state.targetMl) { range,chart,axis -> model.setHistory(range,chart,axis) }
                        }
                        Screen.AllDrinks -> { val snapshot by model.allDrinks.collectAsStateWithLifecycle(); AllDrinksScreen(snapshot,model::back) }
                        Screen.Settings -> SettingsScreen(state,container.syncEngine.isRunning || container.connectionHandoff.isRunning,
                            model::setAppearance,{model.navigate(Screen.Reminder)},{model.navigate(Screen.BottleProfile)},model::setDailyTarget,model::setManualBody,model::setBatteryThresholds,
                            { enabled -> if (!enabled) model.disableHealthSync() else if (state.body.hydrationPermission) model.enableHealthSync() else requestHealth(writeOnly=true) },
                            {openHealthSettings()},{requestHealth()},model::writeAllToHealthConnect,model::setDrinkReminders,{openNotificationSettings()},model::setBackgroundSyncEnabled,
                            {model.navigate(Screen.Scan)},model::forgetDevice,{model.navigate(Screen.Debug)})
                        Screen.BottleProfile -> BottleProfileScreen(state,model::setBottleProfile,model::back)
                        Screen.Reminder -> { val reminder by container.syncEngine.reminder.collectAsStateWithLifecycle()
                            ReminderScreen(reminder,{SyncService.start(this@MainActivity,SyncService.MODE_READ_REMINDER)},{SyncService.applyReminder(this@MainActivity,it)},model::back) }
                        Screen.Debug -> { val entries by model.debugEntries.collectAsStateWithLifecycle()
                            val liveTof by container.syncEngine.lastLiveTof.collectAsStateWithLifecycle()
                            DebugScreen(entries,home.syncStatus is SyncStatus.Running,state.settings?.lastBackgroundRunMs?.let { "${formatDateTime(it)} · ${state.settings?.lastBackgroundOutcome}" } ?: "Never",
                                {copyDebugLog()},{SyncService.start(this@MainActivity,SyncService.MODE_LIVE_TOF)},{SyncService.start(this@MainActivity,SyncService.MODE_READ_ALL)},
                                {lifecycleScope.launch { DebugActions.debugScan(container,BleScanner.DEFAULT_SCAN_MS) }},model::clearDebugLog,model::back,
                                home=home,onSync={SyncService.start(this@MainActivity)},onReadReminder={SyncService.start(this@MainActivity,SyncService.MODE_READ_REMINDER)},liveTof=liveTof) }
                    }
                }
                if (tabs) FloatingTabBar(screen,model::navigate)
            }
            notice?.let { Surface(Modifier.align(Alignment.TopCenter).padding(top=8.dp),shape=RoundedCornerShape(50.dp),color=MaterialTheme.colorScheme.surface.copy(alpha=.95f),shadowElevation=6.dp) { Text(it,Modifier.padding(horizontal=20.dp,vertical=12.dp).semantics { liveRegion=LiveRegionMode.Polite }) } }
        }
    }
    private fun openAppSettings() { startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,"package:$packageName".toUri())) }
    private fun openNotificationSettings() { startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE,packageName)) }
    private fun openHealthSettings() {
        val available = HealthConnectSupport.availability(this) == HealthConnectSupport.Availability.AVAILABLE
        val target = if (available) Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS) else Intent(Intent.ACTION_VIEW,"market://details?id=com.google.android.apps.healthdata".toUri())
        try { startActivity(target) } catch (_: ActivityNotFoundException) { startActivity(Intent(Settings.ACTION_SETTINGS)) }
    }
    private fun copyDebugLog() {
        (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("HydroCap debug log",model.debugText()))
        Toast.makeText(this,R.string.debug_copied,Toast.LENGTH_SHORT).show()
    }
}
@Composable
fun FloatingTabBar(screen: Screen, onNavigate: (Screen) -> Unit) {
    val active = when(screen) { Screen.History -> 1; Screen.Settings,Screen.Reminder,Screen.Debug,Screen.BottleProfile -> 2; else -> 0 }
    Surface(Modifier.fillMaxWidth().padding(horizontal=32.dp).padding(top=8.dp,bottom=10.dp).testTag("tab-bar"),shape=RoundedCornerShape(40.dp),color=MaterialTheme.colorScheme.surface.copy(alpha=.93f),shadowElevation=5.dp) {
        Row(Modifier.padding(5.dp),horizontalArrangement=Arrangement.spacedBy(3.dp)) {
            listOf(Triple("Home",HydroGlyph.HOME,Screen.Home),Triple("History",HydroGlyph.HISTORY,Screen.History),Triple("Settings",HydroGlyph.SETTINGS,Screen.Settings)).forEachIndexed { i,(title,icon,destination) ->
                Column(Modifier.weight(1f).background(if (i==active) WaterBlue.copy(alpha=.14f) else androidx.compose.ui.graphics.Color.Transparent,RoundedCornerShape(30.dp))
                    .clickable { onNavigate(destination) }.heightIn(min=54.dp).semantics { contentDescription=title; selected=i==active; role=Role.Tab }.padding(vertical=5.dp),horizontalAlignment=Alignment.CenterHorizontally) {
                    HydroIcon(icon,Modifier.size(22.dp),color=if(i==active) WaterBlue else MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(title,style=MaterialTheme.typography.labelSmall,color=if(i==active) WaterBlue else MaterialTheme.colorScheme.onSurfaceVariant,modifier=Modifier.clearAndSetSemantics {})
                }
            }
        }
    }
}
