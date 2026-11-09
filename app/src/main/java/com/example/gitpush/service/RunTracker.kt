package com.example.gitpush.service

import com.example.gitpush.model.ActionRun

class RunEvaluation(val matching: List<ActionRun>, val allCompleted: Boolean) {
    val found get() = matching.isNotEmpty()
}

/** Bir commit SHA'sına ait Actions çalışmalarını (yeniden eskiye) ve tamamlanma durumunu döndürür. */
fun evaluateRuns(runs: List<ActionRun>, commitSha: String): RunEvaluation {
    val matching = runs.filter { it.headSha == commitSha }.sortedByDescending { it.createdAt }
    val done = matching.isNotEmpty() && matching.all { it.isCompleted }
    return RunEvaluation(matching, done)
}
