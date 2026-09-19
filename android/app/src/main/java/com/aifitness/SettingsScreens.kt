package com.aifitness

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
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
        item { Text("你的偏好、身体参数与运动器材。", style = MaterialTheme.typography.titleMedium) }
        listOf(
                "软件设置" to Screen.Software,
                "个人身体参数" to Screen.Body,
                "器材" to Screen.Equipment,
                "账号与登录会话" to Screen.Account,
            )
            .forEach { (label, screen) ->
                item {
                    Card(onClick = { model.navigate(screen) }, modifier = Modifier.fillMaxWidth()) {
                        Text(label, Modifier.padding(20.dp))
                    }
                }
            }
        item { Text("已保存到当前账号 · 版本 ${state.settings?.settingsRevision ?: "待加载"}") }
        item {
            TextButton(onClick = model::refreshSettings, enabled = !state.busy) { Text("重新加载设置") }
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
            SectionCard("外观") {
                state.settings?.let { settings ->
                    listOf(
                            Appearance.systemAppearance to "跟随系统",
                            Appearance.lightAppearance to "浅色",
                            Appearance.darkAppearance to "深色",
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
            SectionCard("连接与显示") {
                ValueRow("服务器", state.endpoint)
                ValueRow("单位", "公制 · km / kg / W")
                ValueRow("本地时区", ZoneId.systemDefault().id)
            }
        }
    }
}

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
                require(hrFields.all { it != null } && weighting != null) {
                    "请完整填写心率参数并选择 TRIMP 指数。"
                }
                require(hrFields[0]!! < hrFields[1]!! && hrFields[1]!! <= hrFields[2]!!) {
                    "需要：静息心率 < 阈值心率 ≤ 最大心率。"
                }
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
    require(value != null && value.isFinite() && value > 0) { "请输入大于零的数字，或留空。" }
    return value
}

