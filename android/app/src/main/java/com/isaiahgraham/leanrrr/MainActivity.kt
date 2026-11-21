package com.isaiahgraham.leanrrr

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.isaiahgraham.leanrrr.ui.AppShell
import com.isaiahgraham.leanrrr.ui.theme.LeanrTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        handle(intent)
        setContent {
            LeanrTheme { AppShell() }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    /** leanr://today, leanr://progress and leanr://scan, from widgets, shortcuts and notifications. */
    private fun handle(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme != "leanr") return
        AppServices.nav.openLink(uri.host ?: return)
    }
}
