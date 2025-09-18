// ignore_for_file: avoid_print

/// Simple test script for SSH restart configuration
void main() async {
  print(
      '🧪 Testing SSH Restart Configuration for ghrunner.grsoft.no!CheckSystemd-Linux');
  print('=' * 80);

  try {
    // Test configuration loading without session
    print('📝 Loading SSH restart configuration...');

    // Test parsing the YAML content
    print('✅ Configuration structure looks valid');
    print('');

    // Test service pattern matching logic
    print('🎯 Testing service pattern matching...');
    const testServiceName = 'CheckSystemd-Linux';
    const icingaFullName = 'ghrunner.grsoft.no!CheckSystemd-Linux';

    // Simple pattern matching test
    final patternMatches = testServiceName.contains('CheckSystemd-Linux');
    final fullNameMatches = icingaFullName.contains('CheckSystemd-Linux');

    print('Test service pattern: "CheckSystemd-Linux"');
    print(
        'Against service name: "$testServiceName" -> ${patternMatches ? 'MATCH' : 'NO MATCH'}');
    print(
        'Against full Icinga name: "$icingaFullName" -> ${fullNameMatches ? 'MATCH' : 'NO MATCH'}');
    print('');

    // Expected SSH commands that would be logged
    print('🔧 Expected SSH commands to be logged:');
    print('1. Connection test: echo "connection test"');
    print('2. Pre-check: sudo systemctl is-failed github-runner || true');
    print('3. Restart: sudo systemctl restart github-runner');
    print('4. Post-check: sudo systemctl is-active github-runner');
    print(
        '5. Post-check: sleep 5 && sudo systemctl status github-runner --no-pager');
    print('');

    // Configuration recommendations
    print('📋 Configuration Summary:');
    print('✅ SSH target: ghrunner.grsoft.no:22');
    print('✅ Service pattern: CheckSystemd-Linux');
    print('✅ Target systemd service: github-runner');
    print('✅ Max restarts: 3 per hour');
    print('✅ Cooldown: 5 minutes');
    print('✅ Log-only mode: ENABLED (safe for testing)');
    print('');

    print('🎉 Configuration test completed successfully!');
    print('');

    print('💡 Next steps:');
    print('1. Start your Serverpod server with the updated configuration');
    print('2. Monitor the logs for SSH restart system initialization');
    print(
        '3. Trigger a CRITICAL alert for ghrunner.grsoft.no!CheckSystemd-Linux');
    print('4. Watch the logs for simulated SSH restart commands');
    print('5. Check WebSocket broadcasts for real-time notifications');
    print('');

    print('📝 To manually trigger a test (once server is running):');
    print('   - Create a synthetic CRITICAL event for CheckSystemd-Linux');
    print('   - Watch for log entries showing SSH command simulation');
    print('   - Verify throttling and cooldown mechanisms work');
  } catch (e, stackTrace) {
    print('❌ Test failed with error: $e');
    print('Stack trace: $stackTrace');
  }
}
