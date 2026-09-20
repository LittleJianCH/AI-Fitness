package com.aifitness

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.aifitness.contract.*
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

@Composable
fun SettingsScreen(state: FitnessState, model: FitnessViewModel) {
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.testTag("settings"),
    ) {
        item {
            Text(
                stringResource(R.string.settings_intro),
                style = MaterialTheme.typography.titleMedium,
            )
        }
        listOf(
                R.string.software_settings to Screen.Software,
                R.string.body_settings to Screen.Body,
                R.string.equipment to Screen.Equipment,
                R.string.account_sessions to Screen.Account,
            )
            .forEach { (label, screen) ->
                item {
                    Card(onClick = { model.navigate(screen) }, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(label), Modifier.padding(20.dp))
                    }
                }
            }
        item {
            Text(
                stringResource(
                    R.string.settings_revision,
                    state.settings?.settingsRevision ?: stringResource(R.string.loading),
                )
            )
        }
        item {
            TextButton(onClick = model::refreshSettings, enabled = !state.busy) {
                Text(stringResource(R.string.reload_settings))
            }
        }
    }
}

@Composable
fun SoftwareScreen(state: FitnessState, model: FitnessViewModel) {
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            SectionCard(stringResource(R.string.appearance)) {
                state.settings?.let { settings ->
                    listOf(
                            Appearance.systemAppearance to
                                stringResource(R.string.system_appearance),
                            Appearance.lightAppearance to stringResource(R.string.light_appearance),
                            Appearance.darkAppearance to stringResource(R.string.dark_appearance),
                        )
                        .forEach { (appearance, label) ->
                            Row {
                                RadioButton(
                                    selected =
                                        settings.settingsSoftware.softwareAppearance == appearance,
                                    onClick = {
                                        model.saveSettings(
                                            settings.copy(
                                                settingsSoftware = SoftwareSettings(appearance)
                                            )
                                        )
                                    },
                                    enabled = !state.busy,
                                )
                                Text(label, Modifier.padding(top = 12.dp))
                            }
                        }
                }
            }
        }
        item {
            SectionCard(stringResource(R.string.connection_display)) {
                ValueRow(stringResource(R.string.server), state.endpoint)
                ValueRow(stringResource(R.string.units), stringResource(R.string.metric_units))
                ValueRow(stringResource(R.string.local_time_zone), ZoneId.systemDefault().id)
            }
        }
    }
}

private class FormFailure(val resource: Int) : IllegalArgumentException()

private data class SportDraft(
    val watts: String = "",
    val resting: String = "",
    val threshold: String = "",
    val maximum: String = "",
    val weighting: LoadWeighting? = null,
) {
    fun value(): SportProfile {
        val hrFields = listOf(resting, threshold, maximum).map(::optionalNumber)
        val heart =
            if (hrFields.all { it == null }) null
            else {
                if (!(hrFields.all { it != null } && weighting != null))
                    throw FormFailure(R.string.invalid_heart_profile)
                if (!(hrFields[0]!! < hrFields[1]!! && hrFields[1]!! <= hrFields[2]!!))
                    throw FormFailure(R.string.invalid_heart_order)
                HeartRateProfile(
                    heartRateResting = hrFields[0]!!,
                    heartRateThreshold = hrFields[1]!!,
                    heartRateMaximum = hrFields[2]!!,
                    heartRateWeighting = weighting,
                )
            }
        return SportProfile(sportThresholdWatts = optionalNumber(watts), sportHeartRate = heart)
    }

    companion object {
        fun from(profile: SportProfile?) =
            SportDraft(
                profile?.sportThresholdWatts?.toString().orEmpty(),
                profile?.sportHeartRate?.heartRateResting?.toString().orEmpty(),
                profile?.sportHeartRate?.heartRateThreshold?.toString().orEmpty(),
                profile?.sportHeartRate?.heartRateMaximum?.toString().orEmpty(),
                profile?.sportHeartRate?.heartRateWeighting,
            )
    }
}

private fun optionalNumber(input: String): Double? {
    if (input.isBlank()) return null
    val value = input.toDoubleOrNull()
    if (value == null || !value.isFinite() || value <= 0)
        throw FormFailure(R.string.invalid_positive)
    return value
}

