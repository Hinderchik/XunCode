package com.vscode.android

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val TOR_CHANNEL = "com.vscode.android/tor"
    private val TERMINAL_CHANNEL = "com.vscode.android/terminal"
    private val TERMINAL_EVENTS = "com.vscode.android/terminal/events"

    private lateinit var terminalService: TerminalService
    private val sinks = mutableMapOf<String, EventChannel.EventSink>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        terminalService = TerminalService(applicationContext)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TOR_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startTor" -> {
                    runCatching {
                        val intent = android.content.Intent("org.torproject.android.intent.action.START")
                        intent.setPackage("org.torproject.android")
                        sendBroadcast(intent)
                    }
                    result.success(true)
                }
                "stopTor" -> {
                    runCatching {
                        val intent = android.content.Intent("org.torproject.android.intent.action.STOP")
                        intent.setPackage("org.torproject.android")
                        sendBroadcast(intent)
                    }
                    result.success(true)
                }
                "isRunning" -> result.success(false)
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TERMINAL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAlpineInstalled" -> result.success(terminalService.isInstalled())
                "rootfsPath" -> result.success(terminalService.rootfsDir().absolutePath)
                "markAlpineInstalled" -> {
                    terminalService.markInstalled()
                    result.success(true)
                }
                "prootBinaryExists" -> {
                    val f = terminalService.prootBinary()
                    result.success(f.exists() && f.length() > 0)
                }
                "create" -> {
                    val id = call.argument<String>("id") ?: return@setMethodCallHandler result.error("ARG", "missing id", null)
                    val cols = call.argument<Int>("cols") ?: 80
                    val rows = call.argument<Int>("rows") ?: 24
                    val sink = sinks[id]
                    if (sink == null) {
                        result.error("NO_SINK", "subscribe to events for id=$id first", null)
                    } else {
                        val msg = terminalService.create(id, cols, rows, sink)
                        result.success(msg)
                    }
                }
                "write" -> {
                    val id = call.argument<String>("id") ?: return@setMethodCallHandler result.error("ARG", "missing id", null)
                    val data = call.argument<String>("data") ?: ""
                    result.success(terminalService.write(id, data))
                }
                "resize" -> {
                    val id = call.argument<String>("id") ?: return@setMethodCallHandler result.error("ARG", "missing id", null)
                    val cols = call.argument<Int>("cols") ?: 80
                    val rows = call.argument<Int>("rows") ?: 24
                    result.success(terminalService.resize(id, cols, rows))
                }
                "kill" -> {
                    val id = call.argument<String>("id") ?: return@setMethodCallHandler result.error("ARG", "missing id", null)
                    result.success(terminalService.kill(id))
                }
                "killAll" -> {
                    terminalService.killAll()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, TERMINAL_EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    val id = (arguments as? Map<*, *>)?.get("id") as? String
                        ?: (arguments as? String)
                        ?: return events.error("ARG", "missing id", null)
                    sinks[id] = events
                }
                override fun onCancel(arguments: Any?) {
                    val id = (arguments as? Map<*, *>)?.get("id") as? String
                        ?: (arguments as? String)
                        ?: return
                    sinks.remove(id)
                    terminalService.kill(id)
                }
            }
        )
    }

    override fun onDestroy() {
        runCatching { terminalService.killAll() }
        super.onDestroy()
    }
}
