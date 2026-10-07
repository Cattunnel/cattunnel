import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/asset_icons.dart';
import 'package:trusttunnel/common/error/model/enum/presentation_field_name.dart';
import 'package:trusttunnel/common/error/model/presentation_field.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/extensions/locale_enum_extension.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/models/value_data.dart';
import 'package:trusttunnel/common/utils/routing_profile_utils.dart';
import 'package:trusttunnel/common/utils/validation_utils.dart';
import 'package:trusttunnel/data/model/routing_profile.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/vpn_protocol.dart';
import 'package:trusttunnel/feature/server/server_details/widgets/scope/server_details_scope.dart';
import 'package:trusttunnel/feature/server/server_details/widgets/scope/server_details_scope_aspect.dart';
import 'package:trusttunnel/feature/server/server_details/widgets/server_help_sheet.dart';
import 'package:trusttunnel/feature/vpn/domain/tls_profile_auto.dart';
import 'package:trusttunnel/widgets/buttons/custom_icon_button.dart';
import 'package:trusttunnel/widgets/inputs/custom_text_field.dart';
import 'package:trusttunnel/widgets/menu/custom_dropdown_menu.dart';
import 'package:vpn_plugin/domain/desync_string.dart';

/// The groups of the server form. [bypass] is what people change; the rest
/// starts collapsed (except [key] for a new server, which needs it filled).
/// [travel] holds the Russian-exit switch - rarely needed, and its text only
/// makes sense for a server in Russia, so it stays out of [bypass].
enum _Section { bypass, routing, key, expert, travel }

class ServerDetailsForm extends StatefulWidget {
  const ServerDetailsForm({super.key});

  @override
  State<ServerDetailsForm> createState() => _ServerDetailsFormState();
}

class _ServerDetailsFormState extends State<ServerDetailsForm> {
  late ServerData _formData;
  late List<PresentationField> _fieldErrors;
  late List<RoutingProfile> _routingProfiles;
  late RoutingProfile _pickedRoutingProfile;
  late final ValueNotifier<bool> _isPasswordVisibleNotifier;
  late final Set<_Section> _expanded;

  /// What "auto" fingerprint means on this device, shown under the menu.
  TlsProfileChoice? _autoTls;
  bool _redetectingTls = false;

  /// Where each field the validator can flag lives, to open its group.
  static const _sectionOf = {
    PresentationFieldName.antiDpiDesync: _Section.bypass,
    PresentationFieldName.dnsServers: _Section.routing,
    PresentationFieldName.ipAddress: _Section.key,
    PresentationFieldName.domain: _Section.key,
    PresentationFieldName.userName: _Section.key,
    PresentationFieldName.password: _Section.key,
    PresentationFieldName.certificate: _Section.key,
    PresentationFieldName.sni: _Section.expert,
    PresentationFieldName.clientRandom: _Section.expert,
    PresentationFieldName.clientRandomMask: _Section.expert,
    PresentationFieldName.clientRandomValue: _Section.expert,
  };

