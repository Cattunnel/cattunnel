import 'package:trusttunnel/common/controller/concurrency/sequential_controller_handler.dart';
import 'package:trusttunnel/common/controller/controller/state_controller.dart';
import 'package:trusttunnel/common/error/exception_utils.dart';
import 'package:trusttunnel/common/error/model/presentation_code_exception.dart';
import 'package:trusttunnel/common/error/model/presentation_exception.dart';
import 'package:trusttunnel/common/error/model/presentation_field.dart';
import 'package:trusttunnel/common/models/value_data.dart';
import 'package:trusttunnel/data/model/vpn_protocol.dart';
import 'package:trusttunnel/data/repository/routing_repository.dart';
import 'package:trusttunnel/data/repository/server_repository.dart';
import 'package:trusttunnel/feature/server/server_details/controller/servers_details_states.dart';
import 'package:trusttunnel/feature/server/server_details/domain/service/server_details_service.dart';
import 'package:vpn_plugin/domain/desync_string.dart';

/// {@template products_controller}
/// Controller for managing products and purchase operations.
/// {@endtemplate}
final class ServerDetailsController extends BaseStateController<ServerDetailsState> with SequentialControllerHandler {
  final ServerRepository _repository;
  final RoutingRepository _routingRepository;
  final ServerDetailsService _detailsService;
  final String? _serverId;

  /// Set when a server being added (e.g. from an imported link) is a new
  /// version of an existing manual server - see
  /// [ServerDetailsService.findServerToReplace]. Saving then updates that
  /// server instead of adding a duplicate.
  String? _replacingServerId;
  String? _replacingServerName;
  String? _replacingServerAddress;

  /// The old address of the manual server a new link is about to update
  /// (null when adding a new server or editing one) - for the "port
  /// updated 8443 -> 9443" snackbar.
  String? get replacedAddress => _replacingServerAddress;

  /// {@macro products_controller}
  ServerDetailsController({
    required ServerRepository repository,
    required RoutingRepository routingRepository,
    required ServerDetailsService detailsService,
    required String? serverId,
    super.initialState = const ServerDetailsState.initial(),
  }) : _repository = repository,
       _routingRepository = routingRepository,
       _detailsService = detailsService,
       _serverId = serverId;

  /// Make a purchase for the given product ID
  void fetch() {
    handle(
      () async {
        setState(
          ServerDetailsState.loading(
            data: state.data,
            initialData: state.initialData,
            fieldErrors: state.fieldErrors,
            routingProfiles: state.routingProfiles,
          ),
        );

        final profiles = await _routingRepository.getAllProfiles();
        if (_serverId == null) {
          String serverName = state.data.name.trim();
          String routingProfileId = state.data.routingProfileId;
          final servers = await _repository.getAllServers();
          final replacing = _detailsService.findServerToReplace(state.data, servers);

          if (replacing != null) {
            // Keep the user's name and routing choice for that server; take
            // everything else (address/port, DNS, ...) from the new link.
            _replacingServerId = replacing.id;
            _replacingServerName = replacing.serverData.name;
            _replacingServerAddress = replacing.serverData.ipAddress;
            serverName = replacing.serverData.name;
            routingProfileId = replacing.serverData.routingProfileId;
          } else if (serverName.isNotEmpty) {
            serverName = _detailsService.fallbackDuplicateNames(
              serverName,
              servers.map((server) => server.serverData.name).toSet(),
            );
          }

          setState(
            ServerDetailsState.idle(
              data: state.data.copyWith(
                name: serverName,
                routingProfileId: routingProfileId,
              ),
              initialData: state.initialData,
              fieldErrors: state.fieldErrors,
              routingProfiles: profiles,
            ),
          );

          return;
        }

        final server = await _repository.getServerById(id: _serverId);

        if (server == null) {
          throw const PresentationNotFoundException();
        }

        setState(
          ServerDetailsState.idle(
            data: server.serverData,
            initialData: server.serverData,
            fieldErrors: state.fieldErrors,
            routingProfiles: profiles,
          ),
        );
      },
      errorHandler: _onError,
      completionHandler: _onCompleted,
    );
  }

  void pickPemCertificate() => handle(
    () async {
      setState(
        ServerDetailsState.loading(
          data: state.data,
          initialData: state.initialData,
          fieldErrors: state.fieldErrors,
          routingProfiles: state.routingProfiles,
        ),
      );
      final certificate = await _repository.pickCertificate();
      if (certificate == null) {
        return;
      }
      setState(
        ServerDetailsState.idle(
          data: state.data.copyWith(
            certificate: ValueData(
              certificate,
            ),
          ),
          initialData: state.initialData,
          fieldErrors: state.fieldErrors,
          routingProfiles: state.routingProfiles,
        ),
      );
    },
    errorHandler: _onError,
    completionHandler: _onCompleted,
  );

  void clearPemCertificate() => handle(
    () async {
      setState(
        ServerDetailsState.idle(
          data: state.data.copyWith(
            certificate: const ValueData(null),
          ),
          initialData: state.initialData,
          fieldErrors: state.fieldErrors,
          routingProfiles: state.routingProfiles,
        ),
      );
    },
    errorHandler: _onError,
    completionHandler: _onCompleted,
  );

