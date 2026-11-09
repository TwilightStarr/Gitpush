package com.example.gitpush

import android.app.Application
import android.content.Context
import com.example.gitpush.service.AppLockService
import com.example.gitpush.service.GitHubService
import com.example.gitpush.service.StorageService
import com.example.gitpush.state.AppLockProvider
import com.example.gitpush.state.AuthProvider
import com.example.gitpush.state.RepoProvider
import com.example.gitpush.state.SettingsProvider
import com.example.gitpush.state.ThemeProvider
import com.example.gitpush.state.UploadProvider
import com.example.gitpush.ui.Navigator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/** Uygulama genelinde paylaşılan tekil nesneler (sağlayıcılar). */
object Graph {
    lateinit var appContext: Context
    lateinit var scope: CoroutineScope
    lateinit var storage: StorageService
    lateinit var github: GitHubService
    lateinit var settings: SettingsProvider
    lateinit var theme: ThemeProvider
    lateinit var auth: AuthProvider
    lateinit var lock: AppLockProvider
    lateinit var repo: RepoProvider
    lateinit var upload: UploadProvider
    val nav = Navigator()

    private var initialized = false

    fun init(context: Context) {
        if (initialized) return
        initialized = true
        appContext = context.applicationContext
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        storage = StorageService(appContext)
        github = GitHubService()
        settings = SettingsProvider(storage, scope)
        theme = ThemeProvider(storage, scope)
        auth = AuthProvider(storage, github)
        lock = AppLockProvider(AppLockService(storage.secure), storage, scope)
        repo = RepoProvider(github, storage)
        upload = UploadProvider(github, storage)
    }
}

class GitpushApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Graph.init(this)
    }
}
