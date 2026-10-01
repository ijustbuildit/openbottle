package dev.hydrocap.app.ui

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TimePickerDialog
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import dev.hydrocap.app.R
import dev.hydrocap.app.domain.ReminderRules

/**
 * Material 3 time picker dialog over a seconds-of-day value (1..86400,
 * midnight = 86400 as the cap expects). 24 h layout to match the cap's
 * seconds-of-day model.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SecOfDayPickerDialog(
    title: String,
    initialSecOfDay: Int,
    onDismiss: () -> Unit,
    onConfirm: (secOfDay: Int) -> Unit,
) {
    val state = rememberTimePickerState(
        initialHour = ReminderRules.hourOf(initialSecOfDay),
        initialMinute = ReminderRules.minuteOf(initialSecOfDay),
        is24Hour = true,
    )
    TimePickerDialog(
        onDismissRequest = onDismiss,
        title = { Text(title, style = MaterialTheme.typography.labelLarge) },
        confirmButton = {
            TextButton(onClick = { onConfirm(ReminderRules.secOfDay(state.hour, state.minute)) }) { Text(stringResource(R.string.ok)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    ) {
        TimePicker(state = state)
    }
}
