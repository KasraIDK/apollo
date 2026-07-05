import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

class AreiaController {
  Process? _listenerProcess;
  Process? _senderProcess;

  static const platform = MethodChannel('com.areia.chatwrap/path');
  
  // Stream to send incoming messages to the UI
  final _messageStream = StreamController<String>.broadcast();
  Stream<String> get messages => _messageStream.stream;

  Future<String> get _binaryPath async {
    // 1. Ask Android where the native libs are
    final String libDir = await platform.invokeMethod('getNativeLibPath');
    
    // 2. Point to our renamed binary
    final String path = "$libDir/libareia.so";
    
    if (await File(path).exists()) {
      return path;
    }
    throw Exception("Binary STILL not found at $path. Is it in jniLibs/arm64-v8a?");
  }

  Future<String> get _workingDir async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  // Check if the key file already exists in the working directory
  Future<bool> get hasKey async {
    final wd = await _workingDir;
    final keyFile = File('$wd/key'); // Assuming Rust names it key.dat
    return await keyFile.exists();
  }

  // 1. Initial Key Setup
  Future<void> setupKey(String key) async {
    final bin = await _binaryPath;
    final wd = await _workingDir;

    print("Generating key file in $wd...");
    
    // Start the 'key' process
    final proc = await Process.start(bin, ['key'], workingDirectory: wd);
    
    // Pipe the key into Rust's stdin
    proc.stdin.writeln(key);
    await proc.stdin.flush();
    
    // CRITICAL: Wait for the process to exit to ensure the file is written
    final exitCode = await proc.exitCode;
    
    if (exitCode == 0) {
      print("Key setup successful.");
    } else {
      // Capture stderr if something went wrong
      final error = await proc.stderr.transform(utf8.decoder).join();
      throw Exception("Key setup failed with exit code $exitCode: $error");
    }
  }

  // 2. Start Communication
  Future<void> startMessaging(String serverAddr) async {
    final bin = await _binaryPath;
    final wd = await _workingDir;

        // --- 1. START LISTENER ---
    _listenerProcess = await Process.start(bin, ['listener'], workingDirectory: wd);
    
    _listenerProcess!.stderr.transform(utf8.decoder).listen((error) {
      print("RUST CRITICAL ERROR: $error");
    });

    bool firstLineSkipped = false;
    
    // Listen to output
    _listenerProcess!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
            if (!firstLineSkipped) {
                firstLineSkipped = true;
                print("Skipped Listener prompt: $line");
                return; 
            }
            _messageStream.add(line); 
        });

    // GIVE RUST A MOMENT TO BREATHE
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Send inputs to Listener
    _listenerProcess!.stdin.writeln(serverAddr);
    await _listenerProcess!.stdin.flush(); // Force the data through the pipe



    // --- 2. START SENDER ---
    _senderProcess = await Process.start(bin, ['sender'], workingDirectory: wd);
    
    await Future.delayed(const Duration(milliseconds: 500));

    // Send inputs to Sender
    _senderProcess!.stdin.writeln(serverAddr);
    await _senderProcess!.stdin.flush();
    
    print("Handshakes sent to both processes.");
  }

  // 3. Send a Message
  void sendMessage(String text) {
    _senderProcess?.stdin.writeln(text);
  }

  void stopMessaging() {
  _listenerProcess?.kill();
  _senderProcess?.kill();
  _listenerProcess = null;
  _senderProcess = null;
}

  Future<void> restartMessaging(String serverAddr) async {
    stopMessaging(); 
    // Wait a tiny bit for the OS to release the ports
    await Future.delayed(const Duration(milliseconds: 200)); 
    await startMessaging(serverAddr);
  }

  void dispose() {
  _listenerProcess?.kill();
  _senderProcess?.kill();
  _messageStream.close();
}
}