  void dataChanged({
    String? serverName,
    String? ipAddress,
    String? domain,
    String? username,
    String? password,
    bool? enableIpv6,
    bool? antiDpi,
    int? antiDpiMode,
    String? tlsProfile,
    String? antiDpiDesync,
    int? h2PaddingFrames,
    bool? blockQuic,
    bool? ruExit,
    String? pathToPemFile,
    VpnProtocol? protocol,
    String? routingProfileId,
    List<String>? dnsServers,
    ValueData<String>? clientRandom,
    ValueData<String>? customSni,
  }) => handle(
    () {
      setState(
        ServerDetailsState.idle(
          fieldErrors: state.fieldErrors,
          initialData: state.initialData,
          routingProfiles: state.routingProfiles,
          data: state.data.copyWith(
            name: serverName ?? state.data.name,
            ipAddress: (ipAddress ?? state.data.ipAddress).trim(),
            domain: (domain ?? state.data.domain).trim(),
            username: (username ?? state.data.username).trim(),
            password: (password ?? state.data.password).trim(),
            vpnProtocol: protocol ?? state.data.vpnProtocol,
            routingProfileId: routingProfileId ?? state.data.routingProfileId,
            dnsServers: (dnsServers ?? state.data.dnsServers).map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
            ipv6: enableIpv6 ?? state.data.ipv6,
            antiDpi: antiDpi ?? state.data.antiDpi,
            antiDpiMode: antiDpiMode ?? state.data.antiDpiMode,
            tlsProfile: tlsProfile ?? state.data.tlsProfile,
            antiDpiDesync: antiDpiDesync ?? state.data.antiDpiDesync,
            h2PaddingFrames: h2PaddingFrames ?? state.data.h2PaddingFrames,
            blockQuic: blockQuic ?? state.data.blockQuic,
            ruExit: ruExit ?? state.data.ruExit,
            tlsPrefix: clientRandom == null ? null : ValueData(clientRandom.value?.trim()),
            customSni: customSni == null ? null : ValueData(customSni.value?.trim()),
          ),
        ),
      );
    },
    errorHandler: _onError,
    completionHandler: _onCompleted,
  );

  void submit(void Function(String name) onSaved) => handle(
    () async {
      setState(
        ServerDetailsState.loading(
          data: state.data.copyWith(
            name: state.data.name.trim(),
            ipAddress: state.data.ipAddress.trim(),
            domain: state.data.domain.trim(),
            username: state.data.username.trim(),
            password: state.data.password.trim(),
            dnsServers: state.data.dnsServers.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
            ipv6: state.data.ipv6,
            tlsPrefix: ValueData(state.data.tlsPrefix?.trim()),
            customSni: ValueData(state.data.customSni?.trim()),
            antiDpiDesync: DesyncString.normalize(state.data.antiDpiDesync),
          ),
          initialData: state.initialData,
          fieldErrors: state.fieldErrors,
          routingProfiles: state.routingProfiles,
        ),
      );

      final servers = await _repository.getAllServers();

      final List<PresentationField> filedErrors = _detailsService.validateData(
        data: state.data,
        otherServersNames: servers.map((server) => server.serverData.name).toSet()
          ..remove(
            state.initialData.name,
          )
          ..remove(_replacingServerName),
      );

      if (filedErrors.isEmpty) {
        final targetId = _serverId ?? _replacingServerId;
        if (targetId != null) {
          await _repository.setNewServer(
            id: targetId,
            request: state.data,
          );
        } else {
          await _repository.addNewServer(
            request: state.data,
          );
        }
        onSaved(
          state.data.name,
        );
      }

      setState(
        ServerDetailsState.idle(
          data: state.data,
          initialData: state.initialData,
          fieldErrors: filedErrors,
          routingProfiles: state.routingProfiles,
        ),
      );
    },
    errorHandler: _onError,
    completionHandler: _onCompleted,
  );

  void delete(
    void Function(String name) onDeleted,
  ) => handle(
    () async {
      setState(
        ServerDetailsState.loading(
          data: state.data,
          initialData: state.initialData,
          fieldErrors: state.fieldErrors,
          routingProfiles: state.routingProfiles,
        ),
      );

      await _repository.removeServer(serverId: _serverId!);

      setState(
        ServerDetailsState.idle(
          data: state.data,
          initialData: state.initialData,
          fieldErrors: state.fieldErrors,
          routingProfiles: state.routingProfiles,
        ),
      );

      onDeleted(
        state.data.name,
      );
    },
    errorHandler: _onError,
    completionHandler: _onCompleted,
  );

  PresentationException _parseException(Object? exception) =>
      ExceptionUtils.toPresentationException(exception: exception);

  Future<void> _onError(Object? error, StackTrace _) async {
    final presentationException = _parseException(error);

    setState(
      ServerDetailsState.exception(
        exception: presentationException,
        data: state.data,
        initialData: state.initialData,
        fieldErrors: state.fieldErrors,
        routingProfiles: state.routingProfiles,
      ),
    );
  }

  Future<void> _onCompleted() async => setState(
    ServerDetailsState.idle(
      data: state.data,
      initialData: state.initialData,
      fieldErrors: state.fieldErrors,
      routingProfiles: state.routingProfiles,
    ),
  );
}
