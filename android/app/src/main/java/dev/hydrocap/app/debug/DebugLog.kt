package dev.hydrocap.app.debug

import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** One line of the session debug log. */
data class DebugEntry(val timestampMs: Long, val tag: String, val message: String) {
    fun format(): String = "${TIME_FORMAT.get()!!.format(Date(timestampMs))} [$tag] $message"

    private companion object {
        val TIME_FORMAT = object : ThreadLocal<SimpleDateFormat>() {
            override fun initialValue() = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)
        }
    }
}

/**
 * Process-wide debug log: in-memory ring (for the Debug screen), Logcat tag
 * "HydroCap", and an append-only `files/debug-log.txt` rotated at 2 MB so the
 * first hardware session can be driven and inspected purely over ADB.
 */
class DebugLog(private val filesDir: File?, private val maxMemoryEntries: Int = 4_000) {

    private val lock = Any()
    private val _entries = MutableStateFlow<List<DebugEntry>>(emptyList())
    val entries: StateFlow<List<DebugEntry>> = _entries

    fun log(tag: String, message: String) {
        val entry = DebugEntry(System.currentTimeMillis(), tag, message)
        Log.i(LOGCAT_TAG, "[$tag] $message")
        synchronized(lock) {
            _entries.update { current ->
                if (current.size >= maxMemoryEntries) current.drop(current.size - maxMemoryEntries + 1) + entry else current + entry
            }
            appendToFile(entry)
        }
    }

    fun error(tag: String, message: String, throwable: Throwable? = null) {
        val full = if (throwable != null) "$message: ${throwable.javaClass.simpleName}: ${throwable.message}" else message
        Log.e(LOGCAT_TAG, "[$tag] $full", throwable)
        log(tag, "ERROR $full")
    }

    /** Clears the in-memory view only; the file keeps its history. */
    fun clearMemory() {
        _entries.value = emptyList()
    }

    fun dumpText(): String = _entries.value.joinToString("\n") { it.format() }

    private fun appendToFile(entry: DebugEntry) {
        val dir = filesDir ?: return
        try {
            val file = File(dir, FILE_NAME)
            if (file.exists() && file.length() > MAX_FILE_BYTES) {
                val rotated = File(dir, ROTATED_FILE_NAME)
                if (rotated.exists()) rotated.delete()
                file.renameTo(rotated)
            }
            FileOutputStream(file, true).use { out ->
                out.write((entry.format() + "\n").toByteArray(Charsets.UTF_8))
            }
        } catch (e: Exception) {
            Log.w(LOGCAT_TAG, "debug log file write failed: ${e.message}")
        }
    }

    companion object {
        const val LOGCAT_TAG = "HydroCap"
        const val FILE_NAME = "debug-log.txt"
        const val ROTATED_FILE_NAME = "debug-log.1.txt"
        const val MAX_FILE_BYTES = 2L * 1024 * 1024
    }
}
