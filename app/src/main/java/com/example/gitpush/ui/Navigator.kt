package com.example.gitpush.ui

import androidx.compose.runtime.mutableStateListOf
import com.example.gitpush.model.RepoEntry
import com.example.gitpush.state.PreviewSource

/** Ana kabuğun üstüne açılan ekranlar. */
sealed interface Route {
    data object RepoPicker : Route
    data object Zip : Route
    data object Multi : Route
    data class Preview(val source: PreviewSource, val commitMessage: String) : Route
    data class Result(
        val result: com.example.gitpush.model.PushResult,
        val commitUrl: String,
        val owner: String,
        val repo: String,
        val branch: String,
        val isPrivate: Boolean,
    ) : Route
    data class FileDetail(val entry: RepoEntry) : Route
    data class FileEditor(
        val path: String,
        val initialText: String = "",
        val isNew: Boolean = false,
        val mode: String? = null,
    ) : Route
    data class Commits(val path: String?) : Route
}

class NavEntry(val id: Long, val route: Route, val onResult: ((Boolean) -> Unit)?)

/** Basit geri yığını. pop(result) ile çağırana (ör. düzenleyici → detay) sonuç iletilir. */
class Navigator {
    val stack = mutableStateListOf<NavEntry>()
    private var counter = 0L

    fun push(route: Route, onResult: ((Boolean) -> Unit)? = null) {
        stack.add(NavEntry(++counter, route, onResult))
    }

    fun pop(result: Boolean = false) {
        if (stack.isEmpty()) return
        val e = stack.removeAt(stack.size - 1)
        e.onResult?.invoke(result)
    }

    /** Sonuç ekranından ana ekrana dönüş. */
    fun popToRoot() {
        stack.clear()
    }
}
