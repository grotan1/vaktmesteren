import 'package:serverpod/serverpod.dart';

import 'package:vaktmesteren_server/src/web/routes/root.dart';
import 'package:vaktmesteren_server/src/web/routes/log_viewer.dart';

import 'src/generated/protocol.dart';
import 'src/generated/endpoints.dart';
import 'src/icinga2_event_listener.dart';

// This is the starting point of your Serverpod server. In most cases, you will
// only need to make additions to this file if you add future calls,  are
// configuring Relic (Serverpod's web-server), or need custom setup work.

void run(List<String> args) async {
  // Initialize Serverpod and connect it with your generated code.
  final pod = Serverpod(args, Protocol(), Endpoints());

  // Setup a default page at the web root.
  pod.webServer.addRoute(RouteRoot(), '/');
  pod.webServer.addRoute(RouteRoot(), '/index.html');

  // Setup log viewer routes
  pod.webServer.addRoute(RouteLogViewer(), '/logs');
  // SSE stream removed; use WebSocket route instead for realtime logs
  pod.webServer.addRoute(RouteLogWebSocket(), '/logs/ws');
  pod.webServer.addRoute(RouteLogPoll(), '/logs/poll');
  pod.webServer.addRoute(RouteLogTest(), '/logs/test');

  // Serve all files in the /static directory.
  pod.webServer.addRoute(
    RouteStaticDirectory(serverDirectory: 'static', basePath: '/'),
    '/*',
  );

  // Start the server.
  await pod.start();

  // Initialize Icinga2 event listener with proper session management
  try {
    print('Initializing Icinga2 event listener...');
    // Create a session for the event listener
    final session = await pod.createSession();
    print('Session created successfully');

    // Load Icinga2 configuration
    final config = await Icinga2Config.loadFromConfig(session);
    print('Configuration loaded: ${config.host}:${config.port}');

    // Create and start the event listener
    final eventListener = Icinga2EventListener(session, config);
    print('Event listener created, starting...');
    await eventListener.start();

    session.log('Icinga2 event listener started successfully',
        level: LogLevel.info);
    print('Icinga2 event listener started successfully');
  } catch (e) {
    // Log the error using Serverpod's logging system
    print('Failed to start Icinga2 event listener: $e');
    try {
      final errorSession = await pod.createSession();
      errorSession.log('Failed to start Icinga2 event listener: $e',
          level: LogLevel.error);
    } catch (logError) {
      // Fallback to print if session creation fails
      // ignore: avoid_print
      print('Failed to start Icinga2 event listener: $e');
      // ignore: avoid_print
      print('Also failed to create session for logging: $logError');
    }
  }

  // After starting the server, you can register future calls. Future calls are
  // tasks that need to happen in the future, or independently of the request/
  // response cycle. For example, you can use future calls to send emails, or to
  // schedule tasks to be executed at a later time. Future calls are executed in
  // the background. Their schedule is persisted to the database, so you will
  // not lose them if the server is restarted.

  // Future calls can be registered here during startup
  // Example: pod.registerFutureCall(MyFutureCall(), 'my-future-call');
}
