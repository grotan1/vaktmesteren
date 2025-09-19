# Default Restart Behavior Implementation

## Overview

This implementation provides automatic default restart behavior for all services detected via Icinga2's `systemd_unit_unit` variable, even when they don't have explicit restart rules configured. This ensures that monitoring can automatically attempt to recover services while still allowing fine-grained control for critical services.

## Key Features

### 1. Default Restart Behavior
- **Conservative Settings**: Any service detected via `systemd_unit_unit` will be restarted with safe defaults
- **Max Restarts**: 2 per hour (conservative to prevent restart loops)
- **Cooldown Period**: 10 minutes between restart attempts
- **Pre-checks**: None (minimal intervention)
- **Post-checks**: Basic service status check (`sudo systemctl is-active servicename`)

### 2. Rule Precedence
- **Explicit Rules First**: Services with configured rules use their specific settings
- **Default Fallback**: Services without explicit rules use conservative default behavior
- **Host-based Connection**: Automatically selects SSH connection based on Icinga2 hostname

### 3. Dynamic Connection Creation
- **Host-based Lookup**: First attempts to find SSH connection by exact hostname match
- **Template-based Creation**: Uses 'default' connection as template with target hostname
- **Standard Defaults**: Falls back to standard monitoring connection settings if no template

## Implementation Details

### Modified Files

#### `lib/src/icinga2_alert_service.dart`
- **Method**: `_executeAutomaticRestart`
- **Enhancement**: Added default restart logic for services without explicit rules
- **Logic Flow**:
  1. Check for existing rule (use if found)
  2. If no rule found, determine SSH connection
  3. Create default restart rule with conservative settings
  4. Execute restart using default rule

#### `test/icinga2_default_restart_test.dart` (NEW)
- **Purpose**: Test default restart behavior implementation
- **Coverage**: 
  - Default rule creation with conservative settings
  - Workflow for unconfigured services
  - Rule precedence verification

### Code Example

```dart
// Create a default restart rule for the automatic detection
final defaultRule = RestartRule(
  systemdServiceName: systemdUnitName,
  enabled: true,
  maxRestartsPerHour: 2, // Conservative default
  cooldownPeriod: const Duration(minutes: 10), // Conservative cooldown
  preChecks: [], // No pre-checks by default
  postChecks: ['sudo systemctl is-active $systemdUnitName'], // Basic post-check
);
```

## Configuration Impact

### SSH Restart Rules (`config/ssh_restart.yaml`)
- **No changes required**: Existing configurations continue to work
- **Simplified rules**: Only need to configure services requiring special treatment
- **Default behavior**: All other services get automatic restart capability

### Example Workflow

1. **Icinga2 Alert**: Service `unknown-service` goes CRITICAL
2. **Auto-detection**: Extract `systemd_unit_unit: unknown-service`
3. **Rule Lookup**: No explicit rule found for `unknown-service`
4. **Default Behavior**: Create conservative restart rule
5. **Connection Selection**: Use host-based connection or create dynamic one
6. **Restart Execution**: Execute with 2/hour limit and 10min cooldown

## Benefits

### 1. Comprehensive Coverage
- **All Services**: Every service with `systemd_unit_unit` can be automatically restarted
- **No Configuration Required**: Works out-of-the-box for new services
- **Safe Defaults**: Conservative settings prevent restart loops

### 2. Operational Efficiency
- **Reduced Manual Intervention**: Most service issues handled automatically
- **Fine-grained Control**: Critical services can still have custom rules
- **Monitoring-friendly**: Standard monitoring patterns work seamlessly

### 3. Safety Features
- **Throttling**: Built-in rate limiting prevents restart storms
- **Logging**: Comprehensive logging of all restart attempts
- **Simulation Mode**: Test behavior safely with `logOnly: true`

## Testing Coverage

All functionality is covered by comprehensive tests:

- ✅ Default rule creation with conservative settings
- ✅ Workflow for unconfigured services  
- ✅ Rule precedence (explicit rules override defaults)
- ✅ Host-based connection selection
- ✅ Dynamic connection creation
- ✅ Auto-detection of systemd services
- ✅ Integration with existing SSH restart system

## Migration Path

### For Existing Deployments
1. **No immediate changes**: Current configurations continue working
2. **Gradual simplification**: Remove redundant rules over time
3. **Focus on critical services**: Keep explicit rules only for services needing special handling

### For New Deployments
1. **Minimal configuration**: Only configure SSH connections and critical service rules
2. **Default behavior**: All other services get automatic restart capability
3. **Monitor and adjust**: Fine-tune default settings based on operational experience

This implementation provides a robust foundation for automatic service recovery while maintaining the flexibility to handle edge cases and critical services with specialized requirements.