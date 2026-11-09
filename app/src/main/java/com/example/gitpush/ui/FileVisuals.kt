package com.example.gitpush.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Android
import androidx.compose.material.icons.outlined.Build
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.Css
import androidx.compose.material.icons.outlined.DataObject
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Html
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.InsertDriveFile
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.Javascript
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.PictureAsPdf
import androidx.compose.material.icons.outlined.Terminal
import androidx.compose.material.icons.outlined.VpnKey
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector

class FileVisual(val icon: ImageVector, val color: Color)

private val defaultFile = FileVisual(Icons.Outlined.InsertDriveFile, Color(0xFF8B93A7))

private val byExt: Map<String, FileVisual> = mapOf(
    "dart" to FileVisual(Icons.Outlined.Code, Color(0xFF29B6F6)),
    "kt" to FileVisual(Icons.Outlined.Code, Color(0xFFB455F0)),
    "java" to FileVisual(Icons.Outlined.Code, Color(0xFFE8A200)),
    "swift" to FileVisual(Icons.Outlined.Code, Color(0xFFFF7043)),
    "js" to FileVisual(Icons.Outlined.Javascript, Color(0xFFE8C200)),
    "jsx" to FileVisual(Icons.Outlined.Javascript, Color(0xFF29B6F6)),
    "ts" to FileVisual(Icons.Outlined.Javascript, Color(0xFF3B82F6)),
    "tsx" to FileVisual(Icons.Outlined.Javascript, Color(0xFF3B82F6)),
    "py" to FileVisual(Icons.Outlined.Code, Color(0xFF3B82F6)),
    "rb" to FileVisual(Icons.Outlined.Code, Color(0xFFE5484D)),
    "go" to FileVisual(Icons.Outlined.Code, Color(0xFF00B8A9)),
    "rs" to FileVisual(Icons.Outlined.Code, Color(0xFFFF7043)),
    "c" to FileVisual(Icons.Outlined.Code, Color(0xFF8B93A7)),
    "cpp" to FileVisual(Icons.Outlined.Code, Color(0xFF3B82F6)),
    "h" to FileVisual(Icons.Outlined.Code, Color(0xFF8B93A7)),
    "json" to FileVisual(Icons.Outlined.DataObject, Color(0xFFE8A200)),
    "yaml" to FileVisual(Icons.Outlined.DataObject, Color(0xFFE5484D)),
    "yml" to FileVisual(Icons.Outlined.DataObject, Color(0xFFE5484D)),
    "toml" to FileVisual(Icons.Outlined.DataObject, Color(0xFF8B93A7)),
    "xml" to FileVisual(Icons.Outlined.DataObject, Color(0xFFFF7043)),
    "md" to FileVisual(Icons.Outlined.Description, Color(0xFF5B6CFF)),
    "txt" to FileVisual(Icons.Outlined.Description, Color(0xFF8B93A7)),
    "html" to FileVisual(Icons.Outlined.Html, Color(0xFFFF7043)),
    "css" to FileVisual(Icons.Outlined.Css, Color(0xFF3B82F6)),
    "sh" to FileVisual(Icons.Outlined.Terminal, Color(0xFF2EA043)),
    "bat" to FileVisual(Icons.Outlined.Terminal, Color(0xFF2EA043)),
    "gradle" to FileVisual(Icons.Outlined.Build, Color(0xFF00B8A9)),
    "kts" to FileVisual(Icons.Outlined.Build, Color(0xFF00B8A9)),
    "png" to FileVisual(Icons.Outlined.Image, Color(0xFFB455F0)),
    "jpg" to FileVisual(Icons.Outlined.Image, Color(0xFFB455F0)),
    "jpeg" to FileVisual(Icons.Outlined.Image, Color(0xFFB455F0)),
    "gif" to FileVisual(Icons.Outlined.Image, Color(0xFFB455F0)),
    "webp" to FileVisual(Icons.Outlined.Image, Color(0xFFB455F0)),
    "svg" to FileVisual(Icons.Outlined.Image, Color(0xFFFF7043)),
    "zip" to FileVisual(Icons.Outlined.Inventory2, Color(0xFFE8A200)),
    "apk" to FileVisual(Icons.Outlined.Android, Color(0xFF2EA043)),
    "pdf" to FileVisual(Icons.Outlined.PictureAsPdf, Color(0xFFE5484D)),
    "pem" to FileVisual(Icons.Outlined.VpnKey, Color(0xFFE5484D)),
    "jks" to FileVisual(Icons.Outlined.VpnKey, Color(0xFFE5484D)),
    "lock" to FileVisual(Icons.Outlined.Lock, Color(0xFF8B93A7)),
)

fun fileVisualFor(extension: String): FileVisual = byExt[extension.lowercase()] ?: defaultFile
