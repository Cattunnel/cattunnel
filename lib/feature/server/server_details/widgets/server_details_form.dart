import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trusttunnel/common/assets/asset_icons.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/error/model/enum/presentation_field_name.dart';
import 'package:trusttunnel/common/error/model/presentation_field.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/extensions/locale_enum_extension.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/models/value_data.dart';
import 'package:trusttunnel/common/utils/routing_profile_utils.dart';
import 'package:trusttunnel/common/utils/validation_utils.dart';
import 'package:trusttunnel/data/model/routing_profile.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/vpn_protocol.dart';
import 'package:trusttunnel/feature/server/server_details/widgets/scope/server_details_scope.dart';
import 'package:trusttunnel/feature/server/server_details/widgets/scope/server_details_scope_aspect.dart';
import 'package:trusttunnel/feature/server/server_details/widgets/server_help_sheet.dart';
import 'package:trusttunnel/feature/server/server_details/widgets/subscription_override_dialog.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/feature/vpn/domain/tls_profile_auto.dart';
import 'package:trusttunnel/widgets/buttons/custom_icon_button.dart';
import 'package:trusttunnel/widgets/inputs/custom_text_field.dart';
import 'package:trusttunnel/widgets/menu/custom_dropdown_menu.dart';
import 'package:trusttunnel/widgets/y2k/marsik_image.dart';
import 'package:vpn_plugin/domain/cattail_settings.dart';
import 'package:vpn_plugin/domain/configuration_codec.dart';
import 'package:vpn_plugin/domain/desync_string.dart';
import 'package:vpn_plugin/domain/rotation_addresses.dart';
import 'package:vpn_plugin/models/endpoint.dart';

/// The groups of the server form. [bypass] is what people change; the rest
/// starts collapsed (except [key] for a new server, which needs it filled).
/// [travel] holds the Russian-exit switch - rarely needed, and its text only
/// makes sense for a server in Russia, so it stays out of [bypass].
enum _Section { bypass, routing, key, expert, travel }

