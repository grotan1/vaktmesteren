#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

/// Simple script to send a test HTTP request to trigger a manual test
void main(List<String> args) async {
  print('🧪 Testing SSH Restart Integration');
  print('Sending test request to running server...');

  try {
    // Try to access the log viewer to see if server is responsive
    final client = HttpClient();
    final request =
        await client.getUrl(Uri.parse('http://localhost:8082/logs'));
    final response = await request.close();

    if (response.statusCode == 200) {
      print('✅ Server is responding on port 8082');
      print('🌐 You can view logs at: http://localhost:8082/logs');
      print('');
      print('💡 To test the SSH restart system:');
      print('1. Open the log viewer: http://localhost:8082/logs');
      print('2. Look for SSH restart system initialization messages');
      print('3. Wait for Icinga2 to connect and process events');
      print(
          '4. When a CRITICAL alert occurs for CheckSystemd-Linux, watch for:');
      print('   - "🔍 No restart rules found" OR');
      print(
          '   - "🔄 Triggering restart: github-runner on ghrunner.grsoft.no"');
      print('   - SSH command simulation logs');
      print('');
    } else {
      print('❌ Server responded with status: ${response.statusCode}');
    }

    client.close();
  } catch (e) {
    print('❌ Could not connect to server: $e');
    print('Make sure the server is running with: dart run bin/main.dart');
  }
}