@Composable
private fun SportFields(
    title: String,
    key: String,
    value: SportDraft,
    change: (SportDraft) -> Unit,
) {
    Text(title, style = MaterialTheme.typography.titleLarge)
    Field(stringResource(R.string.sport_ftp, title), value.watts, "$key-watts") {
        change(value.copy(watts = it))
    }
    Field(stringResource(R.string.sport_resting, title), value.resting, "$key-resting") {
        change(value.copy(resting = it))
    }
    Field(stringResource(R.string.sport_threshold, title), value.threshold, "$key-threshold") {
        change(value.copy(threshold = it))
    }
    Field(stringResource(R.string.sport_maximum, title), value.maximum, "$key-maximum") {
        change(value.copy(maximum = it))
    }
    Text(stringResource(R.string.trimp_hint))
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        listOf(LoadWeighting.exponent192 to "1.92", LoadWeighting.exponent167 to "1.67").forEach {
            (weighting, title) ->
            FilterChip(
                value.weighting == weighting,
                { change(value.copy(weighting = weighting)) },
                label = { Text(title) },
            )
        }
    }
}

@Composable
fun Field(label: String, value: String, tag: String, change: (String) -> Unit) {
    OutlinedTextField(
        value,
        change,
        label = { Text(label) },
        singleLine = true,
        modifier = Modifier.fillMaxWidth().testTag(tag),
    )
}

@Composable
fun BodyScreen(state: FitnessState, model: FitnessViewModel) {
    val settings = state.settings ?: return
    val latest = settings.settingsBodyProfiles.lastOrNull()
    var editing by remember(settings.settingsRevision) { mutableStateOf(false) }
    var mass by
        remember(settings.settingsRevision) {
            mutableStateOf(latest?.bodyMassKilograms?.toString().orEmpty())
        }
    var height by
        remember(settings.settingsRevision) {
            mutableStateOf(latest?.bodyHeightMetres?.toString().orEmpty())
        }
    var effective by
        remember(settings.settingsRevision) { mutableStateOf(Instant.now().toString()) }
    var cycling by
        remember(settings.settingsRevision) { mutableStateOf(SportDraft.from(latest?.bodyCycling)) }
    var running by
        remember(settings.settingsRevision) { mutableStateOf(SportDraft.from(latest?.bodyRunning)) }
    var error by remember { mutableStateOf<Int?>(null) }
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier.testTag("bodySettings"),
    ) {
        item { Text(stringResource(R.string.body_history_hint)) }
        if (!editing)
            item {
                Button(onClick = { editing = true }, enabled = !state.busy) {
                    Text(stringResource(R.string.update_body))
                }
            }
        else {
            item {
                Field(stringResource(R.string.effective_time), effective, "effective_time") {
                    effective = it
                }
            }
            item { Field(stringResource(R.string.body_mass), mass, "body_mass") { mass = it } }
            item { Field(stringResource(R.string.height), height, "height") { height = it } }
            item {
                SportFields(stringResource(R.string.cycling), "cycling", cycling) { cycling = it }
            }
            item {
                SportFields(stringResource(R.string.running), "running", running) { running = it }
            }
            item {
                error?.let { Text(stringResource(it), color = MaterialTheme.colorScheme.error) }
                Row {
                    Button(
                        onClick = {
                            try {
                                val profile =
                                    BodyProfile(
                                        bodyProfileId = UUID.randomUUID().toString(),
                                        bodyEffectiveFrom = parseInstant(effective).toString(),
                                        bodyMassKilograms = optionalNumber(mass),
                                        bodyHeightMetres = optionalNumber(height),
                                        bodyCycling = cycling.value(),
                                        bodyRunning = running.value(),
                                    )
                                model.saveSettings(
                                    settings.copy(
                                        settingsBodyProfiles =
                                            settings.settingsBodyProfiles + profile
                                    )
                                )
                                error = null
                            } catch (failure: IllegalArgumentException) {
                                error =
                                    (failure as? FormFailure)?.resource ?: R.string.invalid_input
                            } catch (_: java.time.format.DateTimeParseException) {
                                error = R.string.invalid_effective_time
                            }
                        },
                        enabled = !state.busy,
                        modifier = Modifier.testTag("saveBody"),
                    ) {
                        Text(stringResource(R.string.save_body))
                    }
                    TextButton(onClick = { editing = false }, enabled = !state.busy) {
                        Text(stringResource(R.string.cancel))
                    }
                }
            }
        }
        items(settings.settingsBodyProfiles.reversed(), key = { it.bodyProfileId }) { profile ->
            SectionCard(dateTime(profile.bodyEffectiveFrom)) {
                ValueRow(
                    stringResource(R.string.mass_height),
                    "${number(profile.bodyMassKilograms, "kg")} / ${number(profile.bodyHeightMetres, "m", 2)}",
                )
                listOf(
                        stringResource(R.string.cycling) to profile.bodyCycling,
                        stringResource(R.string.running) to profile.bodyRunning,
                    )
                    .forEach { (label, sport) ->
                        ValueRow(
                            stringResource(R.string.sport_ftp_summary, label),
                            number(sport.sportThresholdWatts, "W"),
                        )
                        sport.sportHeartRate?.let { hr ->
                            ValueRow(
                                stringResource(R.string.sport_heart_summary, label),
                                "${number(hr.heartRateResting)} / ${number(hr.heartRateThreshold)} / ${number(hr.heartRateMaximum)}",
                            )
                            ValueRow(
                                stringResource(R.string.trimp_exponent),
                                if (hr.heartRateWeighting == LoadWeighting.exponent192) "1.92"
                                else "1.67",
                            )
                        }
                    }
            }
        }
    }
}

