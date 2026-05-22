package com.xunkal1.xuncode

import android.content.Context
import android.os.Environment
import io.flutter.plugin.common.EventChannel
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.io.OutputStream
import java.util.concurrent.ConcurrentHashMap

/**
 * Manages multiple proot+Alpine shell sessions. Each session is backed by a
 * native proot process whose stdin/stdout is bridged to Dart via
 * MethodChannel (write/resize/kill) and EventChannel (output stream).
 *
 * Storage layout:
 *  - Private:  context.getExternalFilesDir(null)
 *      = /storage/emulated/0/Android/data/<pkg>/files/
 *  - Shared:   <external>/Shared/XunCode/
 *      = /storage/emulated/0/Shared/XunCode/   (created via Environment)
 */
class TerminalService(private val appContext: Context) {

    private val sessions = ConcurrentHashMap<String, TerminalSession>()

    fun appDataDir(): File {
        val ext = appContext.getExternalFilesDir(null)
            ?: appContext.filesDir
        if (!ext.exists()) ext.mkdirs()
        return ext
    }

    fun sharedDir(): File {
        val external = Environment.getExternalStorageDirectory()
        val preferred = File(external, "Shared/XunCode")
        if (canWriteTo(preferred)) return preferred

        val fallback = File(appContext.getExternalFilesDir(null), "Shared/XunCode")
        if (!fallback.exists()) fallback.mkdirs()
        return fallback
    }

    private fun canWriteTo(dir: File): Boolean {
        return try {
            if (!dir.exists() && !dir.mkdirs()) return false
            val probe = File(dir, ".xc-write-probe")
            probe.writeText("ok")
            probe.delete()
            true
        } catch (_: Throwable) {
            false
        }
    }

    fun rootfsDir(): File {
        val d = File(appDataDir(), "rootfs")
        if (!d.exists()) d.mkdirs()
        return d
    }

    private fun fallbackProotBinary(): File = File(appDataDir(), "proot/proot")

    fun prootBinary(): File {
        val native = File(appContext.applicationInfo.nativeLibraryDir, "libproot.so")
        if (native.exists() && native.length() > 0) return native
        return fallbackProotBinary()
    }

    fun downloadProot(): String {
        val abi = android.os.Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"
        val proot = when (abi) {
            "arm64-v8a" -> "proot-aarch64"
            "armeabi-v7a" -> "proot-armv7a"
            "x86_64" -> "proot-x86_64"
            "x86" -> "proot-x86"
            else -> "proot-aarch64"
        }
        val mirrors = listOf(
            "https://github.com/proot-me/proot-static-build/releases/download/v5.4.0/$proot",
            "https://github.com/proot-me/proot-static-build/releases/latest/download/$proot",
        )
        val out = fallbackProotBinary()
        out.parentFile?.mkdirs()
        var lastError: String? = null
        for (url in mirrors) {
            try {
                val conn = (java.net.URL(url).openConnection() as java.net.HttpURLConnection)
                conn.connectTimeout = 15000
                conn.readTimeout = 60000
                conn.instanceFollowRedirects = true
                conn.requestMethod = "GET"
                if (conn.responseCode in 200..299) {
                    conn.inputStream.use { input ->
                        out.outputStream().use { output -> input.copyTo(output) }
                    }
                    if (out.length() < 1024) {
                        out.delete()
                        lastError = "downloaded file too small from $url"
                        continue
                    }
                    out.setExecutable(true, false)
                    return "ok"
                }
                lastError = "HTTP ${conn.responseCode} from $url"
            } catch (t: Throwable) {
                lastError = "${t.javaClass.simpleName}: ${t.message}"
            }
        }
        return "error: ${lastError ?: "unknown"}"
    }

    fun create(id: String, cols: Int, rows: Int, sink: EventChannel.EventSink): String {
        kill(id)
        val session = TerminalSession(this, id, cols, rows, sink)
        sessions[id] = session
        return session.start()
    }

    fun write(id: String, data: String): Boolean {
        val s = sessions[id] ?: return false
        return s.write(data)
    }

    fun resize(id: String, cols: Int, rows: Int): Boolean {
        val s = sessions[id] ?: return false
        s.resize(cols, rows)
        return true
    }

    fun kill(id: String): Boolean {
        val s = sessions.remove(id) ?: return false
        s.kill()
        return true
    }

    fun killAll() {
        sessions.values.forEach { runCatching { it.kill() } }
        sessions.clear()
    }

    fun isInstalled(): Boolean = File(rootfsDir(), ".installed").exists()

    fun markInstalled() {
        rootfsDir().mkdirs()
        File(rootfsDir(), ".installed").writeText("ok")
    }

    fun startUnsandboxed(id: String, sink: EventChannel.EventSink): String {
        kill(id)
        val session = TerminalSession(this, id, 80, 24, sink, useSystemSh = true)
        sessions[id] = session
        return session.start()
    }

