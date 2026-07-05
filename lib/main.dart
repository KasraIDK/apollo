import 'package:flutter/material.dart';
import 'rust_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const AreiaApp());

class AreiaApp extends StatelessWidget {
  const AreiaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final AreiaController _areia = AreiaController();
  final List<ChatMessage> _chatHistory = [];
  final TextEditingController _msgInput = TextEditingController();

  // Screen States
  bool _hasKey = false;
  bool _isConnected = false;
  bool _isLoading = true;
  bool _autoScroll = true;

  // Controllers
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _ipController = TextEditingController(text: "1.2.3.4:1234");
  final TextEditingController _nickController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSavedSettings(); //load prev IP
    _checkInitialState();
    
    _areia.messages.listen((line) {
      // regex for parsing client output "sender > msg" or "sender -> msg"
      // \s*(?:->|>)\s* matches either "->" or ">" with surrounding spaces
      // (.*)$ matches the rest of the message
      final regex = RegExp(r'^(.+?)\s*(?:->|>)\s*(.*)$');
      final match = regex.firstMatch(line);

      String sender = "Unknown";
      String text = line;

      if (match != null) {
        sender = match.group(1)?.trim() ?? "Unknown";
        text = match.group(2)?.trim() ?? "";
      }

      if (sender == "Server") {
        _showServerPopup(text);
      }
      
      setState(() {
        _chatHistory.add(ChatMessage(
          text: text, 
          sender: sender,
          timestamp: DateTime.now(),
          )
        );
      });
      _scrollToBottom();
    });
  }

    // Fetch the saved IP from storage
  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString('last_ip');
    final savedNick = prefs.getString('last_nick');
    if (savedIp != null && savedIp.isNotEmpty) {
      setState(() {
        _ipController.text = savedIp;
      });
    }
    if (savedNick != null && savedNick.isNotEmpty) {
      setState(() {
        _nickController.text = savedNick;
      });
    }
  }

  // save IP for future
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_ip', _ipController.text);
    await prefs.setString('last_nick', _nickController.text);
  }

  // Check if the 'key' file exists on startup
  Future<void> _checkInitialState() async {
    final exists = await _areia.hasKey;
    setState(() {
      _hasKey = exists;
      _isLoading = false;
    });
  }

  // if key exists and user wants to reset
  void _goToKeySetup() {
    _areia.stopMessaging();
    
    setState(() {
      _hasKey = false;
      _isConnected = false;
    });
  }

  // Step 1: Handle Key Generation
  void _setupKey() async {
    if (_keyController.text.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      await _areia.setupKey(_keyController.text);
      setState(() {
        _hasKey = true;
        _isLoading = false;
      });
    } catch (e) {
      _showError("Key Setup Failed: $e");
      setState(() => _isLoading = false);
    }
  }

  // Step 2: Handle Connection
  void _connect() async {
    setState(() => _isLoading = true);
    try {
      await _areia.startMessaging(_ipController.text);
      await _saveSettings(); //save IP and nick

      setState(() {
        _isConnected = true;
        _isLoading = false;
      });

      

    } catch (e) { // This catch block is rather useless as we never know if a connection fails or not
      _showError("Connection Failed: $e");
      setState(() => _isLoading = false);
    }
    _handleNick();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showServerPopup(String message) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            SizedBox(width: 10),
            Text("Server Notification"),
          ],
        ),
        content: Text(message),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, // Makes buttons full-width hit targets
            children: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  _handleReturn();
                },
                child: const Text("Leave Chat")
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Dismiss"),
              ),
            ],
          ),
        ],
      );
    },
  );
  }

  void _openColorPickerDialog() {
    // A palette list of vibrant, high-contrast colors suited for your Dark Theme
    final List<Color> colorsPalette = [
      Colors.blueAccent,
      Colors.cyanAccent,
      Colors.greenAccent,
      Colors.lightGreenAccent,
      Colors.amberAccent,
      Colors.orangeAccent,
      Colors.redAccent,
      Colors.pinkAccent,
      Colors.purpleAccent,
      const Color.fromARGB(255, 163, 78, 248),
      //const Color(0xFFE0D0FF), // Pastel lavender
      //const Color(0xFFFFD0E0), // Soft rose
      const Color.fromARGB(255, 254, 183, 207),
      const Color(0xFFDCDCD5), // Your layout's base off-white fallback
    ];

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Select Name Color"),
          content: SizedBox(
            width: 300,
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: colorsPalette.length,
              itemBuilder: (context, index) {
                final color = colorsPalette[index];
                return InkWell(
                  onTap: () {
                    final baseNick = _stripHexFromController(_nickController.text);
                    final hexTag = _colorToHex(color);
                    
                    setState(() {
                      // Combine name text and newly picked hex color back to the controller
                      _nickController.text = baseNick.isEmpty ? "User$hexTag" : "$baseNick$hexTag";
                    });
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 2),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            )
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        /*leading: (
          /*switch (_isConnected) { // We want the return button to only show if we are connected
            false => null,
            true => (
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _handleReturn,
                tooltip: "Return",
              )
            )
          }*/
        ),*/
        automaticallyImplyLeading: switch (_isConnected) {
          true => true,
          false => false
        },
        title: const Text("Apollo"),
        bottom: switch (_autoScroll) {
          true => null,
          false => AppBar(
            automaticallyImplyLeading: false,
            title: Text('Auto scroll is disabled', textScaler: TextScaler.linear(0.8)),
            toolbarOpacity: 0.8,
            scrolledUnderElevation: 0,
            actions: [FilledButton(
              onPressed: () {
                setState(() => _autoScroll = true);
                _scrollToBottom();
              }, 
              child: Text('Enable')
            )],
            actionsPadding: EdgeInsetsGeometry.all(10),
          )
        },
        bottomOpacity: 1.0,
        centerTitle: true,
        /* actions: [
        // Only show reload if we are actually connected
        if (_isConnected)
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _handleReload,
            tooltip: "Restart Processes",
          ),
        if (_isConnected)
          IconButton(
            onPressed: _handleClearLogs, 
            icon: const Icon(Icons.delete_rounded),
            tooltip: "Clear Logs",
          ),
        if (_isConnected)  
          Checkbox(
            value: _autoScroll, 
            onChanged: (bool? lol) {
              setState(() {
                _autoScroll = !_autoScroll;
              });
            },
          ),
        ], */
        actions: [
          if (_isConnected)
            IconButton(
              onPressed: () {_areia.sendMessage("/viewmemos");}, 
              icon: const Icon(Icons.note_alt_rounded),
              tooltip: "View memos",
            ),
          if (_isConnected)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _handleReload,
              tooltip: "Reload",
            ),
        ],
        animateColor: true,
      ),
      drawer: Drawer(
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor
              ),
              child: (
                Center(
                  child: Column(children: [
                    Expanded(child: Container()),
                    Text('Connected to'),
                    Text(_ipController.text)
                  ],),
                )
              ),
            ),
            // Row(children: [
            //   VerticalDivider(),
            //   Expanded(child: FilledButton.icon(onPressed: () {print("lol");}, label: Text('Add Memo'), icon: Icon(Icons.abc))),
            //   VerticalDivider(),
            // ],),
            // Row(children: [
            //   VerticalDivider(),
            //   Expanded(child: FilledButton.icon(onPressed: () {print("lol");}, label: Text('Add Memo'), icon: Icon(Icons.abc))),
            //   VerticalDivider(),
            // ],),
            // Divider(),
            ListTile(
              leading: Icon(Icons.refresh_rounded),
              title: Text("Reload"),
              onTap: () {
                Navigator.pop(context);
                _handleReload();
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_rounded),
              title: Text("Clear Logs"),
              onTap: () {
                Navigator.pop(context);
                _handleClearLogs();
              }
            ),
            Divider(),
            CheckboxListTile(
              value: !_autoScroll, 
              onChanged: (bool? lol) {
                setState(() {
                  _autoScroll = !_autoScroll;
                });
              },
              title: Text('Disable Auto Scroll')
            ),
            Expanded(child: Container()),
            ListTile(
              leading: Icon(Icons.logout_rounded),
              title: Text("Leave Chat"),
              onTap: () {
                Navigator.pop(context);
                _handleReturn();
              },
            ),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (!_hasKey) return _buildKeyStep();
    if (!_isConnected) return _buildConnectionStep();
    return _buildChatStep();
  }

  // --- UI SCREENS ---

  Widget _buildKeyStep() {
    return Padding(
      padding: const EdgeInsets.all(30.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.vpn_key, size: 60, color: Colors.blueAccent),
          const SizedBox(height: 20),
          const Text("Encryption Key Required", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Text("This will create a 'key' file in your app directory.", textAlign: TextAlign.center),
          const SizedBox(height: 20),
          TextField(
            controller: _keyController,
            obscureText: true,
            decoration: const InputDecoration(labelText: "Enter New Key", border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: _setupKey, child: const Text("Generate Key File")),
        ],
      ),
    );
  }

  Widget _buildConnectionStep() {
    final Color currentIconColor = _parseInlineHex(
      _nickController.text, 
      const Color(0xFFDCDCD5),
    );

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(child: Container()),
          Expanded(child: Container()),
          TextField(controller: _ipController, decoration: const InputDecoration(labelText: "Server Address (IP:Port)", border: OutlineInputBorder()), onSubmitted: (_) => _connect()),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: _connect, child: const Text("Start Areia"), ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _goToKeySetup,
            icon: const Icon(Icons.vpn_key_outlined, size: 18),
            label: const Text("Reset Encryption Key"),
          ),
          Expanded(child: Container()),
          FractionallySizedBox(
            widthFactor: 0.85, // Bumped slightly to account for layout alignment
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nickController, 
                    decoration: const InputDecoration(
                      labelText: "Nickname (name#hex)", 
                      border: OutlineInputBorder(),
                      hintText: "Apollo#FF5733",
                    ),
                    onChanged: (_) {
                      // Rebuilds layout wrapper so icon visualizer updates dynamically if manually editing hex text
                      setState(() {}); 
                    },
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: _openColorPickerDialog,
                  icon: Icon(Icons.palette_rounded, color: currentIconColor,),
                  tooltip: "Pick Custom Color",
                  style: IconButton.styleFrom(
                    minimumSize: const Size(54, 54), // Matches textfield default vertical bounds
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                )
              ],
            ),
          ),
          Expanded(child: Container())
        ],
      ),
    );
  }

  Widget _buildChatStep() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(10),
            itemCount: _chatHistory.length,
            itemBuilder: (context, i) {
              final msg = _chatHistory[i];
              var lastHeaderTime = msg.timestamp.minute; // We want to compare latest message time with the last time header was shown
              
              bool showHeader = false;

              if (i == 0) {
                showHeader = true;
                lastHeaderTime = msg.timestamp.minute;
              } else {
                final prevMsg = _chatHistory[i - 1];
                
                // Show header if sender changed OR if 3 minutes passed (read above and below comment)
                if (msg.sender != prevMsg.sender || 
                    (msg.timestamp.minute - lastHeaderTime).abs() >= 3) { // The abs ensures an edge case like (13:)00 - (12:)57 will still work
                  showHeader = true;
                  lastHeaderTime = msg.timestamp.minute;
                }
              }

              return _ChatBubble(
                text: msg.text, 
                sender: showHeader ? msg.sender : null,
                time: showHeader ? "${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}" : null,
              );
            },
          ),
        ),
        _buildInputArea(),
      ],
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.black26,
      child: Row(
        children: [
          IconButton.filledTonal(icon: const Icon(Icons.list_rounded), onPressed: _handleList, tooltip: "Request List",),
          Expanded(
            child: TextField(
              controller: _msgInput,
              decoration: const InputDecoration(hintText: "Type a message...", border: InputBorder.none, contentPadding: EdgeInsets.all(6)),
              onSubmitted: (_) => _handleSend(),
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 4,
              minLines: 1,
            ),
          ),
          IconButton.filled(icon: const Icon(Icons.send_rounded), onPressed: _handleSend, tooltip: "Send Message",),
        ],
      ),
    );
  }

  void _handleSend() {
    if (_msgInput.text.isNotEmpty) {
      _areia.sendMessage(_msgInput.text);
      _msgInput.clear();
    }
  }

  void _handleNick() {
    if (_nickController.text.isNotEmpty) {
      _areia.sendMessage("/setnick ${_nickController.text}");
    }
  }

  void _handleList() {
    _areia.sendMessage("/list");
  }

  final ScrollController _scrollController = ScrollController();

  void _scrollToBottom() {
    // Wait for the next frame so the ListView has time to add the new bubble
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _autoScroll) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleReturn() {
    _areia.stopMessaging();
    _handleClearLogs();
    
    setState(() {
      _isConnected = false;
    });
  }

  void _handleReload() async {
    setState(() => _isLoading = true);
    try {
      // Clear chat history on reload
      //setState(() => _chatHistory.clear());
      
      await _areia.restartMessaging(_ipController.text);

      await Future.delayed(const Duration(milliseconds: 100));
      
      //_showError("Areia Restarted"); // Disabled because unnecessary and annoying; if successful will load, if unsuccessful, will error

      _scrollToBottom();

    } catch (e) {
      _showError("Restart failed: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  void _handleClearLogs() async {
    setState(() => _chatHistory.clear());
  }

  @override
  void dispose() {
    // This kills the Rust processes when the UI is destroyed
    _areia.dispose(); 
    super.dispose();
  }
}

class _ChatBubble extends StatelessWidget {
  final String text;
  final String? sender;
  final String? time;

  const _ChatBubble({required this.text, this.sender, this.time});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sender != null)
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4, left: 12),
            child: Row(
              children: [
                Text(
                  _cleanSenderName(sender!),
                  style: TextStyle(
                    color: switch (sender.toString().toLowerCase()) {
                      "server" => Colors.deepOrangeAccent,

                      "list" => Colors.amberAccent,

                      "memo" => Colors.lightGreenAccent,
                      
                      String s => _parseInlineHex(s, Color.fromARGB(255, 220, 220, 213)) 
                    }, // Users are shown as blue, memo is green, list is yellow, server is orange
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  time!,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blueGrey[800],
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }
}

class ChatMessage {
  final String text;
  final String sender;
  final DateTime timestamp;

  ChatMessage({required this.text, required this.sender, required this.timestamp,});
}

Color _parseInlineHex(String sender, Color fallback) {
  // Finds # followed by exactly 6 hex characters at the end of the name
  final match = RegExp(r'#([0-9a-fA-F]{6})$').firstMatch(sender);
  if (match == null) return fallback;

  try {
    final hexCode = match.group(1)!;
    return Color(int.parse("FF$hexCode", radix: 16));
  } catch (_) {
    return fallback;
  }
}

String _cleanSenderName(String sender) {
  // Removes #****** from the end of the string if it exists
  return sender.replaceAll(RegExp(r'#[0-9a-fA-F]{6}$'), '').trim();
}

// Helper to extract a standard Hex String from a Flutter Color Object
String _colorToHex(Color color) {
  return '#${color.value.toRadixString(16).substring(2, 8).toUpperCase()}';
}

// Extract any text before the '#' mark inside a text input field 
String _stripHexFromController(String currentInput) {
  final index = currentInput.indexOf('#');
  if (index == -1) return currentInput.trim();
  return currentInput.substring(0, index).trim();
}