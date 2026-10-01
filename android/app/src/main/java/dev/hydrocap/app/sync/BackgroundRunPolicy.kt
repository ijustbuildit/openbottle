package dev.hydrocap.app.sync

/**
 * Pure decision logic for the periodic background sync ([CapSyncWorker]):
 * whether a run should happen at all, how a run's result maps to the
 * WorkManager verdict, and the "cap not seen" streak. Free of Android types
 * so it is unit-testable; the worker stays thin.
 */
object BackgroundRunPolicy {

    /** After this many consecutive runs without the cap the worker only logs — it never notifies. */
    const val QUIET_AFTER_MISSES = 3

    enum class SkipReason { NOT_PAIRED, DISABLED, PERMISSIONS_MISSING }

    fun skipReason(hasPairedDevice: Boolean, backgroundSyncEnabled: Boolean, hasBlePermissions: Boolean): SkipReason? = when {
        !hasPairedDevice -> SkipReason.NOT_PAIRED
        !backgroundSyncEnabled -> SkipReason.DISABLED
        !hasBlePermissions -> SkipReason.PERMISSIONS_MISSING
        else -> null
    }

    sealed class Outcome {
        data class Synced(val newTofEntries: Int, val drinkEvents: Int, val batteryPercent: Int?) : Outcome()
        data object CapNotFound : Outcome()
        data object Busy : Outcome()
        data class Failed(val reason: String) : Outcome()

        /** Short persisted label (Debug screen "last background run"). */
        fun label(): String = when (this) {
            is Synced -> "synced: $newTofEntries new readings, $drinkEvents drinks, battery ${batteryPercent?.let { "$it %" } ?: "n/a"}"
            CapNotFound -> "cap not found"
            Busy -> "another cap job was running, retried"
            is Failed -> "failed: $reason"
        }
    }

    fun classify(error: Throwable): Outcome = when (error) {
        is CapBusyException -> Outcome.Busy
        is CapNotFoundException -> Outcome.CapNotFound
        else -> Outcome.Failed(error.message ?: error.javaClass.simpleName)
    }

    enum class Verdict { SUCCESS, RETRY }

    /**
     * [consecutiveMisses] is the new streak to persist; [quiet] is true once
     * the streak has reached [QUIET_AFTER_MISSES] (log only, no notification).
     */
    data class Evaluation(val verdict: Verdict, val consecutiveMisses: Int, val quiet: Boolean)

    fun evaluate(outcome: Outcome, previousMisses: Int): Evaluation = when (outcome) {
        is Outcome.Synced -> Evaluation(Verdict.SUCCESS, 0, quiet = false)
        // The cap was reachable but something else went wrong: periodic work must not accumulate backoff.
        is Outcome.Failed -> Evaluation(Verdict.SUCCESS, 0, quiet = false)
        // Only a concurrent cap job justifies a retry (the engine refuses to run two jobs at once).
        Outcome.Busy -> Evaluation(Verdict.RETRY, previousMisses, quiet = false)
        Outcome.CapNotFound -> {
            val misses = previousMisses + 1
            Evaluation(Verdict.SUCCESS, misses, quiet = misses >= QUIET_AFTER_MISSES)
        }
    }
}