    fun appExternalHome(): String {
        val shared = sharedDir()
        if (shared.canRead()) return shared.absolutePath
        val ext = appContext.getExternalFilesDir(null)
        if (ext != null && ext.canRead()) return ext.absolutePath
        return appContext.filesDir.absolutePath
    }
}

class TerminalSession(
    private val service: TerminalService,
    val id: String,
    @Volatile var cols: Int,
    @Volatile var rows: Int,
    private val sink: EventChannel.EventSink,
    private val useSystemSh: Boolean = false,
) {
    private var process: Process? = null
    private var writer: OutputStream? = null
    private var readerThread: Thread? = null

    fun start(): String {
        if (useSystemSh) return startSystemSh()

        val proot = service.prootBinary()
        val rootfs = service.rootfsDir()

        if (!proot.exists() || proot.length() == 0L) {
            return emit("[terminal] proot binary missing")
        }
        if (!service.isInstalled()) {
            return emit("[terminal] Alpine rootfs not installed yet — run installAlpine first")
        }

        return try {
            runCatching { proot.setExecutable(true, false) }

            val shared = service.sharedDir().absolutePath
            val pb = ProcessBuilder(
                proot.absolutePath,
                "-r", rootfs.absolutePath,
                "-w", "/root",
                "-b", "/dev",
                "-b", "/proc",
                "-b", "/sys",
                "-b", "/dev/urandom:/dev/random",
                "-b", "/proc/self/fd:/dev/fd",
                "-b", "$shared:/sdcard/XunCode",
                "-b", "$shared:/home/user",
                "-0",
                "/bin/sh", "-l",
            )
            pb.environment().apply {
                put("HOME", "/root")
                put("TERM", "xterm-256color")
                put("PS1", "alpine:\\w# ")
                put("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
                put("LANG", "C.UTF-8")
                put("PROOT_TMP_DIR", File(service.appDataDir(), "tmp").absolutePath)
                put("XUNCODE_HOME", "/sdcard/XunCode")
                put("COLUMNS", cols.toString())
                put("LINES", rows.toString())
            }
            pb.redirectErrorStream(true)

            val p = pb.start()
            process = p
            writer = p.outputStream

            readerThread = Thread({ pumpOutput(p) }, "term-$id-reader").apply { isDaemon = true; start() }
            "ok"
        } catch (t: Throwable) {
            emit("[terminal] failed to start: ${t.message}\n")
        }
    }

    private fun startSystemSh(): String {
        return try {
            val home = service.appExternalHome()
            val pb = ProcessBuilder("/system/bin/sh")
            pb.directory(File(home))
            pb.environment().apply {
                put("HOME", home)
                put("PWD", home)
                put("TERM", "xterm-256color")
                put("PS1", "$ ")
                put("COLUMNS", cols.toString())
                put("LINES", rows.toString())
                put("PATH", "/sbin:/system/sbin:/system/bin:/system/xbin:/vendor/bin:/vendor/xbin")
            }
            pb.redirectErrorStream(true)
            val p = pb.start()
            process = p
            writer = p.outputStream
            readerThread = Thread({ pumpOutput(p) }, "term-$id-reader").apply {
                isDaemon = true; start()
            }
            emit(buildString {
                append("[terminal] limited Android shell — proot not available\n")
                append("Working directory: $home\n")
                append("Available: ls, cat, ps, busybox subset.\n")
                append("python / apt are NOT available here. For a full Linux shell,\n")
                append("retry the proot download from the Terminal panel.\n\n")
            })
            "ok"
        } catch (t: Throwable) {
            emit("[terminal] system sh failed: ${t.message}\n")
        }
    }

    private fun pumpOutput(p: Process) {
        val reader = BufferedReader(InputStreamReader(p.inputStream, Charsets.UTF_8))
        val buf = CharArray(4096)
        try {
            while (!Thread.currentThread().isInterrupted) {
                val n = reader.read(buf)
                if (n <= 0) break
                val text = String(buf, 0, n)
                postToMain { runCatching { sink.success(text) } }
            }
        } catch (_: Throwable) {
            // stream closed
        } finally {
            postToMain { runCatching { sink.endOfStream() } }
        }
    }

    fun write(data: String): Boolean {
        val w = writer ?: return false
        return try {
            w.write(data.toByteArray(Charsets.UTF_8))
            w.flush()
            true
        } catch (_: Throwable) {
            false
        }
    }

    fun resize(c: Int, r: Int) {
        cols = c
        rows = r
    }

    fun kill() {
        runCatching { writer?.close() }
        runCatching { process?.destroy() }
        runCatching { readerThread?.interrupt() }
        process = null
        writer = null
        readerThread = null
    }

    private fun emit(msg: String): String {
        postToMain { runCatching { sink.success(msg) } }
        return msg
    }

    private fun postToMain(block: () -> Unit) {
        android.os.Handler(service.appContextLooper()).post(block)
    }
}

private fun TerminalService.appContextLooper() = android.os.Looper.getMainLooper()