  @override
  void initState() {
    super.initState();
    final controller = ServerDetailsScope.controllerOf(context, listen: false);
    _formData = controller.data;
    _fieldErrors = controller.fieldErrors;
    _routingProfiles = controller.routingProfiles;
    _pickedRoutingProfile = _getSelectedRoutingProfile(_routingProfiles, _formData.routingProfileId);
    _isPasswordVisibleNotifier = ValueNotifier<bool>(false);
    _expanded = {
      _Section.bypass,
      if (!controller.editing) _Section.key,
      ..._sectionsWithErrors(),
    };
    TlsProfileAuto.current().then((choice) {
      if (mounted) setState(() => _autoTls = choice);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dataSpecific = ServerDetailsScope.controllerOf(
      context,
      aspect: ServerDetailsScopeAspect.data,
    );

    final fieldErrors = ServerDetailsScope.controllerOf(
      context,
      aspect: ServerDetailsScopeAspect.fieldErrors,
    ).fieldErrors;
    if (!identical(fieldErrors, _fieldErrors)) {
      _fieldErrors = fieldErrors;
      // A failed save opens the groups it complains about.
      _expanded.addAll(_sectionsWithErrors());
    }

    _formData = dataSpecific.data;
    _routingProfiles = dataSpecific.routingProfiles;
    _pickedRoutingProfile = _getSelectedRoutingProfile(_routingProfiles, _formData.routingProfileId);
  }

  Iterable<_Section> _sectionsWithErrors() => _fieldErrors.map((e) => _sectionOf[e.fieldName]).nonNulls;

  String? _error(PresentationFieldName name) => ValidationUtils.getErrorString(context, _fieldErrors, name);

  @override
  Widget build(BuildContext context) {
    final errorSections = _sectionsWithErrors().toSet();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          CustomTextField(
            value: _formData.name,
            label: context.ln.serverName,
            hint: context.ln.serverName,
            onChanged: (serverName) => _onDataChanged(
              context,
              serverName: serverName,
            ),
            error: _error(PresentationFieldName.serverName),
          ),
          if (_summary() case final summary?)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                summary,
                style: context.textTheme.bodySmall?.copyWith(color: context.colors.neutralDark),
              ),
            ),
          const SizedBox(height: 4),
          _section(
            _Section.bypass,
            title: context.ln.serverSectionBypass,
            hasError: errorSections.contains(_Section.bypass),
            help: [
              (title: context.ln.helpAntiDpiTitle, body: context.ln.helpAntiDpiBody),
              (title: context.ln.helpAntiDpiModesTitle, body: context.ln.helpAntiDpiModesBody),
              (title: context.ln.helpAntiDpiCustomTitle, body: context.ln.helpAntiDpiCustomBody),
              (title: context.ln.helpTlsProfileTitle, body: context.ln.helpTlsProfileBody),
            ],
            children: _bypassFields(context),
          ),
          _section(
            _Section.routing,
            title: context.ln.serverSectionRouting,
            summary: _pickedRoutingProfile.data.name,
            hasError: errorSections.contains(_Section.routing),
            help: [
              (title: context.ln.helpRoutingTitle, body: context.ln.helpRoutingBody),
              (title: context.ln.helpDnsTitle, body: context.ln.helpDnsBody),
            ],
            children: _routingFields(context),
          ),
          _section(
            _Section.key,
            title: context.ln.serverSectionKey,
            summary: _formData.username.isEmpty ? null : _formData.username,
            hasError: errorSections.contains(_Section.key),
            help: [(title: context.ln.helpKeyTitle, body: context.ln.helpKeyBody)],
            children: _keyFields(context),
          ),
          _section(
            _Section.expert,
            title: context.ln.serverSectionExpert,
            summary: _formData.vpnProtocol.localized(context),
            hasError: errorSections.contains(_Section.expert),
            help: [(title: context.ln.helpExpertTitle, body: context.ln.helpExpertBody)],
            children: _expertFields(context),
          ),
          _section(
            _Section.travel,
            title: context.ln.serverSectionTravel,
            summary: _formData.ruExit ? context.ln.serverSectionTravelOn : null,
            help: [(title: context.ln.helpRuExitTitle, body: context.ln.ruExitDescription)],
            children: [
              SwitchListTile(
                value: _formData.ruExit,
                title: Text(context.ln.ruExitLabel),
                subtitle: Text(context.ln.ruExitDescription),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                onChanged: (value) => _onDataChanged(
                  context,
                  ruExit: value,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// "address · domain" under the name, once there is an address.
  String? _summary() {
    final parts = [
      _formData.ipAddress,
      if (_formData.domain != _formData.ipAddress) _formData.domain,
    ].where((p) => p.isNotEmpty);

    return parts.isEmpty ? null : parts.join(' · ');
  }

  Widget _section(
    _Section section, {
    required String title,
    required List<ServerHelpEntry> help,
    required List<Widget> children,
    String? summary,
    bool hasError = false,
  }) {
    final expanded = _expanded.contains(section);
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.backgroundAdditional,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => expanded ? _expanded.remove(section) : _expanded.add(section)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: context.textTheme.titleMedium),
                        if (hasError && !expanded)
                          Text(
                            context.ln.serverSectionHasError,
                            style: context.textTheme.bodySmall?.copyWith(color: colors.error),
                          )
                        else if (!expanded && summary != null)
                          Text(
                            summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.bodySmall?.copyWith(color: colors.neutralDark),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.ln.serverSectionHelp,
                    icon: const Icon(Icons.help_outline_rounded),
                    onPressed: () => ServerHelpSheet.show(context, title: title, entries: help),
                  ),
                  Icon(expanded ? AssetIcons.arrowDropUp : AssetIcons.arrowDropDown),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 20,
                      children: children,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  /// One menu for anti-DPI: off, or on with a technique.
  static const _antiDpiOff = -1;

  static const _antiDpiChoices = [
    _antiDpiOff,
    0,
    ServerData.antiDpiAuto,
    1,
    2,
    3,
    ServerData.antiDpiCustom,
  ];

  static const _desyncExamples = ['-o1+s -d3+s', '-d7', '-o3 -d7', '-s1 -d3+s'];

  List<Widget> _bypassFields(BuildContext context) {
    final choice = !_formData.antiDpi
        ? _antiDpiOff
        : _antiDpiChoices.contains(_formData.antiDpiMode)
        ? _formData.antiDpiMode
        : 0;

    return [
      CustomDropdownMenu<int>.expanded(
        value: choice,
        values: _antiDpiChoices,
        toText: (mode) => _antiDpiModeText(context, mode),
        labelText: context.ln.antiDpiLabel,
        onChanged: (mode) {
          if (mode == null) return;
          _onDataChanged(
            context,
            antiDpi: mode != _antiDpiOff,
            antiDpiMode: mode == _antiDpiOff ? null : mode,
          );
        },
      ),
      if (choice == ServerData.antiDpiCustom) ..._desyncFields(context),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CustomDropdownMenu<String>.expanded(
            value: _tlsProfiles.contains(_formData.tlsProfile) ? _formData.tlsProfile : ServerData.tlsProfileAuto,
            values: _tlsProfiles,
            toText: (profile) => _tlsProfileText(context, profile),
            labelText: context.ln.tlsProfileLabel,
            onChanged: (profile) => _onDataChanged(
              context,
              tlsProfile: profile,
            ),
          ),
          if (_formData.tlsProfile == ServerData.tlsProfileAuto && _autoTls != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _autoTls!.browser == null
                          ? context.ln.tlsProfileAutoRandom(_profileName(_autoTls!.profile))
                          : context.ln.tlsProfileAutoBrowser(_profileName(_autoTls!.profile)),
                      style: context.textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: _redetectingTls
                        ? null
                        : () async {
                            setState(() => _redetectingTls = true);
                            final choice = await TlsProfileAuto.redetect();
                            if (mounted) {
                              setState(() {
                                _autoTls = choice;
                                _redetectingTls = false;
                              });
                            }
                          },
                    child: Text(context.ln.tlsProfileRedetect),
                  ),
                ],
              ),
            ),
        ],
      ),
    ];
  }

