# Conditional SSH Restart Feature

## Overview
Added conditional SSH restart functionality to the Icinga2 alert service. SSH service restarts now only trigger when the `auto_restart_service_linux` service variable is explicitly set to `true` in Icinga2.

## Implementation Details

### Modified Files
- `lib/src/icinga2_alert_service.dart`: Enhanced `_triggerServiceRestart` method
- `test/icinga2_conditional_restart_test.dart`: New comprehensive unit tests

### Key Changes

1. **Enhanced `_triggerServiceRestart` Method**:
   - Now accepts an additional `event` parameter containing full Icinga2 event data
   - Extracts service variables from the event data
   - Checks for `auto_restart_service_linux` variable before proceeding with restart
   - Supports multiple data types (bool, string, int) for robust compatibility
   - Provides detailed logging for both enabled/disabled scenarios

2. **Robust Type Handling**:
   - `bool`: Direct boolean check (`true`/`false`)
   - `string`: Case-insensitive check for `"true"`
   - `int`: Non-zero values treated as `true`
   - Default behavior: `false` if variable is missing or unrecognized type

3. **Enhanced Logging**:
   - Clear indication when SSH restart is skipped due to disabled flag
   - Shows the actual variable value in log messages
   - Real-time WebSocket broadcast messages for monitoring

### Usage in Icinga2

#### Enable SSH Restart for a Service
```icinga2
object Service "my-critical-service" {
  host_name = "web-server-01"
  check_command = "check_service"
  
  vars {
    auto_restart_service_linux = true
    # other service variables...
  }
}
```

#### Disable SSH Restart for a Service
```icinga2
object Service "my-monitored-service" {
  host_name = "web-server-01"
  check_command = "check_service"
  
  vars {
    auto_restart_service_linux = false
    # SSH restart will be skipped
  }
}
```

#### Default Behavior (No Variable Set)
```icinga2
object Service "my-service" {
  host_name = "web-server-01"
  check_command = "check_service"
  
  # No auto_restart_service_linux variable
  # SSH restart will be skipped (defaults to false)
}
```

### Log Messages

When SSH restart is **enabled**:
```
✅ SSH restart enabled for web-server-01!my-critical-service (auto_restart_service_linux: true)
```

When SSH restart is **disabled**:
```
⏭️ SSH restart skipped for web-server-01!my-monitored-service (auto_restart_service_linux: false)
```

When variable is **not set**:
```
⏭️ SSH restart skipped for web-server-01!my-service (auto_restart_service_linux: not set)
```

### Benefits

1. **Fine-grained Control**: Administrators can enable/disable SSH restarts per service
2. **Safety**: Prevents unwanted restarts on critical services that should be manually handled
3. **Flexibility**: Supports different data types for compatibility with various Icinga2 configurations
4. **Visibility**: Clear logging and real-time monitoring of restart decisions
5. **Backward Compatibility**: Existing services without the variable safely default to no restart

### Testing

Comprehensive unit tests verify:
- Correct handling of `true`/`false` boolean values
- String value parsing (`"true"`, `"false"`)
- Integer value handling (non-zero = true, zero = false)
- Missing variable handling (defaults to false)
- Missing vars section handling
- Type safety and error handling

All tests pass successfully, ensuring robust operation in production environments.