@Composable
fun EquipmentScreen(state: FitnessState, model: FitnessViewModel) {
    val settings = state.settings ?: return
    var editing by remember(settings.settingsRevision) { mutableStateOf(false) }
    var selected by remember(settings.settingsRevision) { mutableStateOf<Equipment?>(null) }
    var name by remember(settings.settingsRevision) { mutableStateOf("") }
    var mass by remember(settings.settingsRevision) { mutableStateOf("") }
    var kind by remember(settings.settingsRevision) { mutableStateOf(EquipmentKind.bicycle) }
    var retired by remember(settings.settingsRevision) { mutableStateOf(false) }
    var error by remember { mutableStateOf<Int?>(null) }
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item { Text(stringResource(R.string.equipment_hint)) }
        item {
            Button(
                onClick = {
                    selected = null
                    name = ""
                    mass = ""
                    retired = false
                    kind = EquipmentKind.bicycle
                    editing = true
                },
                enabled = !state.busy,
            ) {
                Text(stringResource(R.string.add_equipment))
            }
        }
        if (editing)
            item {
                SectionCard(
                    if (selected == null) stringResource(R.string.new_equipment)
                    else stringResource(R.string.edit_equipment)
                ) {
                    Field(stringResource(R.string.equipment_name), name, "equipment_name") {
                        name = it
                    }
                    Field(stringResource(R.string.equipment_mass), mass, "equipment_mass") {
                        mass = it
                    }
                    if (selected == null)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            FilterChip(
                                kind == EquipmentKind.bicycle,
                                { kind = EquipmentKind.bicycle },
                                label = { Text(stringResource(R.string.bicycle)) },
                            )
                            FilterChip(
                                kind == EquipmentKind.runningShoes,
                                { kind = EquipmentKind.runningShoes },
                                label = { Text(stringResource(R.string.running_shoes)) },
                            )
                        }
                    Row {
                        Checkbox(retired, { retired = it })
                        Text(stringResource(R.string.retired), Modifier.padding(top = 12.dp))
                    }
                    error?.let { Text(stringResource(it), color = MaterialTheme.colorScheme.error) }
                    Row {
                        Button(
                            onClick = {
                                try {
                                    if (name.isBlank())
                                        throw FormFailure(R.string.invalid_equipment_name)
                                    val item =
                                        Equipment(
                                            equipmentId =
                                                selected?.equipmentId
                                                    ?: UUID.randomUUID().toString(),
                                            equipmentKind = selected?.equipmentKind ?: kind,
                                            equipmentName = name.trim(),
                                            equipmentMassKilograms = optionalNumber(mass),
                                            equipmentRetired = retired,
                                        )
                                    val equipment =
                                        if (selected == null) settings.settingsEquipment + item
                                        else
                                            settings.settingsEquipment.map {
                                                if (it.equipmentId == item.equipmentId) item else it
                                            }
                                    model.saveSettings(settings.copy(settingsEquipment = equipment))
                                    error = null
                                } catch (failure: IllegalArgumentException) {
                                    error =
                                        (failure as? FormFailure)?.resource
                                            ?: R.string.invalid_input
                                }
                            },
                            enabled = !state.busy,
                            modifier = Modifier.testTag("saveEquipment"),
                        ) {
                            Text(stringResource(R.string.save_equipment))
                        }
                        TextButton(onClick = { editing = false }, enabled = !state.busy) {
                            Text(stringResource(R.string.cancel))
                        }
                    }
                }
            }
        items(settings.settingsEquipment, key = { it.equipmentId }) { equipment ->
            SectionCard(equipment.equipmentName) {
                ValueRow(
                    stringResource(R.string.type),
                    if (equipment.equipmentKind == EquipmentKind.bicycle)
                        stringResource(R.string.bicycle)
                    else stringResource(R.string.running_shoes),
                )
                ValueRow(
                    stringResource(R.string.mass),
                    number(equipment.equipmentMassKilograms, "kg"),
                )
                ValueRow(
                    stringResource(R.string.status),
                    if (equipment.equipmentRetired) stringResource(R.string.retired)
                    else stringResource(R.string.in_use),
                )
                TextButton(
                    onClick = {
                        selected = equipment
                        name = equipment.equipmentName
                        mass = equipment.equipmentMassKilograms?.toString().orEmpty()
                        kind = equipment.equipmentKind
                        retired = equipment.equipmentRetired
                        editing = true
                    }
                ) {
                    Text(stringResource(R.string.edit))
                }
            }
        }
    }
}

