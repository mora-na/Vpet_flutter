import "dart:async";
import "dart:convert";
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
  late final Future<CharacterManifest> _manifestFuture =
      CharacterManifest.load();

  Timer? _statusTimer;
  Timer? _behaviorTimer;
  Timer? _actionResetTimer;
  Timer? _bubbleTimer;
  Timer? _movementTimer;

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

  @override
  void dispose() {
    _statusTimer?.cancel();
    _behaviorTimer?.cancel();
    _actionResetTimer?.cancel();
    _bubbleTimer?.cancel();
    _movementTimer?.cancel();
    super.dispose();
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
    if (_rng.nextDouble() < 0.2 && manifest.actions.containsKey("move")) {
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
    if (selected == "toggleZones") {
      setState(() {
        _showDebugZones = !_showDebugZones;
      });
    } else if (selected == "quit") {
      await _quitApp();
    }
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
        durationMs = 4200 + _rng.nextInt(2800);
      } else {
        durationMs = 180 + _rng.nextInt(120);
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

  static Future<CharacterManifest> load() async {
    final raw = await rootBundle.loadString("assets/mu/manifest.json");
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final character = (data["characters"] as Map<String, dynamic>)["mu"]
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
