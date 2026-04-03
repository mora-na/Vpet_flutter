import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math";

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";

void main() {
  runApp(const VPetApp());
}

class VPetApp extends StatelessWidget {
  const VPetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "VPet Flutter",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4A83C4),
          brightness: Brightness.dark,
        ),
      ),
      home: const VPetHomePage(),
    );
  }
}

class VPetHomePage extends StatefulWidget {
  const VPetHomePage({super.key});

  @override
  State<VPetHomePage> createState() => _VPetHomePageState();
}

class _VPetHomePageState extends State<VPetHomePage> {
  static const MethodChannel _windowChannel = MethodChannel("vpet/window");
  final _rng = Random();
  Future<CharacterManifest> _manifestFuture =
      CharacterManifest.loadForCharacter("mu");
  String _characterId = "mu";

  Timer? _statusTimer;
  Timer? _behaviorTimer;
  Timer? _actionResetTimer;
  Timer? _bubbleTimer;
  Timer? _movementTimer;
  Timer? _scheduleTimer;
  Timer? _dialogTimer;

  bool _runtimeStarted = false;
  bool _showDebugZones = false;
  String _action = "default";
  String? _bubbleText;
  DateTime _lastInteraction = DateTime.now();

  double _strength = 72;
  double _strengthFood = 68;
  double _strengthDrink = 70;
  double _feeling = 74;
  bool _windowMetricsReady = false;
  double _windowX = 0;
  double _windowY = 0;
  double _windowW = 280;
  double _windowH = 280;
  double _screenMinX = 0;
  double _screenMinY = 0;
  double _screenMaxX = 1280;
  double _screenMaxY = 800;
  Offset _petVelocity = const Offset(1.35, 0.92);
  int _windowIndex = 0;
  List<ScheduleEntry> _scheduleEntries = [];
  DateTime _lastScheduleTrigger = DateTime.fromMillisecondsSinceEpoch(0);
  String? _dialogTitle;
  String? _dialogLineA;
  String? _dialogLineB;
  final PetKnowledgeBase _knowledgeBase = PetKnowledgeBase();
  final PetAiService _aiService = PetAiService();
  final ScheduleRepository _scheduleRepository = ScheduleRepository();

  @override
  void initState() {
    super.initState();
    _windowChannel.setMethodCallHandler(_handleNativeMethodCall);
    _loadSchedules();
    _startScheduleLoop();
  }

