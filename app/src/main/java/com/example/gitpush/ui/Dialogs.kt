package com.example.gitpush.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.example.gitpush.ui.components.GpTextField
import com.example.gitpush.ui.components.PinPad
import com.example.gitpush.service.AppLockService
import com.example.gitpush.Graph
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Snackbar (ScaffoldMessenger karşılığı). */
object Snacks {
    val host = SnackbarHostState()
    var scope: CoroutineScope? = null

    fun show(message: String, actionLabel: String? = null, onAction: (() -> Unit)? = null) {
        scope?.launch {
            host.currentSnackbarData?.dismiss()
            val r = host.showSnackbar(message, actionLabel, duration = SnackbarDuration.Short)
            if (r == SnackbarResult.ActionPerformed) onAction?.invoke()
        }
    }
}

sealed interface DialogSpec

class ConfirmSpec(
    val title: String, val content: String, val confirmLabel: String,
    val cancelLabel: String, val destructive: Boolean, val result: CompletableDeferred<Boolean>,
) : DialogSpec

class TypedConfirmSpec(
    val title: String, val content: String, val expected: String, val result: CompletableDeferred<Boolean>,
) : DialogSpec

class PromptSpec(
    val title: String, val message: String?, val label: String, val initial: String,
    val confirmLabel: String, val mono: Boolean, val result: CompletableDeferred<String?>,
) : DialogSpec

class InfoSpec(val title: String, val text: String, val result: CompletableDeferred<Unit>) : DialogSpec

class PickSpec(
    val title: String, val options: List<Pair<Any, String>>, val current: Any?,
    val result: CompletableDeferred<Any?>,
) : DialogSpec

class PinSpec(val title: String, val create: Boolean, val result: CompletableDeferred<Boolean>) : DialogSpec

/** Zaman uyumsuz, "await" edilebilir diyaloglar: `val ok = Dialogs.confirm(...)`. */
object Dialogs {
    var current by mutableStateOf<DialogSpec?>(null)
    var busy by mutableStateOf<String?>(null)
    private val mutex = Mutex()

    private suspend fun <T> show(spec: DialogSpec, result: CompletableDeferred<T>): T =
        mutex.withLock {
            current = spec
            try { result.await() } finally { current = null }
        }

    suspend fun confirm(
        title: String, content: String, confirmLabel: String = "Onayla",
        cancelLabel: String = "Vazgeç", destructive: Boolean = false,
    ): Boolean {
        val d = CompletableDeferred<Boolean>()
        return show(ConfirmSpec(title, content, confirmLabel, cancelLabel, destructive, d), d)
    }

    suspend fun typedConfirm(title: String, content: String, expected: String): Boolean {
        val d = CompletableDeferred<Boolean>()
        return show(TypedConfirmSpec(title, content, expected, d), d)
    }

    suspend fun prompt(
        title: String, label: String, initial: String = "", message: String? = null,
        confirmLabel: String = "Tamam", mono: Boolean = false,
    ): String? {
        val d = CompletableDeferred<String?>()
        return show(PromptSpec(title, message, label, initial, confirmLabel, mono, d), d)
    }

    suspend fun info(title: String, text: String) {
        val d = CompletableDeferred<Unit>()
        show(InfoSpec(title, text, d), d)
    }

    @Suppress("UNCHECKED_CAST")
    suspend fun <T : Any> pick(title: String, options: List<Pair<T, String>>, current: T?): T? {
        val d = CompletableDeferred<Any?>()
        return show(PickSpec(title, options as List<Pair<Any, String>>, current, d), d) as T?
    }

    suspend fun pin(title: String, create: Boolean): Boolean {
        val d = CompletableDeferred<Boolean>()
        return show(PinSpec(title, create, d), d)
    }