@Composable
private fun SportFields(title: String, value: SportDraft, change: (SportDraft) -> Unit) {
    Text(title, style = MaterialTheme.typography.titleLarge)
    Field("$title FTP (W)", value.watts) { change(value.copy(watts = it)) }
    Field("$title 静息心率 (bpm)", value.resting) { change(value.copy(resting = it)) }
    Field("$title 阈值心率 (bpm)", value.threshold) { change(value.copy(threshold = it)) }
    Field("$title 最大心率 (bpm)", value.maximum) { change(value.copy(maximum = it)) }
    Text("TRIMP 指数需要明确选择，不根据身份推断。")
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
fun Field(label: String, value: String, change: (String) -> Unit) {
    OutlinedTextField(
        value,
        change,
        label = { Text(label) },
        singleLine = true,
        modifier = Modifier.fillMaxWidth().testTag(label),
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
    var error by remember { mutableStateOf<String?>(null) }
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier.testTag("bodySettings"),
    ) {
        item { Text("每次更新新增历史记录。运动内参数优先；缺少时使用运动开始时生效的个人参数。选择过去的生效时间会影响此后运动的分析。") }
        if (!editing)
            item { Button(onClick = { editing = true }, enabled = !state.busy) { Text("更新个人参数") } }
        else {
            item { Field("生效时间 (UTC ISO 8601)", effective) { effective = it } }
            item { Field("体重 (kg)", mass) { mass = it } }
            item { Field("身高 (m)", height) { height = it } }
            item { SportFields("骑行", cycling) { cycling = it } }
            item { SportFields("跑步", running) { running = it } }
            item {
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
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
                                error = failure.message ?: "请检查输入。"
                            } catch (_: java.time.format.DateTimeParseException) {
                                error = "生效时间需要有效的 UTC ISO 8601 日期与时间。"
                            }
                        },
                        enabled = !state.busy,
                        modifier = Modifier.testTag("saveBody"),
                    ) {
                        Text("保存身体参数")
                    }
                    TextButton(onClick = { editing = false }, enabled = !state.busy) { Text("取消") }
                }
            }
        }
        items(settings.settingsBodyProfiles.reversed(), key = { it.bodyProfileId }) { profile ->
            SectionCard(profile.bodyEffectiveFrom) {
                ValueRow(
                    "体重 / 身高",
                    "${number(profile.bodyMassKilograms, "kg")} / ${number(profile.bodyHeightMetres, "m", 2)}",
                )
                listOf("骑行" to profile.bodyCycling, "跑步" to profile.bodyRunning).forEach {
                    (label, sport) ->
                    ValueRow("$label FTP", number(sport.sportThresholdWatts, "W"))
                    sport.sportHeartRate?.let { hr ->
                        ValueRow(
                            "$label 静息 / 阈值 / 最大",
                            "${number(hr.heartRateResting)} / ${number(hr.heartRateThreshold)} / ${number(hr.heartRateMaximum)}",
                        )
                        ValueRow(
                            "TRIMP 指数",
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
    var error by remember { mutableStateOf<String?>(null) }
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item { Text("管理自行车与跑鞋；目录修改不会重写运动内的器材记录。") }
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
                Text("添加器材")
            }
        }
        if (editing)
            item {
                SectionCard(if (selected == null) "新器材" else "编辑器材") {
                    Field("器材名称", name) { name = it }
                    Field("器材质量 (kg)", mass) { mass = it }
                    if (selected == null)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            FilterChip(
                                kind == EquipmentKind.bicycle,
                                { kind = EquipmentKind.bicycle },
                                label = { Text("自行车") },
                            )
                            FilterChip(
                                kind == EquipmentKind.runningShoes,
                                { kind = EquipmentKind.runningShoes },
                                label = { Text("跑鞋") },
                            )
                        }
                    Row {
                        Checkbox(retired, { retired = it })
                        Text("已退役", Modifier.padding(top = 12.dp))
                    }
                    error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                    Row {
                        Button(
                            onClick = {
                                try {
                                    require(name.isNotBlank()) { "请输入器材名称。" }
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
                                    error = failure.message
                                }
                            },
                            enabled = !state.busy,
                            modifier = Modifier.testTag("saveEquipment"),
                        ) {
                            Text("保存器材")
                        }
                        TextButton(onClick = { editing = false }, enabled = !state.busy) {
                            Text("取消")
                        }
                    }
                }
            }
        items(settings.settingsEquipment, key = { it.equipmentId }) { equipment ->
            SectionCard(equipment.equipmentName) {
                ValueRow(
                    "类型",
                    if (equipment.equipmentKind == EquipmentKind.bicycle) "自行车" else "跑鞋",
                )
                ValueRow("质量", number(equipment.equipmentMassKilograms, "kg"))
                ValueRow("状态", if (equipment.equipmentRetired) "已退役" else "使用中")
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
                    Text("编辑")
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
            SectionCard("账号") {
                ValueRow("用户名", state.user?.username.orEmpty())
                ValueRow("服务器", state.endpoint)
                Button(
                    onClick = model::logout,
                    enabled = !state.busy,
                    modifier = Modifier.testTag("logout"),
                ) {
                    Text("退出登录")
                }
                Text("退出登录会撤销服务器会话。连接失败时会保留凭据以便重试。")
                if (state.message != null)
                    TextButton(onClick = model::forgetLocalSession, enabled = !state.busy) {
                        Text("仅清除此设备凭据（不撤销服务器会话）")
                    }
            }
        }
        item {
            SectionCard("修改密码") {
                OutlinedTextField(
                    current,
                    { current = it },
                    label = { Text("当前密码") },
                    visualTransformation = PasswordVisualTransformation(),
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    new,
                    { new = it },
                    label = { Text("新密码") },
                    visualTransformation = PasswordVisualTransformation(),
                    modifier = Modifier.fillMaxWidth(),
                )
                Text("密码修改成功后，所有会话都会撤销，需要重新登录。")
                Button(
                    onClick = {
                        model.changePassword(current, new)
                        current = ""
                        new = ""
                    },
                    enabled = !state.busy && current.isNotEmpty() && new.isNotEmpty(),
                ) {
                    Text("修改密码并退出")
                }
            }
        }
        item {
            Row {
                TextButton(onClick = model::loadSessions, enabled = !state.busy) { Text("刷新会话") }
                TextButton(onClick = { confirmAll = true }, enabled = !state.busy) {
                    Text("撤销所有会话")
                }
            }
        }
        items(state.sessions, key = { it.id }) { session ->
            SectionCard(session.deviceName ?: "设备会话") {
                Text(if (session.current) "当前会话" else "其他会话")
                ValueRow("最近活动", session.lastSeenAt)
                ValueRow("绝对到期", session.absoluteExpiresAt)
                TextButton(onClick = { model.revokeSession(session) }, enabled = !state.busy) {
                    Text("撤销此会话")
                }
            }
        }
    }
    if (confirmAll)
        AlertDialog(
            onDismissRequest = { confirmAll = false },
            title = { Text("撤销所有登录会话？") },
            text = { Text("包括当前设备；所有设备都需要重新登录。") },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmAll = false
                        model.revokeAll()
                    }
                ) {
                    Text("撤销")
                }
            },
            dismissButton = { TextButton(onClick = { confirmAll = false }) { Text("取消") } },
        )
}
