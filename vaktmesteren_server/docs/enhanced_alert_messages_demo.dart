/// Example demonstration of the enhanced log messages
void main() {
  print('=== Enhanced Service Alert Messages ===\n');

  // Example log outputs with service names included
  print('Before (without service name and hostname):');
  print('[19.09.2025, 13:31:04] CRITICAL: Service has entered critical state');
  print('[19.09.2025, 13:35:12] RECOVERY: Service has recovered');

  print('\nAfter (with service name and hostname):');
  print(
      '[19.09.2025, 13:31:04] CRITICAL: Service nginx on web01.example.com has entered critical state');
  print(
      '[19.09.2025, 13:35:12] RECOVERY: Service nginx on web01.example.com has recovered');

  print('\nFixed redundancy issue:');
  print(
      '❌ Before fix: RECOVERY: Service ser2net on ghrunner.grsoft.no has recovered for ghrunner.grsoft.no!ser2net');
  print(
      '✅ After fix:  RECOVERY: Service ser2net on ghrunner.grsoft.no has recovered');

  print('\nMore examples:');
  print(
      '[19.09.2025, 14:22:33] CRITICAL: Service postgresql on db01.example.com has entered critical state');
  print(
      '[19.09.2025, 14:25:45] RECOVERY: Service postgresql on db01.example.com has recovered');
  print(
      '[19.09.2025, 15:10:18] CRITICAL: Service redis on cache01.example.com has entered critical state');

  print('\nFor host-only checks (service = null):');
  print(
      '[19.09.2025, 15:15:22] CRITICAL: Service Unknown on host01.example.com has entered critical state');

  print('\n=== Key Benefits ===');
  print('✅ Service name and hostname now clearly visible in logs');
  print('✅ Easier troubleshooting and monitoring');
  print('✅ Better correlation with specific services and hosts');
  print('✅ Consistent formatting for all alert types');
  print('✅ Full context for incident response');
}