    /** İşlem sürerken kapatılamayan "bekleyin" diyaloğu. */
    suspend fun <T> withBusy(label: String, block: suspend () -> T): T {
        busy = label
        try { return block() } finally { busy = null }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DialogHost() {
    val spec = Dialogs.current
    val errorColor = MaterialTheme.colorScheme.error

    when (spec) {
        is ConfirmSpec -> AlertDialog(
            onDismissRequest = { spec.result.complete(false) },
            title = { Text(spec.title) },
            text = { Text(spec.content) },
            dismissButton = { TextButton(onClick = { spec.result.complete(false) }) { Text(spec.cancelLabel) } },
            confirmButton = {
                Button(
                    onClick = { spec.result.complete(true) },
                    colors = if (spec.destructive) ButtonDefaults.buttonColors(containerColor = errorColor) else ButtonDefaults.buttonColors(),
                ) { Text(spec.confirmLabel) }
            },
        )

        is TypedConfirmSpec -> {
            var typed by remember(spec) { mutableStateOf("") }
            val matches = typed.trim().lowercase() == spec.expected.lowercase()
            AlertDialog(
                onDismissRequest = { spec.result.complete(false) },
                title = { Text(spec.title) },
                text = {
                    Column {
                        Text(spec.content)
                        Spacer(Modifier.height(14.dp))
                        Text("Onaylamak için \"${spec.expected}\" yazın:", style = MaterialTheme.typography.bodySmall)
                        Spacer(Modifier.height(8.dp))
                        GpTextField(value = typed, onValueChange = { typed = it }, modifier = Modifier.fillMaxWidth())
                    }
                },
                dismissButton = { TextButton(onClick = { spec.result.complete(false) }) { Text("Vazgeç") } },
                confirmButton = {
                    Button(
                        enabled = matches,
                        onClick = { spec.result.complete(true) },
                        colors = ButtonDefaults.buttonColors(containerColor = errorColor),
                    ) { Text("Sil") }
                },
            )
        }

        is PromptSpec -> {
            var text by remember(spec) { mutableStateOf(spec.initial) }
            AlertDialog(
                onDismissRequest = { spec.result.complete(null) },
                title = { Text(spec.title) },
                text = {
                    Column {
                        if (spec.message != null) {
                            Text(spec.message, style = MaterialTheme.typography.bodySmall)
                            Spacer(Modifier.height(12.dp))
                        }
                        GpTextField(
                            value = text, onValueChange = { text = it }, label = spec.label,
                            modifier = Modifier.fillMaxWidth(), mono = spec.mono,
                        )
                    }
                },
                dismissButton = { TextButton(onClick = { spec.result.complete(null) }) { Text("Vazgeç") } },
                confirmButton = { Button(onClick = { spec.result.complete(text) }) { Text(spec.confirmLabel) } },
            )
        }

        is InfoSpec -> AlertDialog(
            onDismissRequest = { spec.result.complete(Unit) },
            title = { Text(spec.title) },
            text = { Column(Modifier.verticalScroll(rememberScrollState())) { Text(spec.text) } },
            confirmButton = { TextButton(onClick = { spec.result.complete(Unit) }) { Text("Tamam") } },
        )

        is PickSpec -> ModalBottomSheet(
            onDismissRequest = { spec.result.complete(null) },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        ) {
            Column(Modifier.padding(bottom = 16.dp).verticalScroll(rememberScrollState())) {
                Text(
                    spec.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
                )
                for ((key, label) in spec.options) {
                    ListItem(
                        headlineContent = { Text(label) },
                        trailingContent = {
                            if (key == spec.current) Icon(Icons.Filled.Check, null, tint = MaterialTheme.colorScheme.primary)
                        },
                        modifier = Modifier.clickable { spec.result.complete(key) },
                    )
                }
            }
        }

        is PinSpec -> PinDialog(spec)
        null -> Unit
    }

    val busy = Dialogs.busy
    if (busy != null) {
        Dialog(onDismissRequest = {}, properties = DialogProperties(dismissOnBackPress = false, dismissOnClickOutside = false)) {
            androidx.compose.material3.Surface(shape = RoundedCornerShape(24.dp), tonalElevation = 6.dp) {
                Row(Modifier.padding(24.dp), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(28.dp), strokeWidth = 3.dp)
                    Spacer(Modifier.width(18.dp))
                    Text(busy)
                }
            }
        }
    }
}

/** PIN oluşturma / doğrulama diyaloğu. */
@Composable
private fun PinDialog(spec: PinSpec) {
    var reset by remember(spec) { mutableStateOf(0) }
    var error by remember(spec) { mutableStateOf<String?>(null) }
    var first by remember(spec) { mutableStateOf<String?>(null) }
    var busy by remember(spec) { mutableStateOf(false) }
    val scope = androidx.compose.runtime.rememberCoroutineScope()

    fun onPin(pin: String) {
        scope.launch {
            if (!spec.create) {
                busy = true
                val r = Graph.lock.service.verify(pin)
                if (r.ok) { spec.result.complete(true); return@launch }
                busy = false
                reset++
                error = if (r.isLockedOut) "Çok fazla deneme. ${r.lockedForMs / 1000} sn bekleyin." else "Hatalı PIN."
                return@launch
            }
            if (first == null) {
                if (AppLockService.isWeakPin(pin)) {
                    reset++
                    error = "Çok kolay bir PIN (tekrar eden / ardışık). Başka bir tane seçin."
                    return@launch
                }
                first = pin; reset++; error = null
                return@launch
            }
            if (pin != first) {
                first = null; reset++
                error = "PIN'ler eşleşmedi. Baştan başlayın."
                return@launch
            }
            busy = true
            Graph.lock.service.setPin(pin)
            spec.result.complete(true)
        }
    }

    val subtitle = if (spec.create) {
        if (first == null) "${AppLockService.PIN_LENGTH} haneli bir PIN seçin" else "PIN'i tekrar girin"
    } else "PIN'inizi girin"

    AlertDialog(
        onDismissRequest = { spec.result.complete(false) },
        title = { Text(spec.title) },
        text = {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(subtitle, style = MaterialTheme.typography.bodyMedium)
                Spacer(Modifier.height(12.dp))
                PinPad(onCompleted = { onPin(it) }, errorText = error, enabled = !busy, resetToken = reset)
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = { spec.result.complete(false) }) { Text("Vazgeç") } },
    )
}
