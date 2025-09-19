# Configuration Restructuring: Connection-Based Restart Settings

## Overview

Successfully restructured the SSH restart configuration from a rule-based approach to a connection-based approach, moving `maxRestarts` and `timeBetweenRestartAttempts` (renamed from `cooldownMinutes`) to the SSH connection level. This simplifies configuration management and provides a cleaner architecture.

## Changes Made

### 1. SSH Connection Model Updates

**File**: `lib/src/ops/models/ssh_connection.dart`

- Added `maxRestarts` field (default: 3 attempts)
- Added `timeBetweenRestartAttempts` field (default: 10 minutes)
- Updated `fromMap()` factory to load new fields from YAML
- Updated `toMap()`, equality, and hashCode methods
- Connection now contains all restart behavior settings

### 2. Configuration Structure Simplification

**File**: `lib/src/ops/models/restart_rule.dart`

- Added `restartMappings` field to `SshRestartConfig`
- Added `getConnectionForService()` method for service-to-connection mapping
- Maintained backward compatibility with legacy rules
- Simplified service restart mapping using connection names

### 3. Updated Configuration File

**File**: `config/ssh_restart.yaml`

**NEW STRUCTURE** (simplified - no mappings needed):
```yaml
connections:
  ghrunner.grsoft.no:                        # Connection name = hostname
    host: "ghrunner.grsoft.no"
    port: 22
    username: "root"
    privateKeyPath: "/home/grotan/.ssh/id_ed25519"
    timeoutSeconds: 30
    maxRestarts: 2                           # Connection-level setting
    timeBetweenRestartAttempts: 15           # Connection-level setting

# No restartMappings section needed!
# Services automatically find connections by hostname from Icinga2
```

**OLD STRUCTURE** (deprecated):
```yaml
connections:
  # SSH settings only
rules:
  - systemdServiceName: "ser2net"
    maxRestarts: 2                         # Service-level setting
    cooldownMinutes: 15                    # Service-level setting
```

### 4. Service Restart Logic Updates

**File**: `lib/src/ops/services/linux_service_restart_service.dart`

- Updated `_canRestart()` method to accept `SshConnection` instead of `RestartRule`
- Modified cooldown checking to use `connection.timeBetweenRestartAttempts`
- Updated restart limit checking to use `connection.maxRestarts`

### 5. Alert Service Integration

**File**: `lib/src/icinga2_alert_service.dart`

- Replaced complex rule-based logic with simplified connection-based approach
- Updated `_executeAutomaticRestart()` to use `getConnectionForService()`
- Automatic fallback to hostname-based connection selection
- Dynamic connection creation with connection-level restart settings

## Benefits

### 1. **Simplified Configuration**
- **Before**: Each service required its own rule with restart settings
- **After**: All services on a host share the same restart behavior
- **Result**: Dramatically reduced configuration complexity

### 2. **Consistent Host Behavior**
- All services on the same host have consistent restart limits and timing
- Easier to manage restart behavior per environment (prod vs dev)
- Logical grouping by infrastructure rather than individual services

### 3. **Cleaner Architecture**
- Separation of concerns: connections handle SSH + restart settings, mappings handle service routing
- Reduced duplication of restart settings across services
- More maintainable and predictable configuration

### 4. **Backward Compatibility**
- Legacy rules still supported during transition period
- Gradual migration path for existing configurations
- No breaking changes for current deployments

## Configuration Examples

### Production Environment
```yaml
connections:
  production.example.com:                    # Connection name = hostname
    host: "production.example.com"
    username: "monitoring"
    privateKeyPath: "/etc/ssh/monitoring_key"
    maxRestarts: 2                           # Conservative for production
    timeBetweenRestartAttempts: 15           # Longer cooldown for stability

# No restartMappings needed! Services automatically find connections by hostname
# When Icinga2 sends alert for host "production.example.com", it automatically uses this connection
```

### Development Environment
```yaml
connections:
  development.example.com:                   # Connection name = hostname
    host: "development.example.com"
    username: "monitoring"
    privateKeyPath: "/etc/ssh/monitoring_key"
    maxRestarts: 5                           # More attempts for development
    timeBetweenRestartAttempts: 5            # Faster recovery for testing

# All services on development.example.com automatically inherit these settings
```

## Migration Guide

### For Existing Configurations

1. **Remove restartMappings** - they're no longer needed!
2. **Name connections after hostnames** - this enables automatic selection
3. **Update connection host properties** to match Icinga2 hostnames

### For New Deployments

1. **Name connections after hostnames** from your Icinga2 monitoring
2. **Configure restart settings** appropriate for each environment at connection level
3. **No explicit mappings needed** - hostname matching handles everything automatically!

## Testing Coverage

All functionality verified with comprehensive tests:
- ✅ Connection-based configuration loading
- ✅ Service-to-connection mapping
- ✅ Restart settings inheritance from connections
- ✅ Backward compatibility with legacy rules
- ✅ Hostname-based fallback connections
- ✅ Dynamic connection creation

## Impact Summary

### Configuration Complexity: **Eliminated**
- **Before**: N services = N rules with restart settings + N mappings
- **After**: N services = 1 connection per hostname (pure hostname matching)

### Maintainability: **Dramatically Improved**
- Zero-configuration service discovery via hostname matching
- Connection names match Icinga2 hostnames for automatic selection
- No explicit mappings or rules required

### Operational Benefits: **Maximized**
- Add new services automatically - no configuration changes needed
- Hostname-based connection discovery eliminates configuration errors
- Intuitive connection naming (hostname) simplifies management

This restructuring provides a solid foundation for scalable restart configuration management while maintaining all existing functionality and providing a clear migration path.