  @override
  void dispose() {
    _windowChannel.setMethodCallHandler(null);
    _statusTimer?.cancel();
    _behaviorTimer?.cancel();
    _actionResetTimer?.cancel();
    _bubbleTimer?.cancel();
    _movementTimer?.cancel();
    _scheduleTimer?.cancel();
    _dialogTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleNativeMethodCall(MethodCall call) async {
    if (call.method != "peerInteraction") {
      return;
    }
    final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
    final interactionType = (args["type"] as String? ?? "greet").trim();
    switch (interactionType) {
      case "schedule_dialog":
        final title = (args["title"] as String? ?? "").trim();
        final a = (args["a"] as String? ?? "今天按计划进行。").trim();
        final b = (args["b"] as String? ?? "收到。").trim();
        final action = (args["action"] as String? ?? "default").trim();
        _showDialogueBox(title: title, lineA: a, lineB: b);
        final manifest = await _manifestFuture;
        if (!mounted) return;
        _playAction(manifest, action, hold: const Duration(seconds: 2));
        return;
      case "greet":
      default:
        _showBubble("另一只：嗨！");
        final manifest = await _manifestFuture;
        if (!mounted) return;
        _playAction(manifest, "move", hold: const Duration(seconds: 2));
    }
  }

  bool get _isPrimaryWindow => _windowIndex == 0;

  Future<void> _loadSchedules() async {
    final entries = await _scheduleRepository.load();
    if (!mounted) return;
    setState(() {
      _scheduleEntries = entries;
    });
  }

  void _startScheduleLoop() {
    _scheduleTimer?.cancel();
    _scheduleTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _handleScheduleTick();
    });
  }

  Future<void> _handleScheduleTick() async {
    if (!mounted || !_isPrimaryWindow || _scheduleEntries.isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastScheduleTrigger).inSeconds < 45) {
      return;
    }
    final active = _scheduleEntries.where((e) => e.isActiveAt(now)).toList();
    if (active.isEmpty) return;
    if (_rng.nextDouble() > 0.35) return;
    final entry = active[_rng.nextInt(active.length)];
    await _triggerScheduleEntry(entry);
    _lastScheduleTrigger = now;
  }

  Future<void> _triggerScheduleEntry(ScheduleEntry entry) async {
    final manifest = await _manifestFuture;
    if (!mounted) return;
    final desiredAction = entry.actions.isEmpty
        ? "move"
        : entry.actions[_rng.nextInt(entry.actions.length)];
    final action =
        manifest.actions.containsKey(desiredAction) ? desiredAction : "move";
    _playAction(manifest, action, hold: const Duration(seconds: 2));
    final simulator = ScheduleDialogueSimulator(
      knowledgeBase: _knowledgeBase,
      aiService: _aiService,
    );
    final pair = await simulator.generate(entry);
    if (!mounted) return;
    _showDialogueBox(title: entry.title, lineA: pair.a, lineB: pair.b);
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      try {
        await _windowChannel.invokeMethod<void>("broadcastInteraction", {
          "type": "schedule_dialog",
          "title": entry.title,
          "a": pair.a,
          "b": pair.b,
          "action": action,
        });
      } catch (_) {}
    }
  }

  void _ensureRuntime(CharacterManifest manifest) {
    if (_runtimeStarted) return;
    _runtimeStarted = true;
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() {
        if (_action == "sleep") {
          _strength = (_strength + 1.6).clamp(0, 100);
        } else {
          _strength = (_strength - 0.7).clamp(0, 100);
        }
        _strengthFood = (_strengthFood - 0.8).clamp(0, 100);
        _strengthDrink = (_strengthDrink - 1.0).clamp(0, 100);
        final idleMinutes =
            DateTime.now().difference(_lastInteraction).inSeconds / 60.0;
        final moodDrop = 0.4 + (idleMinutes > 1.5 ? 0.4 : 0);
        _feeling = (_feeling - moodDrop).clamp(0, 100);
        if (_strengthFood < 28 || _strengthDrink < 28) {
          _feeling = (_feeling - 0.6).clamp(0, 100);
        }
      });
    });
    _scheduleNextBehavior(manifest);
    _startMovementLoop();
  }

  void _startMovementLoop() {
    _movementTimer?.cancel();
    _movementTimer =
        Timer.periodic(const Duration(milliseconds: 24), (_) async {
      if (!mounted || !_windowMetricsReady) return;
      var velocity = _petVelocity;
      var speedScale = 0.0;
      if (_action == "move") {
        speedScale = 1.8;
      } else if (_action == "sleep") {
        speedScale = 0.0;
      }
      if (speedScale == 0) {
        return;
      }
      final dx = velocity.dx * speedScale;
      final dy = velocity.dy * speedScale;
      final minX = _screenMinX;
      final minY = _screenMinY;
      final maxX = _screenMaxX - _windowW;
      final maxY = _screenMaxY - _windowH;
      var nextX = _windowX + dx;
      var nextY = _windowY + dy;
      if (nextX <= minX || nextX >= maxX) {
        velocity = Offset(-velocity.dx, velocity.dy);
        nextX = nextX.clamp(minX, maxX).toDouble();
      }
      if (nextY <= minY || nextY >= maxY) {
        velocity = Offset(velocity.dx, -velocity.dy);
        nextY = nextY.clamp(minY, maxY).toDouble();
      }
      if (_rng.nextDouble() < 0.004) {
        final nvx = velocity.dx + (_rng.nextDouble() - 0.5) * 0.7;
        final nvy = velocity.dy + (_rng.nextDouble() - 0.5) * 0.45;
        velocity = Offset(nvx.clamp(-2.2, 2.2), nvy.clamp(-1.7, 1.7));
      }
      await _moveWindowBy(nextX - _windowX, nextY - _windowY);
      setState(() {
        _petVelocity = velocity;
        _windowX = nextX;
        _windowY = nextY;
      });
    });
  }

  void _scheduleNextBehavior(CharacterManifest manifest) {
    _behaviorTimer?.cancel();
    final nextSeconds = 4 + _rng.nextInt(7);
    _behaviorTimer = Timer(Duration(seconds: nextSeconds), () {
      if (!mounted) return;
      _runAutonomousBehavior(manifest);
      _scheduleNextBehavior(manifest);
    });
  }

  void _runAutonomousBehavior(CharacterManifest manifest) {
    if (_strength < 24 && manifest.actions.containsKey("sleep")) {
      _playAction(manifest, "sleep",
          hold: _durationForAction(manifest, "sleep"));
      _showBubble("有点困了...");
      return;
    }
    if (_feeling < 35 &&
        manifest.actions.containsKey("move") &&
        _rng.nextDouble() < 0.7) {
      _playAction(manifest, "move", hold: _durationForAction(manifest, "move"));
      _showBubble("想活动一下");
      return;
    }
    if (_rng.nextDouble() < 0.08 && manifest.actions.containsKey("move")) {
      _playAction(manifest, "move", hold: _durationForAction(manifest, "move"));
      return;
    }
    _playAction(manifest, "default");
  }

  Duration _durationForAction(CharacterManifest manifest, String action) {
    final config = manifest.config;
    switch (action) {
      case "sleep":
        return Duration(seconds: config.duration("sleep", fallback: 10));
      case "move":
        return Duration(seconds: config.duration("state", fallback: 4));
      case "default":
      default:
        return Duration(seconds: config.duration("boring", fallback: 6));
    }
  }

  void _showBubble(String text) {
    _bubbleTimer?.cancel();
    setState(() {
      _bubbleText = text;
    });
    _bubbleTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _bubbleText = null;
      });
    });
  }

  void _showDialogueBox({
    required String title,
    required String lineA,
    required String lineB,
  }) {
    _dialogTimer?.cancel();
    setState(() {
      _dialogTitle = title;
      _dialogLineA = lineA;
      _dialogLineB = lineB;
    });
    _dialogTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      setState(() {
        _dialogTitle = null;
        _dialogLineA = null;
        _dialogLineB = null;
      });
    });
  }

  void _playAction(
    CharacterManifest manifest,
    String action, {
    Duration? hold,
  }) {
    if (!manifest.actions.containsKey(action)) return;
    _actionResetTimer?.cancel();
    setState(() {
      _action = action;
    });
    if (action != "default") {
      _actionResetTimer = Timer(
        hold ?? _durationForAction(manifest, action),
        () {
          if (!mounted) return;
          setState(() {
            _action = "default";
          });
        },
      );
    }
  }

  void _onZoneTapped(CharacterManifest manifest, String? zone) {
    _lastInteraction = DateTime.now();
    setState(() {
      _feeling = (_feeling + 3).clamp(0, 100);
    });
    switch (zone) {
      case "head":
        _showBubble("摸摸头");
        setState(() {
          _feeling = (_feeling + 8).clamp(0, 100);
        });
        _playAction(manifest, "move", hold: const Duration(seconds: 3));
        return;
      case "body":
        _showBubble("贴贴");
        _playAction(manifest, "sleep", hold: const Duration(seconds: 8));
        return;
      case "pinch":
        _showBubble("别捏啦");
        _playAction(manifest, "move", hold: const Duration(seconds: 2));
        return;
      default:
        _playAction(manifest, "default");
    }
  }

  Future<void> _startWindowDrag() async {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }
    try {
      await _windowChannel.invokeMethod<void>("startDrag");
      await _refreshWindowMetrics();
    } catch (_) {}
  }

  Future<void> _quitApp() async {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }
    try {
      await _windowChannel.invokeMethod<void>("quitApp");
    } catch (_) {}
  }

  Future<void> _moveWindowBy(double dx, double dy) async {
    if (defaultTargetPlatform != TargetPlatform.macOS) return;
    try {
      await _windowChannel.invokeMethod<void>("moveWindowBy", {
        "dx": dx,
        "dy": dy,
      });
    } catch (_) {}
  }

  Future<void> _refreshWindowMetrics() async {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }
    try {
      final metrics = await _windowChannel
          .invokeMapMethod<String, dynamic>("windowMetrics");
      if (metrics == null || !mounted) return;
      setState(() {
        _windowX = (metrics["x"] as num?)?.toDouble() ?? _windowX;
        _windowY = (metrics["y"] as num?)?.toDouble() ?? _windowY;
        _windowW = (metrics["width"] as num?)?.toDouble() ?? _windowW;
        _windowH = (metrics["height"] as num?)?.toDouble() ?? _windowH;
        _screenMinX =
            (metrics["screenMinX"] as num?)?.toDouble() ?? _screenMinX;
        _screenMinY =
            (metrics["screenMinY"] as num?)?.toDouble() ?? _screenMinY;
        _screenMaxX =
            (metrics["screenMaxX"] as num?)?.toDouble() ?? _screenMaxX;
        _screenMaxY =
            (metrics["screenMaxY"] as num?)?.toDouble() ?? _screenMaxY;
        _windowMetricsReady = true;
      });
      final idx = await _windowChannel.invokeMethod<int>("windowIndex");
      if (!mounted) return;
      final newCharacterId = (idx ?? 0) == 1 ? "lu" : "mu";
      setState(() {
        _windowIndex = idx ?? 0;
        if (_characterId != newCharacterId) {
          _characterId = newCharacterId;
          _manifestFuture = CharacterManifest.loadForCharacter(_characterId);
          _runtimeStarted = false;
        }
      });
      if ((idx ?? 0) == 0) {
        await _windowChannel.invokeMethod<void>("ensureSecondWindow");
      }
    } catch (_) {}
  }

  Future<void> _showPetMenuAt(Offset globalPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      color: const Color(0xFF121521),
      items: [
        const PopupMenuItem<String>(
          value: "chat",
          child: Text("AI对话"),
        ),
        const PopupMenuItem<String>(
          value: "schedule",
          child: Text("安排日程"),
        ),
        const PopupMenuItem<String>(
          value: "interactPeer",
          child: Text("和另一只互动"),
        ),
        PopupMenuItem<String>(
          value: "toggleZones",
          child: Text(_showDebugZones ? "隐藏触摸区" : "显示触摸区"),
        ),
        const PopupMenuItem<String>(
          value: "quit",
          child: Text("退出"),
        ),
      ],
    );
    if (!mounted || selected == null) return;
    if (selected == "chat") {
      await _openAiChatDialog();
    } else if (selected == "schedule") {
      await _openScheduleDialog();
    } else if (selected == "interactPeer") {
      await _triggerPeerInteraction();
    } else if (selected == "toggleZones") {
      setState(() {
        _showDebugZones = !_showDebugZones;
      });
    } else if (selected == "quit") {
      await _quitApp();
    }
  }

  Future<void> _openAiChatDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AiChatDialog(
        knowledgeBase: _knowledgeBase,
        aiService: _aiService,
      ),
    );
  }

  Future<void> _openScheduleDialog() async {
    final updated = await showDialog<List<ScheduleEntry>>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ScheduleBoardDialog(initial: _scheduleEntries),
    );
    if (updated == null || !mounted) return;
    await _scheduleRepository.save(updated);
    setState(() {
      _scheduleEntries = updated;
    });
  }

  Future<void> _triggerPeerInteraction() async {
    _showBubble("我：嗨！");
    final manifest = await _manifestFuture;
    if (!mounted) return;
    _playAction(manifest, "move", hold: const Duration(seconds: 2));
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }
    try {
      await _windowChannel.invokeMethod<void>("broadcastInteraction", {
        "type": "greet",
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: FutureBuilder<CharacterManifest>(
        future: _manifestFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final manifest = snapshot.data!;
          _ensureRuntime(manifest);
          if (!_windowMetricsReady &&
              defaultTargetPlatform == TargetPlatform.macOS) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _refreshWindowMetrics();
            });
          }
          return Stack(
            children: [
              if (_bubbleText != null)
                Positioned(
                  left: 84,
                  top: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(_bubbleText!,
                        style: const TextStyle(fontSize: 13)),
                  ),
                ),
              if (_dialogTitle != null &&
                  _dialogLineA != null &&
                  _dialogLineB != null)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white30),
                    ),
                    child: DefaultTextStyle(
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _dialogTitle!,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text("Mu-1: ${_dialogLineA!}"),
                          Text("Mu-2: ${_dialogLineB!}"),
                        ],
                      ),
                    ),
                  ),
                ),
              Center(
                child: PetActor(
                  manifest: manifest,
                  action: _action,
                  showTouchZones: _showDebugZones,
                  onTapZone: (zone) => _onZoneTapped(manifest, zone),
                  onPanStart: _startWindowDrag,
                  onTapUp: (details) => _showPetMenuAt(details.globalPosition),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class PetActor extends StatefulWidget {
  const PetActor({
    super.key,
    required this.manifest,
    required this.action,
    required this.showTouchZones,
    required this.onTapZone,
    required this.onPanStart,
    required this.onTapUp,
  });

  final CharacterManifest manifest;
  final String action;
  final bool showTouchZones;
  final ValueChanged<String?> onTapZone;
  final VoidCallback onPanStart;
  final ValueChanged<TapUpDetails> onTapUp;

  @override
  State<PetActor> createState() => _PetActorState();
}

class _PetActorState extends State<PetActor> {
  static const _size = 260.0;
  final _rng = Random();

  int _frameIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleNextFrame();
  }

  @override
  void didUpdateWidget(covariant PetActor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.action != widget.action) {
      _frameIndex = 0;
      _scheduleNextFrame();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<FrameData> get _frames =>
      widget.manifest.actions[widget.action] ??
      widget.manifest.actions["default"] ??
      const [];

  void _scheduleNextFrame() {
    _timer?.cancel();
    if (_frames.isEmpty) return;
    final frame = _frames[_frameIndex % _frames.length];
    var durationMs = frame.durationMs;
    if (widget.action == "default" && _frames.length == 2) {
      if (_frameIndex == 0) {
        durationMs = 2000 + _rng.nextInt(1000);
      } else {
        durationMs = 35 + _rng.nextInt(25);
      }
    } else if (widget.action == "sleep") {
      durationMs = (durationMs * 4.5).round() + _rng.nextInt(240);
    } else if (widget.action == "default") {
      durationMs = (durationMs * 3.0).round();
    }
    _timer = Timer(Duration(milliseconds: durationMs), () {
      if (!mounted || _frames.isEmpty) return;
      setState(() {
        if (widget.action == "default" && _frames.length == 2) {
          _frameIndex = _frameIndex == 0 ? 1 : 0;
        } else {
          _frameIndex = (_frameIndex + 1) % _frames.length;
        }
      });
      _scheduleNextFrame();
    });
  }

  void _handleTapDown(TapDownDetails details) {
    final zone = widget.manifest.config.touchZones.hitTest(
      details.localPosition,
      _size,
      _size,
    );
    widget.onTapZone(zone);
  }

  @override
  Widget build(BuildContext context) {
    final frame =
        _frames.isNotEmpty ? _frames[_frameIndex % _frames.length] : null;
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: widget.onTapUp,
      onPanStart: (_) => widget.onPanStart(),
      child: SizedBox(
        width: _size,
        height: _size,
        child: Stack(
          children: [
            Positioned.fill(
              child: frame == null
                  ? const Center(
                      child: Text(
                        "No Frames",
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : Image.asset(
                      frame.asset,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.low,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Text(
                            "Frame Load Error",
                            style: TextStyle(color: Colors.white54),
                          ),
                        );
                      },
                    ),
            ),
            if (widget.showTouchZones)
              ...widget.manifest.config.touchZones
                  .buildDebugRects(_size, _size),
          ],
        ),
      ),
    );
  }
}

class CharacterManifest {
  const CharacterManifest({required this.actions, required this.config});

  final Map<String, List<FrameData>> actions;
  final MuConfig config;

  static Future<CharacterManifest> loadForCharacter(String characterId) async {
    final assetPath =
        characterId == "lu" ? "lu/manifest.json" : "assets/mu/manifest.json";
    final raw = await rootBundle.loadString(assetPath);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final characters = data["characters"] as Map<String, dynamic>;
    final character = (characters[characterId] ?? characters.values.first)
        as Map<String, dynamic>;
    final config = MuConfig.fromJson(
      character["config"] as Map<String, dynamic>? ?? const {},
    );
    final rawActions = character["actions"] as Map<String, dynamic>;
    final actions = <String, List<FrameData>>{};
    for (final entry in rawActions.entries) {
      final list = (entry.value as List<dynamic>)
          .map((e) => FrameData.fromJson(e as Map<String, dynamic>))
          .toList();
      actions[entry.key] = list;
    }
    return CharacterManifest(actions: actions, config: config);
  }
}

class FrameData {
  const FrameData({required this.asset, required this.durationMs});

  final String asset;
  final int durationMs;

  factory FrameData.fromJson(Map<String, dynamic> json) {
    return FrameData(
      asset: json["asset"] as String,
      durationMs: (json["durationMs"] as num).toInt(),
    );
  }
}

class MuConfig {
  const MuConfig({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.touchZones,
    required this.durations,
    required this.moveGraphs,
  });

  final double canvasWidth;
  final double canvasHeight;
  final TouchZones touchZones;
  final Map<String, int> durations;
  final List<String> moveGraphs;

  int duration(String key, {required int fallback}) {
    return durations[key] ?? fallback;
  }

  factory MuConfig.fromJson(Map<String, dynamic> json) {
    final canvas = (json["canvasSize"] as Map<String, dynamic>? ?? const {});
    final rawDurations =
        (json["duration"] as Map<String, dynamic>? ?? const {});
    final durationMap = <String, int>{};
    for (final entry in rawDurations.entries) {
      durationMap[entry.key] = int.tryParse("${entry.value}") ?? 0;
    }
    final rawMoveGraphs = (json["moveGraphs"] as List<dynamic>? ?? const []);
    return MuConfig(
      canvasWidth: (canvas["width"] as num?)?.toDouble() ?? 500,
      canvasHeight: (canvas["height"] as num?)?.toDouble() ?? 500,
      touchZones: TouchZones.fromJson(
        json["touchZones"] as Map<String, dynamic>? ?? const {},
      ),
      durations: durationMap,
      moveGraphs: rawMoveGraphs.map((e) => "$e").toList(),
    );
  }
}

class TouchZones {
  const TouchZones(this.zones);

  final Map<String, RectSpec> zones;

  factory TouchZones.fromJson(Map<String, dynamic> json) {
    final map = <String, RectSpec>{};
    for (final entry in json.entries) {
      map[entry.key] = RectSpec.fromJson(entry.value as Map<String, dynamic>);
    }
    return TouchZones(map);
  }

  String? hitTest(Offset local, double widgetW, double widgetH) {
    for (final entry in zones.entries) {
      if (entry.value.toWidgetRect(widgetW, widgetH).contains(local)) {
        return entry.key;
      }
    }
    return null;
  }

  List<Widget> buildDebugRects(double widgetW, double widgetH) {
    final colors = {
      "head": Colors.blueAccent.withValues(alpha: 0.14),
      "body": Colors.greenAccent.withValues(alpha: 0.14),
      "pinch": Colors.orangeAccent.withValues(alpha: 0.14),
    };
    return zones.entries.map((entry) {
      final rect = entry.value.toWidgetRect(widgetW, widgetH);
      return Positioned(
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
        child: IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              color: colors[entry.key] ?? Colors.white10,
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      );
    }).toList();
  }
}

class RectSpec {
  const RectSpec({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final double x;
  final double y;
  final double w;
  final double h;

  factory RectSpec.fromJson(Map<String, dynamic> json) {
    return RectSpec(
      x: (json["x"] as num?)?.toDouble() ?? 0,
      y: (json["y"] as num?)?.toDouble() ?? 0,
      w: (json["w"] as num?)?.toDouble() ?? 0,
      h: (json["h"] as num?)?.toDouble() ?? 0,
    );
  }

  Rect toWidgetRect(double widgetW, double widgetH) {
    const sourceW = 500.0;
    const sourceH = 500.0;
    final sx = widgetW / sourceW;
    final sy = widgetH / sourceH;
    return Rect.fromLTWH(x * sx, y * sy, w * sx, h * sy);
  }
}

class AiChatDialog extends StatefulWidget {
  const AiChatDialog({
    super.key,
    required this.knowledgeBase,
    required this.aiService,
  });

  final PetKnowledgeBase knowledgeBase;
  final PetAiService aiService;

  @override
  State<AiChatDialog> createState() => _AiChatDialogState();
}

class _AiChatDialogState extends State<AiChatDialog> {
  final TextEditingController _inputController = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _sending = false;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;
    _inputController.clear();
    setState(() {
      _messages.add(ChatMessage(role: "user", content: text));
      _sending = true;
    });
    final snippets = await widget.knowledgeBase.search(text, limit: 3);
    final reply = await widget.aiService.reply(
      userText: text,
      knowledgeSnippets: snippets,
    );
    if (!mounted) return;
    setState(() {
      _messages.add(ChatMessage(role: "assistant", content: reply));
      _sending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF141826),
      child: SizedBox(
        width: 420,
        height: 460,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              const Row(
                children: [
                  Text(
                    "VPet AI 对话",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isUser = msg.role == "user";
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          constraints: const BoxConstraints(maxWidth: 320),
                          decoration: BoxDecoration(
                            color: isUser
                                ? const Color(0xFF2B4C7E)
                                : Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(msg.content),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: "输入你的问题...",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sending ? null : _send,
                    child: Text(_sending ? "发送中" : "发送"),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                "提示: 配置 OPENAI_API_KEY 后将启用在线回复，否则使用本地知识库回复。",
                style: TextStyle(fontSize: 11, color: Colors.white60),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatMessage {
  const ChatMessage({required this.role, required this.content});

  final String role;
  final String content;
}

class ScheduleEntry {
  const ScheduleEntry({
    required this.id,
    required this.title,
    required this.startMinuteOfDay,
    required this.endMinuteOfDay,
    required this.topics,
    required this.actions,
  });

  final String id;
  final String title;
  final int startMinuteOfDay;
  final int endMinuteOfDay;
  final List<String> topics;
  final List<String> actions;

  bool isActiveAt(DateTime time) {
    final minute = time.hour * 60 + time.minute;
    if (startMinuteOfDay <= endMinuteOfDay) {
      return minute >= startMinuteOfDay && minute <= endMinuteOfDay;
    }
    return minute >= startMinuteOfDay || minute <= endMinuteOfDay;
  }

  String formatRange() {
    String fmt(int m) =>
        "${(m ~/ 60).toString().padLeft(2, "0")}:${(m % 60).toString().padLeft(2, "0")}";
    return "${fmt(startMinuteOfDay)}-${fmt(endMinuteOfDay)}";
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "title": title,
      "startMinuteOfDay": startMinuteOfDay,
      "endMinuteOfDay": endMinuteOfDay,
      "topics": topics,
      "actions": actions,
    };
  }

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) {
    return ScheduleEntry(
      id: (json["id"] as String? ?? "").trim(),
      title: (json["title"] as String? ?? "未命名日程").trim(),
      startMinuteOfDay: (json["startMinuteOfDay"] as num?)?.toInt() ?? 0,
      endMinuteOfDay: (json["endMinuteOfDay"] as num?)?.toInt() ?? 0,
      topics: ((json["topics"] as List<dynamic>? ?? const []).map((e) => "$e"))
          .toList(),
      actions: ((json["actions"] as List<dynamic>? ?? const [])
          .map((e) => "$e")).toList(),
    );
  }
}

class ScheduleRepository {
  static const _fileName = "vpet_schedule_entries_v1.json";

  Future<File> _file() async {
    final home = Platform.environment["HOME"] ?? Directory.current.path;
    final dir = Directory("$home/Library/Application Support/vpet_flutter");
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File("${dir.path}/$_fileName");
  }

  Future<List<ScheduleEntry>> load() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    final raw = await file.readAsString();
    if (raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => ScheduleEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<ScheduleEntry> entries) async {
    final file = await _file();
    final raw = jsonEncode(entries.map((e) => e.toJson()).toList());
    await file.writeAsString(raw, flush: true);
  }
}

class ScheduleDialoguePair {
  const ScheduleDialoguePair({required this.a, required this.b});

  final String a;
  final String b;
}

class ScheduleDialogueSimulator {
  const ScheduleDialogueSimulator({
    required this.knowledgeBase,
    required this.aiService,
  });

  final PetKnowledgeBase knowledgeBase;
  final PetAiService aiService;

  Future<ScheduleDialoguePair> generate(ScheduleEntry entry) async {
    final topic = entry.topics.isEmpty ? "日常" : entry.topics.first;
    final snippets = await knowledgeBase.search("性格 $topic", limit: 3);
    final apiKey = Platform.environment["OPENAI_API_KEY"] ?? "";
    if (apiKey.isNotEmpty) {
      final prompt = "根据以下知识库，模拟两只桌宠在日程“${entry.title}”里的简短对话。"
          "输出严格 JSON: {\"a\":\"...\",\"b\":\"...\"}，每句不超过20字。\n\n知识库:\n${snippets.join("\n")}";
      final content =
          await aiService.reply(userText: prompt, knowledgeSnippets: snippets);
      final pair = _tryParsePair(content);
      if (pair != null) return pair;
    }
    final a = "到 ${entry.title} 时间了，先做 $topic。";
    const b = "收到，我会按计划执行。";
    return ScheduleDialoguePair(a: a, b: b);
  }

  ScheduleDialoguePair? _tryParsePair(String text) {
    final start = text.indexOf("{");
    final end = text.lastIndexOf("}");
    if (start < 0 || end <= start) return null;
    try {
      final data =
          jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
      final a = (data["a"] as String? ?? "").trim();
      final b = (data["b"] as String? ?? "").trim();
      if (a.isEmpty || b.isEmpty) return null;
      return ScheduleDialoguePair(a: a, b: b);
    } catch (_) {
      return null;
    }
  }
}

class ScheduleBoardDialog extends StatefulWidget {
  const ScheduleBoardDialog({super.key, required this.initial});

  final List<ScheduleEntry> initial;

  @override
  State<ScheduleBoardDialog> createState() => _ScheduleBoardDialogState();
}

class _ScheduleBoardDialogState extends State<ScheduleBoardDialog> {
  late final List<ScheduleEntry> _entries = [...widget.initial];

  Future<void> _addEntry() async {
    final entry = await showDialog<ScheduleEntry>(
      context: context,
      builder: (_) => const AddScheduleEntryDialog(),
    );
    if (entry == null) return;
    setState(() {
      _entries.add(entry);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF141826),
      child: SizedBox(
        width: 520,
        height: 500,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              const Row(
                children: [
                  Text(
                    "日程表",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _entries.isEmpty
                    ? const Center(
                        child: Text("暂无日程，点击“新增”添加。"),
                      )
                    : ListView.builder(
                        itemCount: _entries.length,
                        itemBuilder: (context, index) {
                          final entry = _entries[index];
                          return ListTile(
                            dense: true,
                            title: Text(entry.title),
                            subtitle: Text(
                              "${entry.formatRange()} | 话题: ${entry.topics.join(" / ")} | 动作: ${entry.actions.join(", ")}",
                            ),
                            trailing: IconButton(
                              onPressed: () {
                                setState(() {
                                  _entries.removeAt(index);
                                });
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _addEntry,
                    icon: const Icon(Icons.add),
                    label: const Text("新增"),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("取消"),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_entries),
                    child: const Text("保存"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AddScheduleEntryDialog extends StatefulWidget {
  const AddScheduleEntryDialog({super.key});

  @override
  State<AddScheduleEntryDialog> createState() => _AddScheduleEntryDialogState();
}

class _AddScheduleEntryDialogState extends State<AddScheduleEntryDialog> {
  final _titleController = TextEditingController();
  final _startController = TextEditingController(text: "09:00");
  final _endController = TextEditingController(text: "10:00");
  final _topicController = TextEditingController(text: "散步,问候");
  final _actionController =
      TextEditingController(text: "move,sleep,reserved_chat");

  @override
  void dispose() {
    _titleController.dispose();
    _startController.dispose();
    _endController.dispose();
    _topicController.dispose();
    _actionController.dispose();
    super.dispose();
  }

  int? _parseMinute(String text) {
    final m = RegExp(r"^(\d{1,2}):(\d{1,2})$").firstMatch(text.trim());
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!);
    final min = int.tryParse(m.group(2)!);
    if (h == null || min == null) return null;
    if (h < 0 || h > 23 || min < 0 || min > 59) return null;
    return h * 60 + min;
  }

  void _submit() {
    final title = _titleController.text.trim().isEmpty
        ? "未命名日程"
        : _titleController.text.trim();
    final start = _parseMinute(_startController.text);
    final end = _parseMinute(_endController.text);
    if (start == null || end == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("时间格式错误，请用 HH:mm")),
      );
      return;
    }
    final topics = _topicController.text
        .split(RegExp(r"[，,]+"))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final actions = _actionController.text
        .split(RegExp(r"[，,]+"))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    Navigator.of(context).pop(
      ScheduleEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        startMinuteOfDay: start,
        endMinuteOfDay: end,
        topics: topics.isEmpty ? const ["日常"] : topics,
        actions: actions.isEmpty ? const ["move"] : actions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF141826),
      child: SizedBox(
        width: 420,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "新增日程",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: "日程名称",
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _startController,
                      decoration: const InputDecoration(
                        labelText: "开始(HH:mm)",
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _endController,
                      decoration: const InputDecoration(
                        labelText: "结束(HH:mm)",
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _topicController,
                decoration: const InputDecoration(
                  labelText: "话题(逗号分隔)",
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _actionController,
                decoration: const InputDecoration(
                  labelText: "动作(逗号分隔，支持预留动作名)",
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("取消"),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _submit,
                    child: const Text("添加"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PetKnowledgeBase {
  String? _doc;

  Future<String> _loadDoc() async {
    if (_doc != null) return _doc!;
    _doc = await rootBundle.loadString("assets/knowledge/base.md");
    return _doc!;
  }

  Future<List<String>> search(String query, {int limit = 3}) async {
    final doc = await _loadDoc();
    final blocks = doc
        .split(RegExp(r"\n\s*\n"))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final memoryMode = _isMemoryQuery(query);
    final keys = query
        .toLowerCase()
        .split(RegExp(r"[\s，。！？,.!?;；:：]+"))
        .where((e) => e.isNotEmpty)
        .toSet();
    final scored = <({String text, int score})>[];
    for (final block in blocks) {
      final low = block.toLowerCase();
      final isTimeline = _isTimelineBlock(block);
      var score = 0;
      for (final k in keys) {
        if (low.contains(k)) {
          score += 1;
        }
      }
      if (isTimeline && !memoryMode) {
        score -= 2;
      }
      if (isTimeline && memoryMode) {
        score += 3;
      }
      if (score > 0) {
        final text = isTimeline && memoryMode
            ? _extractTimelineMatches(block, keys)
            : block;
        scored.add((text: text, score: score));
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((e) => e.text).toList();
  }

  bool _isTimelineBlock(String block) {
    final low = block.toLowerCase();
    return low.contains("时间线") ||
        block.contains("✅") ||
        RegExp(r"20\d{2}").hasMatch(block);
  }

  bool _isMemoryQuery(String query) {
    final low = query.toLowerCase();
    const keys = [
      "时间线",
      "回忆",
      "过往",
      "以前",
      "当时",
      "哪年",
      "哪天",
      "什么时候",
      "历史",
      "事件",
      "记得",
      "timeline",
      "history",
      "memory",
    ];
    if (keys.any(low.contains)) return true;
    return RegExp(r"20\d{2}").hasMatch(low);
  }

  String _extractTimelineMatches(String block, Set<String> keys) {
    final lines =
        block.split("\n").map((e) => e.trim()).where((e) => e.isNotEmpty);
    final matched = <String>[];
    for (final line in lines) {
      final low = line.toLowerCase();
      if (keys.any((k) => low.contains(k))) {
        matched.add(line);
      }
    }
    if (matched.isEmpty) {
      return lines.take(6).join("\n");
    }
    return matched.take(8).join("\n");
  }
}

class PetAiService {
  Future<String> reply({
    required String userText,
    required List<String> knowledgeSnippets,
  }) async {
    final contextText = knowledgeSnippets.isEmpty
        ? "无匹配知识片段。"
        : knowledgeSnippets.join("\n\n---\n\n");
    final apiKey = Platform.environment["OPENAI_API_KEY"] ?? "";
    if (apiKey.isEmpty) {
      if (knowledgeSnippets.isEmpty) {
        return "我暂时没在本地知识库找到相关内容。你可以先补充知识库文档。";
      }
      return "我先基于本地知识库回答:\n\n$contextText";
    }

    final baseUrl =
        Platform.environment["OPENAI_BASE_URL"] ?? "https://api.openai.com/v1";
    final model = Platform.environment["OPENAI_MODEL"] ?? "gpt-4o-mini";
    final uri = Uri.parse("$baseUrl/chat/completions");
    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      req.headers.set(HttpHeaders.authorizationHeader, "Bearer $apiKey");
      req.headers.set(HttpHeaders.contentTypeHeader, "application/json");
      final body = jsonEncode({
        "model": model,
        "temperature": 0.5,
        "messages": [
          {"role": "system", "content": "你是桌宠助手。优先使用提供的知识库内容，回答简洁、可执行。"},
          {
            "role": "user",
            "content": "知识库:\n$contextText\n\n用户问题:\n$userText",
          },
        ],
      });
      req.add(utf8.encode(body));
      final resp = await req.close();
      final text = await utf8.decoder.bind(resp).join();
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return "AI 请求失败(${resp.statusCode})，已回退本地知识库:\n$contextText";
      }
      final data = jsonDecode(text) as Map<String, dynamic>;
      final choices = data["choices"] as List<dynamic>? ?? const [];
      if (choices.isEmpty) {
        return "AI 返回为空，已回退本地知识库:\n$contextText";
      }
      final message =
          choices.first["message"] as Map<String, dynamic>? ?? const {};
      final content = (message["content"] as String? ?? "").trim();
      if (content.isEmpty) {
        return "AI 返回为空文本，已回退本地知识库:\n$contextText";
      }
      return content;
    } catch (_) {
      return "AI 请求异常，已回退本地知识库:\n$contextText";
    } finally {
      client.close(force: true);
    }
  }
}