  List<Widget> _desyncFields(BuildContext context) {
    final text = _formData.antiDpiDesync;
    // Live, so the exact part at fault shows while typing; an empty string
    // is only flagged on save.
    final liveError = text.trim().isEmpty ? null : _desyncErrorText(context, DesyncString.validate(text));

    return [
      CustomTextField(
        value: text,
        label: context.ln.antiDpiDesyncLabel,
        hint: context.ln.antiDpiDesyncHint,
        helper: context.ln.antiDpiDesyncHelper,
        onChanged: (value) => _onDataChanged(
          context,
          antiDpiDesync: value,
        ),
        error: liveError ?? _error(PresentationFieldName.antiDpiDesync),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(context.ln.antiDpiDesyncExamples, style: context.textTheme.bodySmall),
          for (final example in _desyncExamples)
            ActionChip(
              label: Text(example, style: const TextStyle(fontFamily: 'monospace')),
              onPressed: () => _onDataChanged(context, antiDpiDesync: example),
            ),
        ],
      ),
    ];
  }

  String? _desyncErrorText(BuildContext context, DesyncStringError? error) => switch (error?.reason) {
    null => null,
    DesyncStringErrorReason.unknown => context.ln.antiDpiDesyncErrorUnknown(error!.token),
    DesyncStringErrorReason.recordSplit => context.ln.antiDpiDesyncErrorRecordSplit(error!.token),
    DesyncStringErrorReason.position => context.ln.antiDpiDesyncErrorPosition(error!.token),
    DesyncStringErrorReason.tooMany => context.ln.antiDpiDesyncErrorTooMany,
    DesyncStringErrorReason.oobWithoutTtl => context.ln.antiDpiDesyncErrorOobWithoutTtl,
  };

  List<Widget> _routingFields(BuildContext context) => [
    CustomDropdownMenu<RoutingProfile>.expanded(
      value: _pickedRoutingProfile,
      values: _routingProfiles,
      toText: (value) => value.data.name,
      labelText: context.ln.routingProfile,
      onChanged: (profile) => _onDataChanged(
        context,
        routingProfileId: profile?.id,
      ),
    ),
    CustomTextField(
      value: _formData.dnsServers.join('\n'),
      hint: context.ln.enterDnsServerHint,
      label: context.ln.enterDnsServerLabel,
      helper: context.ln.enterDnsServerHelper,
      minLines: 1,
      maxLines: 4,
      onChanged: (dns) => _onDataChanged(
        context,
        dnsServers: dns.trim().split('\n'),
      ),
      error: _error(PresentationFieldName.dnsServers),
    ),
    SwitchListTile(
      value: _formData.ipv6,
      title: Text(context.ln.ipv6Label),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onChanged: (value) => _onDataChanged(
        context,
        enableIpv6: value,
      ),
    ),
  ];

  List<Widget> _keyFields(BuildContext context) => [
    CustomTextField(
      value: _formData.ipAddress,
      label: context.ln.enterIpAddressLabel,
      hint: context.ln.enterIpAddressHint,
      helper: context.ln.enterIpAddressHelper,
      onChanged: (ipAddress) => _onDataChanged(
        context,
        ipAddress: ipAddress,
      ),
      error: _error(PresentationFieldName.ipAddress),
    ),
    CustomTextField(
      value: _formData.domain,
      label: context.ln.enterDomainLabel,
      hint: context.ln.enterDomainHint,
      onChanged: (domain) => _onDataChanged(
        context,
        domain: domain,
      ),
      error: _error(PresentationFieldName.domain),
    ),
    CustomTextField(
      value: _formData.username,
      label: context.ln.username,
      hint: context.ln.enterUsername,
      onChanged: (username) => _onDataChanged(
        context,
        username: username,
      ),
      error: _error(PresentationFieldName.userName),
    ),
    ListenableBuilder(
      listenable: _isPasswordVisibleNotifier,
      builder: (context, _) => CustomTextField.customSuffixIcon(
        value: _formData.password,
        label: context.ln.password,
        hint: context.ln.enterPassword,
        obscureText: !_isPasswordVisibleNotifier.value,
        onChanged: (password) => _onDataChanged(
          context,
          password: password,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _isPasswordVisibleNotifier.value ? AssetIcons.eye : AssetIcons.eyeClosed,
          ),
          onPressed: () => _isPasswordVisibleNotifier.value = !_isPasswordVisibleNotifier.value,
        ),
        error: _error(PresentationFieldName.password),
      ),
    ),
    CustomTextField.customSuffixIcon(
      value: _formData.certificate?.name,
      label: context.ln.pemLabel,
      hint: context.ln.importHint,
      readOnly: true,
      suffixIcon: _formData.certificate != null
          ? CustomIconButton(
              icon: AssetIcons.close,
              onPressed: () => _onClearPemCertificatePressed(
                context,
              ),
            )
          : CustomIconButton(
              icon: AssetIcons.attach,
              onPressed: () => _onSelectPemCertificatePressed(
                context,
              ),
            ),
      error: _error(PresentationFieldName.certificate),
    ),
  ];

  List<Widget> _expertFields(BuildContext context) => [
    CustomDropdownMenu<VpnProtocol>.expanded(
      value: _formData.vpnProtocol,
      values: VpnProtocol.values,
      toText: (value) => value.localized(context),
      labelText: context.ln.protocol,
      onChanged: (protocol) => _onDataChanged(
        context,
        protocol: protocol,
      ),
    ),
    SwitchListTile(
      value: _formData.h2PaddingFrames > 0,
      title: Text(context.ln.h2PaddingLabel),
      subtitle: Text(context.ln.h2PaddingDescription),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onChanged: (value) => _onDataChanged(
        context,
        h2PaddingFrames: value ? ServerData.h2PaddingDefaultFrames : 0,
      ),
    ),
    SwitchListTile(
      value: _formData.blockQuic,
      title: Text(context.ln.blockQuicLabel),
      subtitle: Text(context.ln.blockQuicDescription),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onChanged: (value) => _onDataChanged(
        context,
        blockQuic: value,
      ),
    ),
    CustomTextField(
      value: _formData.customSni,
      label: context.ln.customSniLabel,
      hint: context.ln.customSniHint,
      onChanged: (domain) => _onDataChanged(
        context,
        customSni: ValueData(domain.trim().isEmpty ? null : domain),
      ),
      error: _error(PresentationFieldName.sni),
    ),
    CustomTextField(
      value: _formData.tlsPrefix,
      hint: context.ln.clientRandomHint,
      label: context.ln.clientRandomLabel,
      helper: context.ln.clientRandomHelper,
      counter: const SizedBox.shrink(),
      maxLength: 64,
      onChanged: (tls) => _onDataChanged(
        context,
        clientRandom: ValueData(
          tls.isEmpty ? null : tls,
        ),
      ),
      error: [
        PresentationFieldName.clientRandom,
        PresentationFieldName.clientRandomMask,
        PresentationFieldName.clientRandomValue,
      ].map(_error).nonNulls.firstOrNull,
    ),
  ];

  RoutingProfile _getSelectedRoutingProfile(List<RoutingProfile> availableRoutingProfiles, String routingProfileId) =>
      availableRoutingProfiles.firstWhereOrNull((profile) => profile.id == routingProfileId) ??
      availableRoutingProfiles.firstWhere((profile) => profile.id == RoutingProfileUtils.defaultRoutingProfileId);

  void _onSelectPemCertificatePressed(
    BuildContext context,
  ) => ServerDetailsScope.controllerOf(context, listen: false).pickPemCertificate();

  void _onClearPemCertificatePressed(
    BuildContext context,
  ) => ServerDetailsScope.controllerOf(context, listen: false).clearPemCertificate();

  /// "Like an Android app" (okhttp) only where it is plausible.
  static final _tlsProfiles = [
    ServerData.tlsProfileAuto,
    'chrome',
    'firefox',
    if (Platform.isAndroid) 'okhttp',
    'safari',
  ];

  String _profileName(String profile) => switch (profile) {
    'chrome' => 'Chrome',
    'firefox' => 'Firefox',
    'safari' => 'Safari',
    'okhttp' => 'Android',
    _ => profile,
  };

  String _tlsProfileText(BuildContext context, String profile) => switch (profile) {
    'chrome' => context.ln.tlsProfileChrome,
    'firefox' => context.ln.tlsProfileFirefox,
    'safari' => context.ln.tlsProfileSafari,
    'okhttp' => context.ln.tlsProfileOkhttp,
    _ => context.ln.tlsProfileAuto,
  };

  String _antiDpiModeText(BuildContext context, int mode) => switch (mode) {
    _antiDpiOff => context.ln.antiDpiModeOff,
    ServerData.antiDpiAuto => context.ln.antiDpiModeAuto,
    ServerData.antiDpiCustom => context.ln.antiDpiModeCustom,
    1 => context.ln.antiDpiMode1,
    2 => context.ln.antiDpiMode2,
    3 => context.ln.antiDpiMode3,
    _ => context.ln.antiDpiModeBasic,
  };

  void _onDataChanged(
    BuildContext context, {
    String? serverName,
    String? ipAddress,
    String? domain,
    String? username,
    String? password,
    ValueData<String>? clientRandom,
    bool? enableIpv6,
    bool? antiDpi,
    int? antiDpiMode,
    String? tlsProfile,
    String? antiDpiDesync,
    int? h2PaddingFrames,
    bool? blockQuic,
    bool? ruExit,
    VpnProtocol? protocol,
    String? routingProfileId,
    List<String>? dnsServers,
    ValueData<String>? customSni,
  }) =>
      ServerDetailsScope.controllerOf(
        context,
        listen: false,
      ).changeData(
        serverName: serverName,
        ipAddress: ipAddress,
        domain: domain,
        username: username,
        password: password,
        protocol: protocol,
        clientRandom: clientRandom,
        enableIpv6: enableIpv6,
        antiDpi: antiDpi,
        antiDpiMode: antiDpiMode,
        tlsProfile: tlsProfile,
        antiDpiDesync: antiDpiDesync,
        h2PaddingFrames: h2PaddingFrames,
        blockQuic: blockQuic,
        ruExit: ruExit,
        routingProfileId: routingProfileId,
        dnsServers: dnsServers,
        customSni: customSni,
      );

  @override
  void dispose() {
    _isPasswordVisibleNotifier.dispose();
    super.dispose();
  }
}
