/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:serverpod/serverpod.dart' as _i1;
import '../endpoints/portainer_ops.dart' as _i2;

class Endpoints extends _i1.EndpointDispatch {
  @override
  void initializeEndpoints(_i1.Server server) {
    var endpoints = <String, _i1.Endpoint>{
      'portainerOps': _i2.PortainerOpsEndpoint()
        ..initialize(
          server,
          'portainerOps',
          null,
        )
    };
    connectors['portainerOps'] = _i1.EndpointConnector(
      name: 'portainerOps',
      endpoint: endpoints['portainerOps']!,
      methodConnectors: {
        'checkService': _i1.MethodConnector(
          name: 'checkService',
          params: {
            'serviceId': _i1.ParameterDescription(
              name: 'serviceId',
              type: _i1.getType<int?>(),
              nullable: true,
            ),
            'serviceName': _i1.ParameterDescription(
              name: 'serviceName',
              type: _i1.getType<String?>(),
              nullable: true,
            ),
            'configPath': _i1.ParameterDescription(
              name: 'configPath',
              type: _i1.getType<String?>(),
              nullable: true,
            ),
            'endpointId': _i1.ParameterDescription(
              name: 'endpointId',
              type: _i1.getType<int?>(),
              nullable: true,
            ),
          },
          call: (
            _i1.Session session,
            Map<String, dynamic> params,
          ) async =>
              (endpoints['portainerOps'] as _i2.PortainerOpsEndpoint)
                  .checkService(
            session,
            serviceId: params['serviceId'],
            serviceName: params['serviceName'],
            configPath: params['configPath'],
            endpointId: params['endpointId'],
          ),
        )
      },
    );
  }
}
