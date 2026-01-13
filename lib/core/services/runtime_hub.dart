import 'control_agent.dart';
import 'event_bus.dart';
import 'live3d_bridge.dart';
import 'tool_router.dart';

/// Aggregates runtime-wide services (event bus, control agent, tool router,
/// and Live3D bridge). This is a light-weight locator for future wiring.
class RuntimeHub {
  RuntimeHub._internal()
      : bus = RuntimeEventBus(),
        toolRouter = const ToolRouter() {
    controlAgent = ControlAgent(
      bus: bus,
      toolRouter: toolRouter,
    );
    live3dBridge = Live3DBridge(bus);
  }

  static final RuntimeHub instance = RuntimeHub._internal();

  final RuntimeEventBus bus;
  final ToolRouter toolRouter;
  late final ControlAgent controlAgent;
  late final Live3DBridge live3dBridge;

  Future<void> dispose() async {
    await live3dBridge.dispose();
    await bus.dispose();
  }
}