@Composable
fun AccountScreen(state: FitnessState, model: FitnessViewModel) {
    var current by remember { mutableStateOf("") }
    var new by remember { mutableStateOf("") }
    var confirmAll by remember { mutableStateOf(false) }
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            SectionCard(stringResource(R.string.account)) {
                ValueRow(stringResource(R.string.username), state.user?.username.orEmpty())
                ValueRow(stringResource(R.string.server), state.endpoint)
                Button(
                    onClick = model::logout,
                    enabled = !state.busy,
                    modifier = Modifier.testTag("logout"),
                ) {
                    Text(stringResource(R.string.logout))
                }
                Text(stringResource(R.string.logout_hint))
                if (state.message != null)
                    TextButton(onClick = model::forgetLocalSession, enabled = !state.busy) {
                        Text(stringResource(R.string.forget_local))
                    }
            }
        }
        item {
            SectionCard(stringResource(R.string.change_password)) {
                OutlinedTextField(
                    current,
                    { current = it },
                    label = { Text(stringResource(R.string.current_password)) },
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions =
                        KeyboardOptions(
                            keyboardType = KeyboardType.Password,
                            autoCorrectEnabled = false,
                        ),
                    modifier = Modifier.fillMaxWidth().testTag("currentPassword"),
                )
                OutlinedTextField(
                    new,
                    { new = it },
                    label = { Text(stringResource(R.string.new_password)) },
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions =
                        KeyboardOptions(
                            keyboardType = KeyboardType.Password,
                            autoCorrectEnabled = false,
                        ),
                    modifier = Modifier.fillMaxWidth().testTag("newPassword"),
                )
                Text(stringResource(R.string.password_hint))
                Button(
                    onClick = {
                        model.changePassword(current, new)
                        current = ""
                        new = ""
                    },
                    enabled = !state.busy && current.isNotEmpty() && new.isNotEmpty(),
                ) {
                    Text(stringResource(R.string.change_password_logout))
                }
            }
        }
        item {
            Row {
                TextButton(onClick = model::loadSessions, enabled = !state.busy) {
                    Text(stringResource(R.string.refresh_sessions))
                }
                TextButton(onClick = { confirmAll = true }, enabled = !state.busy) {
                    Text(stringResource(R.string.revoke_all))
                }
            }
        }
        items(state.sessions, key = { it.id }) { session ->
            SectionCard(session.deviceName ?: stringResource(R.string.device_session)) {
                Text(
                    if (session.current) stringResource(R.string.current_session)
                    else stringResource(R.string.other_session)
                )
                ValueRow(stringResource(R.string.last_active), dateTime(session.lastSeenAt))
                ValueRow(stringResource(R.string.expires), dateTime(session.absoluteExpiresAt))
                TextButton(onClick = { model.revokeSession(session) }, enabled = !state.busy) {
                    Text(stringResource(R.string.revoke_session))
                }
            }
        }
    }
    if (confirmAll)
        AlertDialog(
            onDismissRequest = { confirmAll = false },
            title = { Text(stringResource(R.string.revoke_all_title)) },
            text = { Text(stringResource(R.string.revoke_all_hint)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmAll = false
                        model.revokeAll()
                    }
                ) {
                    Text(stringResource(R.string.revoke))
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmAll = false }) {
                    Text(stringResource(R.string.cancel))
                }
            },
        )
}
