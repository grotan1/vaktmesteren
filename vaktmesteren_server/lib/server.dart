import 'dart:io';
import 'package:serverpod/serverpod.dart';

import 'package:vaktmesteren_server/src/web/routes/root.dart';
import 'package:vaktmesteren_server/src/web/routes/log_viewer.dart';
import 'package:vaktmesteren_server/src/web/routes/alert_history.dart';
import 'package:vaktmesteren_server/src/web/routes/portainer_ops.dart';

import 'src/generated/protocol.dart';
import 'src/generated/endpoints.dart';
import 'src/icinga2_alert_service.dart';

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
  // Also register the trailing-slash variant so browsers that request '/logs/'
  // don't receive a 404.
  pod.webServer.addRoute(RouteLogViewer(), '/logs/');
  // SSE stream removed; use WebSocket route instead for realtime logs
  pod.webServer.addRoute(RouteLogWebSocket(), '/logs/ws');
  pod.webServer.addRoute(RouteLogPoll(), '/logs/poll');
  pod.webServer.addRoute(RouteLogTest(), '/logs/test');

  // Alert history viewer
  pod.webServer.addRoute(RouteAlertHistoryPage(), '/alerts/history');
  pod.webServer.addRoute(RouteAlertHistoryJson(), '/alerts/history');

  // Internal-only Portainer ops route. Registered under a path that avoids
  // Serverpod's automatic endpoint dispatch for top-level endpoint names.
  // This route is restricted to private addresses by the route
  // implementation and therefore intended for internal use only.
  pod.webServer.addRoute(
    RoutePortainerOpsCheckService(),
    '/_internal/ops/portainer/check-service',
  );
  // Also register a trailing-slash variant.
  pod.webServer.addRoute(
    RoutePortainerOpsCheckService(),
    '/_internal/ops/portainer/check-service/',
  );

  // Serve all files in the /static directory.
  pod.webServer.addRoute(
    RouteStaticDirectory(serverDirectory: 'static', basePath: '/'),
    '/*',
  );

  // Start the server.
  await pod.start();

  // Initialize simple Icinga2 alert service
  print('DEBUG: About to initialize Icinga2AlertService');
  try {
    // Create a session for the alert service
    print('DEBUG: Creating session...');
    final session = await pod.createSession(enableLogging: false);
    print('DEBUG: Session created');
    session.log('Session created for Icinga2AlertService',
        level: LogLevel.info);

    // Load Icinga2 configuration
    print('DEBUG: Loading Icinga2 configuration...');
    final config = await Icinga2Config.loadFromConfig(session);
    print('DEBUG: Config loaded: ${config.host}:${config.port}');
    session.log('Icinga2 configuration loaded: ${config.host}:${config.port}',
        level: LogLevel.info);

    // Create and start the alert service
    print('DEBUG: Creating alert service...');
    final alertService = Icinga2AlertService(session, config);
    print('DEBUG: Starting alert service...');
    await alertService.start();
    print('DEBUG: Alert service started successfully');

    session.log('Icinga2AlertService started successfully',
        level: LogLevel.info);
  } catch (e, stackTrace) {
    print('DEBUG: Error occurred: $e');
    print('DEBUG: Stack trace: $stackTrace');
    // Log the error using Serverpod's logging system
    try {
      final errorSession = await pod.createSession(enableLogging: false);
      errorSession.log(
          'Failed to start Icinga2AlertService: $e\nStack trace: $stackTrace',
          level: LogLevel.error);
    } catch (logError) {
      // Fallback to stderr if session creation fails
      stderr.writeln('Failed to start Icinga2AlertService: $e');
      stderr.writeln('Stack trace: $stackTrace');
      stderr.writeln('Also failed to create session for logging: $logError');
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

// No startup token loading required — endpoints are open per operator request.
