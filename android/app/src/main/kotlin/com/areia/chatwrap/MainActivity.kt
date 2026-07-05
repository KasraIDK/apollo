package com.areia.chatwrap

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.areia.chatwrap/path"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getNativeLibPath") {
                // This gets the absolute path to where the OS extracted libareia.so
                val libraryPath = context.applicationInfo.nativeLibraryDir
                result.success(libraryPath)
            } else {
                result.notImplemented()
            }
        }
    }
}