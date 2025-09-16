/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:serverpod_client/serverpod_client.dart' as _i1;
import 'dart:async' as _i2;
import 'protocol.dart' as _i3;

/// {@category Endpoint}
class EndpointPortainerOps extends _i1.EndpointRef {
  EndpointPortainerOps(_i1.EndpointCaller caller) : super(caller);

  @override
  String get name => 'portainerOps';

  /// Check whether a service exists in Portainer.
  ///
  /// This endpoint is intentionally left open (no auth) per operator request.
  _i2.Future<Map<String, dynamic>> checkService({
    int? serviceId,
    String? serviceName,
    String? configPath,
    int? endpointId,
  }) =>
      caller.callServerEndpoint<Map<String, dynamic>>(
        'portainerOps',
        'checkService',
        {
          'serviceId': serviceId,
          'serviceName': serviceName,
          'configPath': configPath,
          'endpointId': endpointId,
        },
      );
}

class Client extends _i1.ServerpodClientShared {
  Client(
    String host, {
    dynamic securityContext,
    _i1.AuthenticationKeyManager? authenticationKeyManager,
    Duration? streamingConnectionTimeout,
    Duration? connectionTimeout,
    Function(
      _i1.MethodCallContext,
      Object,
      StackTrace,
    )? onFailedCall,
    Function(_i1.MethodCallContext)? onSucceededCall,
    bool? disconnectStreamsOnLostInternetConnection,
  }) : super(
          host,
          _i3.Protocol(),
          securityContext: securityContext,
          authenticationKeyManager: authenticationKeyManager,
          streamingConnectionTimeout: streamingConnectionTimeout,
          connectionTimeout: connectionTimeout,
          onFailedCall: onFailedCall,
          onSucceededCall: onSucceededCall,
          disconnectStreamsOnLostInternetConnection:
              disconnectStreamsOnLostInternetConnection,
        ) {
    portainerOps = EndpointPortainerOps(this);
  }

  late final EndpointPortainerOps portainerOps;

  @override
  Map<String, _i1.EndpointRef> get endpointRefLookup =>
      {'portainerOps': portainerOps};

  @override
  Map<String, _i1.ModuleEndpointCaller> get moduleLookup => {};
}
