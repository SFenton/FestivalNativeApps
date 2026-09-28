package com.festivalscoretracker.android.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.BuildConfig
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.nav.LicensesRoute
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.presentation.ShellViewModel
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.SectionHeader
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Settings

/**
 * Settings (first slice): profile, visible instruments, additive accessibility
 * overrides and About. Every value persists across cold starts via DataStore.
 *
 * @param settings Effective settings.
 * @param shellViewModel Settings actions.
 * @param serviceOrigin Active service origin (shown in About).
 */
@Composable
fun SettingsScreen(settings: AppSettings, shellViewModel: ShellViewModel, serviceOrigin: String) {
    val shell = LocalShellActions.current
    FestivalScreen(title = "Settings", isRoot = true) { padding ->
        LazyColumn(
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 24.dp),
            modifier = Modifier.fillMaxSize().testTag("fst.settings.list"),
        ) {
            item(key = "profile-header") { SectionHeader("Profile") }
            item(key = "profile") {
                GlassCard(Modifier.fillMaxWidth()) {
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(16.dp)) {
                        Text(
                            settings.selectedPlayer?.displayName ?: "No player selected",
                            color = BrandTokens.textPrimary,
                            modifier = Modifier.weight(1f),
                        )
                        if (settings.selectedPlayer != null) {
                            OutlinedButton(onClick = shellViewModel::deselectPlayer) { Text("Deselect") }
                        } else {
                            TextButton(onClick = shell.openProfile) { Text("Choose Profile") }
                        }
                    }
                }
            }
            item(key = "instruments-header") { SectionHeader("Instruments") }
            item(key = "instruments") {
                GlassCard(Modifier.fillMaxWidth()) {
                    Instrument.entries.forEach { instrument ->
                        SettingSwitch(
                            label = instrument.label,
                            checked = instrument in settings.visibleInstruments,
                            onChange = { shellViewModel.setInstrumentVisible(instrument, it) },
                            tag = "fst.settings.instrument.${instrument.wireId}",
                        ) { InstrumentIcon(instrument, size = 28.dp, decorative = true) }
                    }
                }
            }
            item(key = "accessibility-header") { SectionHeader("Accessibility") }
            item(key = "accessibility") {
                GlassCard(Modifier.fillMaxWidth()) {
                    SettingSwitch("Increase Contrast", settings.increaseContrast, shellViewModel::setIncreaseContrast, "fst.settings.contrast")
                    SettingSwitch("Reduce Motion", settings.reduceMotion, shellViewModel::setReduceMotion, "fst.settings.motion")
                }
            }
            item(key = "about-header") { SectionHeader("About") }
            item(key = "about") {
                GlassCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("Version ${BuildConfig.VERSION_NAME}", color = BrandTokens.textPrimary)
                        Text("Service: $serviceOrigin", style = MaterialTheme.typography.bodySmall, color = BrandTokens.textMuted)
                        TextButton(onClick = { shell.navigate(LicensesRoute) }) { Text("Licenses") }
                    }
                }
            }
        }
    }
}

@Composable
private fun SettingSwitch(label: String, checked: Boolean, onChange: (Boolean) -> Unit, tag: String, leading: (@Composable () -> Unit)? = null) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .toggleable(value = checked, role = Role.Switch, onValueChange = onChange)
            .padding(horizontal = 16.dp)
            .testTag(tag),
    ) {
        leading?.invoke()
        Text(label, color = BrandTokens.textPrimary, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = null)
    }
}

// endregion
