package com.cold04.uwhlife

import android.content.Intent
import android.content.ClipData
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebStorage
import androidx.core.content.FileProvider
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi

class MainActivity : FlutterActivity() {
    private val androidInjectorChannelName = "uwhlife/android_webview_injector"
    private val appLauncherChannelName = "uwhlife/android_app_launcher"
    private val browserDataChannelName = "uwhlife/browser_data"
    private val deepLinkMethodChannelName = "uwhlife/deep_links"
    private val deepLinkEventChannelName = "uwhlife/deep_links/events"
    private val apkInstallerChannelName = "uwhlife/apk_installer"

    private var deepLinkSink: EventChannel.EventSink? = null
    private var initialDeepLink: String? = null
    private var initialDeepLinkConsumed = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 冷启动时记录唤起 intent 的 URI（onNewIntent 已 setIntent，所以这里可直接读）
        initialDeepLink = extractDeepLink(intent)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deepLinkEventChannelName,
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                deepLinkSink = events
            }

            override fun onCancel(arguments: Any?) {
                deepLinkSink = null
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deepLinkMethodChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialLink" -> {
                    if (initialDeepLinkConsumed) {
                        result.success(null)
                    } else {
                        initialDeepLinkConsumed = true
                        result.success(initialDeepLink)
                    }
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            androidInjectorChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "injectDocumentStartScript" -> handleDocumentStartScript(
                    flutterEngine = flutterEngine,
                    arguments = call.arguments as? Map<*, *>,
                    result = result,
                )

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            appLauncherChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // 入参: { "packages": ["com.wisedu.cpdaily.wju", "com.wisedu.cpdaily"] }
                // 顺序探测，命中第一个已安装的就启动主入口；都没装返回 false。
                "launchFirstAvailable" -> {
                    val args = call.arguments as? Map<*, *>
                    @Suppress("UNCHECKED_CAST")
                    val packages = (args?.get("packages") as? List<*>)
                        ?.filterIsInstance<String>()
                        ?: emptyList()
                    val launched = launchFirstAvailable(packages)
                    result.success(launched)
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            browserDataChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "clearAppBrowserData" -> clearAppBrowserData(result)
                "clearCookiesForUrl" -> clearCookiesForUrl(call.arguments as? Map<*, *>, result)
                "setCookiesForUrl" -> setCookiesForUrl(call.arguments as? Map<*, *>, result)
                "flushCookies" -> flushCookies(result)
                "getCookies" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrBlank()) {
                        result.error("bad_args", "Missing url", null)
                    } else {
                        val cookies = CookieManager.getInstance().getCookie(url)
                        result.success(cookies ?: "")
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            apkInstallerChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canRequestPackageInstalls" -> {
                    val allowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        packageManager.canRequestPackageInstalls()
                    } else {
                        true
                    }
                    result.success(allowed)
                }
                "openInstallPermissionSettings" -> openInstallPermissionSettings(result)
                "supportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "installApk" -> installApk(call.arguments as? Map<*, *>, result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // singleTop：应用在前台时再次被 uwhlife://... 唤起会走这里
        setIntent(intent)
        val link = extractDeepLink(intent) ?: return
        deepLinkSink?.success(link)
    }

    private fun extractDeepLink(intent: Intent?): String? {
        if (intent == null) return null
        if (intent.action != Intent.ACTION_VIEW) return null
        val data: Uri = intent.data ?: return null
        return data.toString()
    }

    private fun launchFirstAvailable(packageNames: List<String>): Boolean {
        val pm = packageManager
        for (name in packageNames) {
            val intent = pm.getLaunchIntentForPackage(name) ?: continue
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                startActivity(intent)
                return true
            } catch (_: Throwable) {
                // 包存在但启动失败（极少见，例如 Activity 被禁用）— 继续试下一个
            }
        }
        return false
    }

    private fun handleDocumentStartScript(
        flutterEngine: FlutterEngine,
        arguments: Map<*, *>?,
        result: MethodChannel.Result,
    ) {
        val identifier = (arguments?.get("webViewIdentifier") as? Number)?.toLong()
        val script = arguments?.get("script") as? String
        if (identifier == null || script.isNullOrBlank()) {
            result.error("bad_args", "Missing webViewIdentifier or script", null)
            return
        }

        val webView = WebViewFlutterAndroidExternalApi.getWebView(flutterEngine, identifier)
        if (webView == null) {
            result.error("no_webview", "Android WebView not found for identifier", null)
            return
        }

        if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            result.error(
                "unsupported",
                "DOCUMENT_START_SCRIPT is not supported by the current WebView package",
                null,
            )
            return
        }

        try {
            WebViewCompat.addDocumentStartJavaScript(
                webView,
                script,
                setOf("*"),
            )
            result.success(null)
        } catch (error: Throwable) {
            result.error("inject_failed", error.message, null)
        }
    }

    private fun clearAppBrowserData(result: MethodChannel.Result) {
        try {
            CookieManager.getInstance().removeAllCookies { _ ->
                CookieManager.getInstance().flush()
                WebStorage.getInstance().deleteAllData()
                WebView(applicationContext).apply {
                    clearCache(true)
                    clearSslPreferences()
                }
                result.success(null)
            }
        } catch (error: Throwable) {
            result.error("clear_failed", error.message, null)
        }
    }

    private fun clearCookiesForUrl(arguments: Map<*, *>?, result: MethodChannel.Result) {
        val url = arguments?.get("url") as? String
        val names = (arguments?.get("names") as? List<*>)
            ?.filterIsInstance<String>()
            ?: emptyList()
        if (url.isNullOrBlank() || names.isEmpty()) {
            result.error("bad_args", "Missing url or names", null)
            return
        }

        try {
            val manager = CookieManager.getInstance()
            val paths = listOf("/", "/message_pocket_web", "/message_pocket_web/")
            for (name in names) {
                for (path in paths) {
                    manager.setCookie(
                        url,
                        "$name=; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Max-Age=0; Path=$path",
                    )
                }
            }
            manager.flush()
            result.success(null)
        } catch (error: Throwable) {
            result.error("clear_cookies_failed", error.message, null)
        }
    }

    private fun setCookiesForUrl(arguments: Map<*, *>?, result: MethodChannel.Result) {
        val url = arguments?.get("url") as? String
        val cookies = (arguments?.get("cookies") as? List<*>)
            ?.filterIsInstance<String>()
            ?: emptyList()
        if (url.isNullOrBlank() || cookies.isEmpty()) {
            result.error("bad_args", "Missing url or cookies", null)
            return
        }

        try {
            val manager = CookieManager.getInstance()
            for (cookie in cookies) {
                manager.setCookie(url, cookie)
            }
            manager.flush()
            result.success(null)
        } catch (error: Throwable) {
            result.error("set_cookies_failed", error.message, null)
        }
    }

    private fun flushCookies(result: MethodChannel.Result) {
        try {
            CookieManager.getInstance().flush()
            result.success(null)
        } catch (error: Throwable) {
            result.error("flush_failed", error.message, null)
        }
    }

    private fun openInstallPermissionSettings(result: MethodChannel.Result) {
        try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                )
            } else {
                Intent(Settings.ACTION_SECURITY_SETTINGS)
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            result.success(null)
        } catch (error: Throwable) {
            result.error("open_settings_failed", error.message, null)
        }
    }

    private fun installApk(arguments: Map<*, *>?, result: MethodChannel.Result) {
        val path = arguments?.get("path") as? String
        if (path.isNullOrBlank()) {
            result.error("bad_args", "Missing APK path", null)
            return
        }

        try {
            val file = File(path)
            if (!file.exists()) {
                result.error("missing_apk", "APK file not found", null)
                return
            }
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.apk_provider",
                file,
            )
            val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                data = uri
                clipData = ClipData.newUri(contentResolver, "UWHLife update", uri)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
            }
            startActivity(intent)
            result.success(null)
        } catch (error: Throwable) {
            result.error("install_failed", error.message, null)
        }
    }
}
