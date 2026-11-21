package com.isaiahgraham.leanrrr.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.delay

/**
 * A tab or pushed screen: a big Bebas title (iOS large navigation title), optional back arrow, the Settings gear at the
 * top right of every tab, extra actions, and a scrolling list of grouped sections on the order-pad paper.
 */
@Composable
fun LeanrScreen(
    title: String,
    modifier: Modifier = Modifier,
    onBack: (() -> Unit)? = null,
    showSettings: Boolean = onBack == null,
    actions: @Composable RowScope.() -> Unit = {},
    bottomBar: @Composable () -> Unit = {},
    content: LazyListScope.() -> Unit,
) {
    Column(modifier.fillMaxSize().statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(start = if (onBack != null) 4.dp else 20.dp, end = 8.dp, top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            if (onBack != null) IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = Leanr.colours.accent) }
            Text(title, style = if (onBack != null) LeanrType.title else LeanrType.largeTitle, color = Leanr.colours.text,
                maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            actions()
            if (showSettings) IconButton(onClick = { AppServices.nav.settingsOpen = true }) {
                Icon(Icons.Filled.Settings, "Settings", tint = Leanr.colours.accent)
            }
        }
        LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(0.dp), content = content)
        bottomBar()
    }
}

/** A grouped section like an iOS inset-grouped List section: optional header, rows on a rounded card, optional footer. */
@Composable
fun LeanrSection(header: String? = null, footer: String? = null, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val c = Leanr.colours
    Column(modifier.fillMaxWidth().padding(bottom = 20.dp)) {
        if (header != null) Text(header.uppercase(), style = LeanrType.footnote, color = c.secondaryText, modifier = Modifier.padding(start = 16.dp, bottom = 6.dp))
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(c.card), content = content)
        if (footer != null) Text(footer, style = LeanrType.footnote, color = c.secondaryText, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp))
    }
}

/** One row in a section: title, optional subtitle, trailing content, tappable. Draws a divider above unless it's first. */
@Composable
fun LeanrRow(
    title: String,
    subtitle: String? = null,
    modifier: Modifier = Modifier,
    divider: Boolean = true,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable RowScope.() -> Unit)? = null,
    titleColour: androidx.compose.ui.graphics.Color? = null,
    onClick: (() -> Unit)? = null,
) {
    val c = Leanr.colours
    Column {
        Row(
            modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).padding(horizontal = 16.dp, vertical = 11.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (leading != null) { leading(); Spacer(Modifier.width(12.dp)) }
            Column(Modifier.weight(1f)) {
                Text(title, style = LeanrType.body, color = titleColour ?: c.text)
                if (subtitle != null) Text(subtitle, style = LeanrType.subheadline, color = c.secondaryText)
            }
            if (trailing != null) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), content = trailing)
        }
        if (divider) HorizontalDivider(Modifier.padding(start = if (leading != null) 56.dp else 16.dp), color = c.separator, thickness = 0.5.dp)
    }
}

/**
 * The Undo banner and passing notices, at the top as on iOS (ContentView.swift): with something to undo, the notice (or the
 * change's own label) and Undo for 5 seconds; otherwise a notice for 2 seconds, gone sooner if tapped. Errors are an alert.
 */
@Composable
fun StoreToasts(modifier: Modifier = Modifier) {
    val store = AppServices.store
    val c = Leanr.colours
    val undo = store.undo
    val notice = store.notice
    LaunchedEffect(undo?.id) { if (undo != null) { delay(5000); store.dismissUndo(undo.id); store.notice = null } }
    LaunchedEffect(notice, undo == null) { if (notice != null && undo == null) { delay(2000); if (store.notice == notice) store.notice = null } }
    val text = if (undo != null) notice ?: undo.label else notice
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        AnimatedVisibility(text != null, enter = slideInVertically { -it } + fadeIn(), exit = slideOutVertically { -it } + fadeOut()) {
            var shown by remember { mutableStateOf("") }
            if (text != null) shown = text
            Surface(shape = RoundedCornerShape(50), color = c.card, shadowElevation = 8.dp,
                modifier = Modifier.padding(horizontal = 16.dp).clickable(enabled = undo == null) { store.notice = null }) {
                Row(Modifier.padding(start = 20.dp, end = if (undo != null) 6.dp else 20.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(shown, style = LeanrType.subheadline.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Medium), color = c.text, maxLines = 2,
                        modifier = Modifier.padding(vertical = 8.dp).weight(1f, fill = false))
                    if (undo != null) TextButton(onClick = { store.undoLast() }) { Text("Undo", style = LeanrType.subheadline.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Bold), color = c.accent) }
                }
            }
        }
    }
    store.errorMessage?.let { message ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { store.errorMessage = null },
            confirmButton = { TextButton(onClick = { store.errorMessage = null }) { Text("OK") } },
            title = { Text("Couldn’t complete that") },
            text = { Text(message) },
        )
    }
}

/** Placeholder for a screen whose port hasn't landed yet. */
@Composable
fun ComingSoon(title: String) {
    LeanrScreen(title) {
        item { LeanrSection { LeanrRow("Coming soon", "This screen is being ported from the iOS app.", divider = false) } }
    }
}
