package com.vscode.android

import android.content.Context
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
 * Because Android forbids exec() from /data/data on API 29+, the proot ELF is
 * shipped as android/app/src/main/jniLibs/<abi>/libproot.so and resolved at
 * runtime via applicationInfo.nativeLibraryDir. The Alpine rootfs is unpacked
 * to filesDir/alpine on the Dart side using the `archive` package.
 */
class TerminalService(private val appContext: Context) {

    private val sessions = ConcurrentHashMap<String, TerminalSession>()

    fun rootfsDir(): File = File(appContext.filesDir, "alpine")

    private fun fallbackProotBinary(): File = File(appContext.filesDir, "bin/proot")

    fun prootBinary(): File {
        val native = File(appContext.applicationInfo.nativeLibraryDir, "libproot.so")
        if (native.exists() && native.length() > 0) return native
        return fallbackProotBinary()
    }

    fun downloadProot(): String {
        val arch = when (android.os.Build.SUPPORTED_ABIS.firstOrNull()) {
            "arm64-v8a" -> "proot-aarch64"
            "armeabi-v7a" -> "proot-armv7a"
            "x86_64" -> "proot-x86_64"
            else -> "proot-aarch64"
        }
        val mirrors = listOf(
            "https://github.com/proot-me/proot-static-build/releases/download/v5.4.0/$arch",
            "https://github.com/termux/proot/releases/download/v5.4.0/$arch",
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
                    out.setExecutable(true, false)
                    return "ok"
                }
                lastError = "HTTP ${conn.responseCode}"
            } catch (t: Throwable) {
                lastError = t.message
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
            // Make sure the binary is executable. nativeLibraryDir entries are
            // already 0755 in practice, but this is cheap insurance.
            runCatching { proot.setExecutable(true, false) }

            val pb = ProcessBuilder(
                proot.absolutePath,
                "-r", rootfs.absolutePath,
                "-w", "/root",
                "-b", "/dev",
                "-b", "/proc",
                "-b", "/sys",
                "-b", "/dev/urandom:/dev/random",
                "-b", "/proc/self/fd:/dev/fd",
                "-0",
                "/bin/sh", "-l",
            )
            pb.environment().apply {
                put("HOME", "/root")
                put("TERM", "xterm-256color")
                put("PS1", "alpine:\\w# ")
                put("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
                put("LANG", "C.UTF-8")
                put("PROOT_TMP_DIR", File(service.rootfsDir(), "tmp").absolutePath)
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
            val pb = ProcessBuilder("/system/bin/sh")
            pb.environment().apply {
                put("HOME", service.rootfsDir().absolutePath)
                put("TERM", "xterm-256color")
                put("PS1", "$ ")
                put("COLUMNS", cols.toString())
                put("LINES", rows.toString())
            }
            pb.redirectErrorStream(true)
            val p = pb.start()
            process = p
            writer = p.outputStream
            readerThread = Thread({ pumpOutput(p) }, "term-$id-reader").apply {
                isDaemon = true; start()
            }
            emit("[terminal] running in unsandboxed mode (/system/bin/sh)\n")
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
        // No PTY ioctl in this minimal implementation. We update env vars on
        // the next session start; running shells will not see the new size.
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
