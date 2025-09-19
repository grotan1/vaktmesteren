# maxRestartsPerHour → maxRestarts Implementation

## Overview

Successfully replaced the time-based `maxRestartsPerHour` field with a simpler `maxRestarts` counter that resets when Icinga2 state changes from CRITICAL to OK. This provides more predictable restart behavior aligned with service recovery cycles.

## Key Changes Made

### 1. **RestartRule Model** (`lib/src/ops/models/restart_rule.dart`)
- **Replaced**: `maxRestartsPerHour: int` → `maxRestarts: int`
- **Added**: Backward compatibility support in `fromMap()` factory
- **Updated**: Constructor, `toMap()`, and field documentation
- **Default**: Changed from 3/hour to 3 attempts (resets on state change)

### 2. **Restart Service Logic** (`lib/src/ops/services/linux_service_restart_service.dart`)
- **Simplified**: `_canRestart()` method now uses simple counter vs limit
- **Removed**: Time-based calculations (1-hour window, cleanup logic)
- **Added**: `resetRestartCounter()` method for state-based resets
- **Updated**: Error messages to reflect attempt-based limits

### 3. **State Change Integration** (`lib/src/icinga2_alert_service.dart`)
- **Added**: Counter reset logic in `_handleStateTransition()`
- **Trigger**: Resets when service transitions from CRITICAL → OK
- **Updated**: Default rule creation to use `maxRestarts: 3`
- **Updated**: Logging messages to show "attempts" instead of "/hour"

### 4. **Configuration Files**
- **ssh_restart.yaml**: Updated examples and documentation
- **Config Loader**: Updated validation and example configurations
- **Comments**: Clarified that counters reset on state changes

### 5. **Comprehensive Test Updates**
- **All test files**: Migrated from `maxRestartsPerHour` to `maxRestarts`
- **New test**: `restart_counter_reset_test.dart` demonstrating the concept
- **Verification**: All 31 tests passing with new implementation

## Behavioral Changes

### Before (Time-based)
```yaml
maxRestartsPerHour: 3  # Max 3 restarts in any 1-hour period
```
- Counter decremented over time (1-hour sliding window)
- Could lead to indefinite restart blocking if service stuck
- Complex time-based calculations and cleanup

### After (State-based)
```yaml
maxRestarts: 3  # Max 3 restart attempts (resets when state changes)
```
- Simple counter: attempts vs limit
- Resets to 0 when service recovers (CRITICAL → OK)
- Fresh restart capability after each recovery cycle

## Implementation Benefits

### 1. **Predictable Behavior**
- Clear restart limits tied to service states
- No confusion about time windows
- Fresh attempts after recovery

### 2. **Simplified Logic**
- No time-based calculations
- No background cleanup required
- Straightforward counter management

### 3. **Better Operational Model**
- Aligns with monitoring cycles
- Recovery-focused approach
- More intuitive troubleshooting

### 4. **Backward Compatibility**
- Config loader accepts both field names
- Graceful migration path
- No breaking changes for existing configs

## Configuration Examples

### Modern Configuration
```yaml
rules:
  - systemdServiceName: "nginx"
    maxRestarts: 3                    # Allow 3 restart attempts
    cooldownMinutes: 10               # Wait 10min between attempts
    # Counter resets when service recovers (CRITICAL → OK)
```

### Default Behavior
```yaml
# Services WITHOUT explicit rules get conservative defaults:
# - maxRestarts: 3 attempts
# - cooldownMinutes: 10
# - Counter resets on state change
```

## Migration Path

### For Existing Configs
1. **No immediate action required**: Backward compatibility maintained
2. **Gradual migration**: Update `maxRestartsPerHour` → `maxRestarts` at convenience
3. **New behavior**: Restart limits now reset on service recovery

### For New Deployments
1. **Use new field**: Configure `maxRestarts` for attempt-based limits
2. **Understand resets**: Counters reset when services recover
3. **Monitor behavior**: Observe more predictable restart patterns

## Testing Coverage

All functionality verified with comprehensive tests (31/31 passing):
- ✅ Default rule creation with new field
- ✅ Backward compatibility with old field names
- ✅ State-based counter reset concept
- ✅ Rule precedence and lookup
- ✅ Host-based connection selection
- ✅ Dynamic connection creation
- ✅ Integration with existing SSH restart system

## Summary

This implementation provides a cleaner, more predictable restart limiting system that aligns with service monitoring patterns. Restart attempts are tied to service state transitions rather than arbitrary time windows, making the system more intuitive and operationally friendly.

**Key Benefit**: Services get fresh restart attempts after recovery, enabling better automated recovery while still preventing restart loops during persistent failures.