enum _ServerTab { settings, rotation }

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
  _ServerTab _tab = _ServerTab.settings;

  /// What "auto" fingerprint means on this device, shown under the menu.
  TlsProfileChoice? _autoTls;
  bool _redetectingTls = false;

  /// The text of a number field the user is in the middle of typing: the
  /// model holds a whole number, but an empty or half-typed field must not
  /// jump back to the old value.
  final Map<String, String> _numberDrafts = {};

  /// The value of a number field the user has emptied. The engine never sees
  /// it: the save is stopped until the field holds a number.
  static const _numberNotSet = -1;

  /// What "keepalive on" means in the form: a ping every 60..240 seconds.
  static const _keepaliveDefaultSecs = 60;

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
    PresentationFieldName.tlsAuthKey: _Section.expert,
    PresentationFieldName.cattail: _Section.expert,
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
      if (fieldErrors.any(
        (error) =>
            error.fieldName == PresentationFieldName.rotationAddresses ||
            error.fieldName == PresentationFieldName.rotationTerm,
      )) {
        _tab = _ServerTab.rotation;
      }
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
          if (_formData.subscriptionOverride)
            Row(
              children: [
                const MarsikImage(AssetImages.catAlert, height: 32),
                const SizedBox(width: 8),
                Expanded(child: Text(context.ln.subscriptionDifferent)),
              ],
            ),
          SegmentedButton<_ServerTab>(
            segments: [
              ButtonSegment(value: _ServerTab.settings, label: Text(context.ln.serverTabSettings)),
              ButtonSegment(value: _ServerTab.rotation, label: Text(context.ln.serverTabRotation)),
            ],
            selected: {_tab},
            onSelectionChanged: (selected) => setState(() => _tab = selected.single),
          ),
          if (_tab == _ServerTab.settings) ...[
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
          ] else
            ..._rotationFields(context),
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

  Future<bool?> _rotationOverride(BuildContext context) async {
    if (!SubscriptionChallenge.needsChallenge(_formData)) return false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => const SubscriptionOverrideDialog(),
    );
    if (accepted != true || !context.mounted) return null;
    return true;
  }

  List<Widget> _rotationFields(BuildContext context) {
    final entries = _formData.rotationAddresses;
    final port = RotationAddresses.portOf(_formData.ipAddress);

    Future<void> change({List<String>? addresses, bool? enabled, int? min, int? max}) async {
      final override = await _rotationOverride(context);
      if (override == null || !context.mounted) return;
      _onDataChanged(
        context,
        rotationAddresses: addresses,
        rotationEnabled: enabled,
        rotationMinSecs: min,
        rotationMaxSecs: max,
        subscriptionOverride: override ? true : null,
      );
    }

    // An entry is "host:port sni1 sni2": the address and its own names.
    String addressOf(String entry) => entry.trim().split(RegExp(r'\s+')).first;
    String namesOf(String entry) => entry.trim().split(RegExp(r'\s+')).skip(1).join(' ');
    List<String> replaced(int index, String address, String names) =>
        [...entries]..[index] = [address.trim(), names.trim()].where((part) => part.isNotEmpty).join(' ');

    return [
      SwitchListTile(
        value: _formData.rotationEnabled,
        title: Text(context.ln.rotationSwitch),
        subtitle: Text(context.ln.rotationHint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        onChanged: (enabled) => change(enabled: enabled),
      ),
      if (entries.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(context.ln.rotationEmpty),
        ),
      for (var index = 0; index < entries.length; index++)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CustomTextField(
                    key: ValueKey('rotation-address-$index'),
                    value: addressOf(entries[index]),
                    label: '${context.ln.rotationAddressLabel} ${index + 1}',
                    hint: context.ln.rotationAddressHint,
                    error:
                        _formData.rotationEnabled &&
                            RotationAddresses.normalize(addressOf(entries[index]), port) == null
                        ? context.ln.rotationAddressError
                        : null,
                    onChanged: (value) => change(addresses: replaced(index, value, namesOf(entries[index]))),
                  ),
                  CustomTextField(
                    key: ValueKey('rotation-sni-$index'),
                    value: namesOf(entries[index]),
                    label: context.ln.rotationSniLabel,
                    hint: context.ln.rotationSniHint,
                    error:
                        _formData.rotationEnabled &&
                            RotationAddresses.parseEntry(entries[index], port) == null &&
                            RotationAddresses.normalize(addressOf(entries[index]), port) != null
                        ? context.ln.rotationSniError
                        : null,
                    onChanged: (value) => change(addresses: replaced(index, addressOf(entries[index]), value)),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: context.ln.rotationRemoveAddress,
              onPressed: () => change(addresses: [...entries]..removeAt(index)),
              icon: const Icon(Icons.remove_circle_outline),
            ),
          ],
        ),
      if (_error(PresentationFieldName.rotationAddresses) case final error?)
        Text(error, style: context.textTheme.bodySmall?.copyWith(color: context.colors.error)),
      TextButton.icon(
        onPressed: entries.length >= RotationAddresses.maxCount ? null : () => change(addresses: [...entries, '']),
        icon: const Icon(Icons.add),
        label: Text(context.ln.rotationAddAddress),
      ),
      if (entries.length >= RotationAddresses.maxCount)
        Text(context.ln.rotationMaxAddresses, style: context.textTheme.bodySmall),
      const SizedBox(height: 8),
      Text(context.ln.rotationTermTitle, style: context.textTheme.titleSmall),
      Text(context.ln.rotationTermHint, style: context.textTheme.bodySmall),
      _numberField(
        context,
        key: 'rotationMin',
        label: context.ln.rotationMinLabel,
        value: _formData.rotationMinSecs,
        min: 0,
        max: RotationAddresses.maxSecs,
        onChanged: (value) => change(min: value),
      ),
      _numberField(
        context,
        key: 'rotationMax',
        label: context.ln.rotationMaxLabel,
        value: _formData.rotationMaxSecs,
        min: 0,
        max: RotationAddresses.maxSecs,
        onChanged: (value) => change(max: value),
      ),
      if (_error(PresentationFieldName.rotationTerm) case final error?)
        Text(error, style: context.textTheme.bodySmall?.copyWith(color: context.colors.error)),
    ];
  }

  /// CatTail, right under NineLives and switched the same way: the
  /// subscription gives the default, a change by hand stays with "above the
  /// subscription" like every other expert field.
  Widget _disguiseMenu(BuildContext context) => CustomDropdownMenu<bool>.expanded(
    value: _formData.cattailEnabled,
    values: const [false, true],
    toText: (cattail) => cattail ? context.ln.disguiseCattail : context.ln.disguiseQuiet,
    labelText: context.ln.serverDisguiseLabel,
    errorText: _error(PresentationFieldName.cattail),
    onChanged: (cattail) => _onDataChanged(context, cattailEnabled: cattail ?? false),
  );

  List<Widget> _cattailFields(BuildContext context) => [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        _formData.xhttpEnabled ? context.ln.disguiseCattailNoNineLives : context.ln.disguiseCattailHint,
        style: context.textTheme.bodySmall,
      ),
    ),
    CustomTextField(
      value: _formData.cattailPorts,
      label: context.ln.cattailPortsLabel,
      hint: context.ln.cattailPortsHint,
      error: CattailSettings.normalizePorts(_formData.cattailPorts) == null ? context.ln.cattailPortsError : null,
      onChanged: (value) => _onDataChanged(context, cattailPorts: value.trim()),
    ),
    CustomTextField(
      value: _formData.cattailKey,
      label: context.ln.cattailKeyLabel,
      hint: context.ln.cattailKeyHint,
      error: CattailSettings.isValidKey(_formData.cattailKey.trim()) ? null : context.ln.cattailKeyError,
      onChanged: (value) => _onDataChanged(context, cattailKey: value.trim()),
    ),
    CustomTextField(
      value: _formData.cattailPattern,
      label: context.ln.cattailPatternLabel,
      hint: context.ln.cattailPatternHint,
      maxLines: 4,
      minLines: 1,
      error: CattailSettings.normalizePattern(_formData.cattailPattern) == null ? context.ln.cattailPatternError : null,
      onChanged: (value) => _onDataChanged(context, cattailPattern: value),
    ),
  ];

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
        onChanged: (mode) async {
          if (mode == null) return;
          var aboveSubscription = false;
          if (SubscriptionChallenge.needsChallenge(_formData)) {
            // The bypass of a subscription key changes only above the
            // subscription: the question first, then the key keeps the choice.
            final accepted = await showDialog<bool>(
              context: context,
              builder: (_) => const SubscriptionOverrideDialog(),
            );
            if (accepted != true || !context.mounted) {
              if (mounted) setState(() {});
              return;
            }
            aboveSubscription = true;
          }
          _onDataChanged(
            context,
            antiDpi: mode != _antiDpiOff,
            antiDpiMode: mode == _antiDpiOff ? null : mode,
            subscriptionOverride: aboveSubscription ? true : null,
          );
        },
      ),
      if (choice == ServerData.antiDpiCustom) ..._desyncFields(context),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CustomDropdownMenu<String>.expanded(
            // 1.5.9.1: chrome_canary sends the same ClientHello as chrome (engine), so it is shown and saved as chrome.
            value: _formData.tlsProfile == 'chrome_canary'
                ? 'chrome'
                : _tlsProfiles.contains(_formData.tlsProfile)
                ? _formData.tlsProfile
                : ServerData.tlsProfileAuto,
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

  Future<void> _restoreSubscription() async {
    final controller = ServerDetailsScope.controllerOf(context, listen: false);
    final id = controller.id;
    if (id == null) return;
    final dependencies = context.dependencyFactory;
    try {
      await dependencies.subscriptionSyncService.restoreServer(Server(id: id, serverData: _formData));
      if (!mounted) return;
      controller.fetchServer();
      ServersScope.controllerOf(context, listen: false).fetchServers();
    } on Object {
      if (mounted) context.showInfoSnackBar(message: context.ln.subscriptionRestoreFailed);
    }
  }

  List<Widget> _expertFields(BuildContext context) => [
    if (_formData.subscriptionId != null) ...[
      SwitchListTile(
        title: Text(context.ln.subscriptionOverride),
        subtitle: Text(context.ln.subscriptionOverrideDescription),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        value: _formData.subscriptionOverride,
        onChanged: (value) async {
          if (!value) {
            await _restoreSubscription();
            return;
          }
          final accepted = await showDialog<bool>(context: context, builder: (_) => const SubscriptionOverrideDialog());
          if (accepted == true && context.mounted) _onDataChanged(context, subscriptionOverride: true);
        },
      ),
      if (_formData.subscriptionOverride)
        TextButton(
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
          onPressed: _restoreSubscription,
          child: Text(context.ln.subscriptionRestore),
        ),
    ],
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
    if (_formData.h2PaddingFrames > 0) ..._paddingFields(context),
    SwitchListTile(
      value: _formData.keepaliveIntervalSecs > 0,
      title: Text(context.ln.expertKeepaliveLabel),
      subtitle: Text(context.ln.expertKeepaliveDescription),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onChanged: (value) => _onDataChanged(
        context,
        keepaliveIntervalSecs: value ? _keepaliveDefaultSecs : 0,
      ),
    ),
    if (_formData.keepaliveIntervalSecs > 0) ..._keepaliveFields(context),
    SwitchListTile(
      value: _formData.xhttpEnabled,
      title: Text(context.ln.expertXhttpLabel),
      subtitle: Text(context.ln.expertXhttpDescription),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onChanged: (value) => _onDataChanged(
        context,
        xhttpEnabled: value,
      ),
    ),
    if (_formData.xhttpEnabled) ...[
      ..._xhttpFields(context),
      _nineLivesEncryptionSwitch(context),
    ],
    _disguiseMenu(context),
    if (_formData.cattailEnabled) ..._cattailFields(context),
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
      value: _formData.tlsAuthKey,
      hint: context.ln.tlsAuthKeyHint,
      label: context.ln.tlsAuthKeyLabel,
      helper: context.ln.tlsAuthKeyHelper,
      counter: const SizedBox.shrink(),
      maxLength: 128,
      onChanged: (key) => _onDataChanged(context, tlsAuthKey: key),
      error: _error(PresentationFieldName.tlsAuthKey),
    ),
  ];

  /// The numbers of the traffic shaper: how many frames of a stream get the
  /// junk, how big the junk is and how much of it a stream and a session may
  /// spend. The engine draws the frame count at random between the minimum
  /// and the maximum.
  List<Widget> _paddingFields(BuildContext context) => [
    _numberField(
      context,
      key: 'paddingFrames',
      label: context.ln.expertPaddingFramesLabel,
      value: _formData.h2PaddingFrames,
      min: 1,
      max: ConfigurationCodecKeys.h2PaddingFramesMax,
      onChanged: (value) => _onDataChanged(context, h2PaddingFrames: value),
    ),
    _numberField(
      context,
      key: 'paddingFramesMin',
      label: context.ln.expertPaddingFramesMinLabel,
      value: _formData.h2PaddingFramesMin,
      min: 0,
      max: ConfigurationCodecKeys.h2PaddingFramesMinMax,
      onChanged: (value) => _onDataChanged(context, h2PaddingFramesMin: value),
    ),
    SwitchListTile(
      value: _formData.h2PaddingPerStream,
      title: Text(context.ln.expertPaddingPerStreamLabel),
      subtitle: Text(context.ln.expertPaddingPerStreamDescription),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onChanged: (value) => _onDataChanged(
        context,
        h2PaddingPerStream: value,
      ),
    ),
    _numberField(
      context,
      key: 'paddingMinBytes',
      label: context.ln.expertPaddingMinBytesLabel,
      value: _formData.h2PaddingMinBytes,
      min: 0,
      max: ConfigurationCodecKeys.h2PaddingBytesMax,
      onChanged: (value) => _onDataChanged(context, h2PaddingMinBytes: value),
    ),
    _numberField(
      context,
      key: 'paddingMaxBytes',
      label: context.ln.expertPaddingMaxBytesLabel,
      value: _formData.h2PaddingMaxBytes,
      min: 0,
      max: ConfigurationCodecKeys.h2PaddingBytesMax,
      onChanged: (value) => _onDataChanged(context, h2PaddingMaxBytes: value),
    ),
    _numberField(
      context,
      key: 'paddingStreamBytes',
      label: context.ln.expertPaddingStreamBytesLabel,
      value: _formData.h2PaddingStreamBytes,
      min: 0,
      max: ConfigurationCodecKeys.h2PaddingBytesBudgetMax,
      onChanged: (value) => _onDataChanged(context, h2PaddingStreamBytes: value),
    ),
    _numberField(
      context,
      key: 'paddingSessionBytes',
      label: context.ln.expertPaddingSessionBytesLabel,
      value: _formData.h2PaddingSessionBytes,
      min: 0,
      max: ConfigurationCodecKeys.h2PaddingBytesBudgetMax,
      onChanged: (value) => _onDataChanged(context, h2PaddingSessionBytes: value),
    ),
  ];

  /// The keepalive of an idle session: how often the client reminds the
  /// server that the session is still wanted, with what signal and how long
  /// the session may live without a signal.
  List<Widget> _keepaliveFields(BuildContext context) => [
    _numberField(
      context,
      key: 'keepaliveInterval',
      label: context.ln.expertKeepaliveIntervalLabel,
      hint: context.ln.expertKeepaliveIntervalHint,
      value: _formData.keepaliveIntervalSecs,
      min: 1,
      max: ConfigurationCodecKeys.keepaliveIntervalSecsMax,
      onChanged: (value) => _onDataChanged(context, keepaliveIntervalSecs: value),
    ),
    CustomDropdownMenu<String>.expanded(
      value: Endpoint.keepaliveSignals.contains(_formData.keepaliveSignal)
          ? _formData.keepaliveSignal
          : Endpoint.keepaliveSignals.first,
      values: Endpoint.keepaliveSignals,
      toText: (signal) => _keepaliveSignalText(context, signal),
      labelText: context.ln.expertKeepaliveSignalLabel,
      onChanged: (signal) {
        if (signal == null) return;
        _onDataChanged(context, keepaliveSignal: signal);
      },
    ),
    _numberField(
      context,
      key: 'sessionLifetime',
      label: context.ln.expertSessionLifetimeLabel,
      hint: context.ln.expertSessionLifetimeHint,
      value: _formData.sessionLifetimeSecs,
      min: 0,
      max: ConfigurationCodecKeys.sessionLifetimeSecsMax,
      onChanged: (value) => _onDataChanged(context, sessionLifetimeSecs: value),
    ),
  ];

  /// NineLives: the XHTTP body is encrypted inside TLS with the key from the
  /// subscription. Off keeps the key but does not send it to the engine, so
  /// only TLS protects the tunnel. Without a key there is nothing to switch.
  Widget _nineLivesEncryptionSwitch(BuildContext context) {
    final hasKey = _formData.xhttpServerKey.isNotEmpty;

    return SwitchListTile(
      value: hasKey && _formData.xhttpEncryptionEnabled,
      title: Text(context.ln.expertNineLivesEncryptionLabel),
      subtitle: Text(
        hasKey ? context.ln.expertNineLivesEncryptionDescription : context.ln.expertNineLivesEncryptionNoKey,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onChanged: hasKey
          ? (value) => _onDataChanged(
              context,
              xhttpEncryptionEnabled: value,
            )
          : null,
    );
  }

  /// The XHTTP transport: the path prefix the requests go to.
  List<Widget> _xhttpFields(BuildContext context) {
    final path = _formData.xhttpPath;
    final wrongPath = path.isNotEmpty && !path.startsWith('/');

    return [
      CustomTextField(
        value: path,
        label: context.ln.expertXhttpPathLabel,
        hint: context.ln.expertXhttpPathHint,
        onChanged: (value) => _onDataChanged(
          context,
          xhttpPath: value.trim(),
        ),
        error: wrongPath ? context.ln.expertPathWrong : null,
      ),
    ];
  }

  /// A number the user types: only digits, the range is checked while
  /// typing, and the value the engine may take is written under the label.
  ///
  /// The text the user is in the middle of writing is kept aside, so an
  /// empty field does not jump back to the old number while the person is
  /// still typing.
  Widget _numberField(
    BuildContext context, {
    required String key,
    required String label,
    required int value,
    required int min,
    required int max,
    String? hint,
    required ValueChanged<int> onChanged,
  }) {
    final draft = _numberDrafts[key];
    final text = draft ?? value.toString();
    final empty = text.trim().isEmpty;
    final outOfRange = value < min || value > max;

    return CustomTextField(
      value: text,
      label: label,
      hint: hint,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      counter: const SizedBox.shrink(),
      onChanged: (value) {
        _numberDrafts[key] = value;
        final parsed = int.tryParse(value.trim());
        if (parsed == null) {
          // Nothing to write yet: the field stays as it is, the error shows.
          onChanged(_numberNotSet);
          return;
        }
        _numberDrafts.remove(key);
        onChanged(parsed);
      },
      error: empty
          ? context.ln.expertNumberWrong
          : outOfRange
          ? context.ln.expertNumberOutOfRange(min, max)
          : null,
    );
  }

  String _keepaliveSignalText(BuildContext context, String signal) => switch (signal) {
    'ping' => context.ln.expertKeepaliveSignalPing,
    _ => context.ln.expertKeepaliveSignalCheck,
  };

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
  ];

  String _profileName(String profile) => switch (profile) {
    'chrome' => 'Chrome 157',
    'chrome_canary' => 'Chrome 157',
    'firefox' => 'Firefox 160',
    'okhttp' => 'Android',
    _ => profile,
  };

  String _tlsProfileText(BuildContext context, String profile) => switch (profile) {
    'chrome' => context.ln.tlsProfileChrome,
    'chrome_canary' => context.ln.tlsProfileChrome,
    'firefox' => context.ln.tlsProfileFirefox,
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
    bool? subscriptionOverride,
    bool? antiDpi,
    int? antiDpiMode,
    String? tlsProfile,
    String? tlsAuthKey,
    String? antiDpiDesync,
    int? h2PaddingFrames,
    int? h2PaddingFramesMin,
    bool? h2PaddingPerStream,
    int? h2PaddingMinBytes,
    int? h2PaddingMaxBytes,
    int? h2PaddingStreamBytes,
    int? h2PaddingSessionBytes,
    int? keepaliveIntervalSecs,
    String? keepaliveSignal,
    int? sessionLifetimeSecs,
    List<String>? rotationAddresses,
    bool? rotationEnabled,
    int? rotationMinSecs,
    int? rotationMaxSecs,
    bool? cattailEnabled,
    String? cattailPorts,
    String? cattailKey,
    String? cattailPattern,
    bool? xhttpEnabled,
    String? xhttpPath,
    bool? xhttpEncryptionEnabled,
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
        subscriptionOverride: subscriptionOverride,
        antiDpi: antiDpi,
        antiDpiMode: antiDpiMode,
        tlsProfile: tlsProfile,
        tlsAuthKey: tlsAuthKey,
        antiDpiDesync: antiDpiDesync,
        h2PaddingFrames: h2PaddingFrames,
        h2PaddingFramesMin: h2PaddingFramesMin,
        h2PaddingPerStream: h2PaddingPerStream,
        h2PaddingMinBytes: h2PaddingMinBytes,
        h2PaddingMaxBytes: h2PaddingMaxBytes,
        h2PaddingStreamBytes: h2PaddingStreamBytes,
        h2PaddingSessionBytes: h2PaddingSessionBytes,
        keepaliveIntervalSecs: keepaliveIntervalSecs,
        keepaliveSignal: keepaliveSignal,
        sessionLifetimeSecs: sessionLifetimeSecs,
        rotationAddresses: rotationAddresses,
        rotationEnabled: rotationEnabled,
        rotationMinSecs: rotationMinSecs,
        rotationMaxSecs: rotationMaxSecs,
        cattailEnabled: cattailEnabled,
        cattailPorts: cattailPorts,
        cattailKey: cattailKey,
        cattailPattern: cattailPattern,
        xhttpEnabled: xhttpEnabled,
        xhttpPath: xhttpPath,
        xhttpEncryptionEnabled: xhttpEncryptionEnabled,
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
