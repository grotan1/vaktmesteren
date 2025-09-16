import 'package:serverpod/serverpod.dart';

/// A widget that displays the real-time log viewer.
/// It uses the log_viewer.html template to render the page.
class LogViewerPage extends Widget {
  LogViewerPage() : super(name: 'log_viewer') {
    values = {
      'title': 'Vaktmesteren - Real-time Log Viewer',
    };
  }
}
