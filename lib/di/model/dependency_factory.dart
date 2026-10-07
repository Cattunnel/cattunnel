import 'package:adguard_logger/adguard_logger.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/common/theme/app_theme.dart';
import 'package:trusttunnel/common/theme/theme_palette.dart';
import 'package:trusttunnel/common/utils/certificate_encoders.dart';
import 'package:trusttunnel/data/database/app_database.dart' as db;
import 'package:trusttunnel/data/datasources/app_split_settings_datasource.dart';
import 'package:trusttunnel/data/datasources/app_state_logging_datasource.dart';
import 'package:trusttunnel/data/datasources/auto_connect_on_launch_settings_datasource.dart';
import 'package:trusttunnel/data/datasources/certificate_datasource.dart';
import 'package:trusttunnel/data/datasources/connection_notifications_settings_datasource.dart';
import 'package:trusttunnel/data/datasources/kill_switch_settings_datasource.dart';
import 'package:trusttunnel/data/datasources/launch_at_login_datasource.dart';
import 'package:trusttunnel/data/datasources/local_sources/app_split_settings_datasource_impl.dart';
import 'package:trusttunnel/data/datasources/local_sources/app_state_logging_datasource_impl.dart';
import 'package:trusttunnel/data/datasources/local_sources/auto_connect_on_launch_settings_datasource_impl.dart';
import 'package:trusttunnel/data/datasources/local_sources/certificate_datasource_impl.dart';
import 'package:trusttunnel/data/datasources/local_sources/connection_notifications_settings_datasource_impl.dart';
import 'package:trusttunnel/data/datasources/local_sources/kill_switch_settings_datasource_impl.dart';
import 'package:trusttunnel/data/datasources/local_sources/logging_settings_datasource_impl.dart';
import 'package:trusttunnel/data/datasources/local_sources/logs_export_destination_datasource_impl.dart';
import 'package:trusttunnel/data/datasources/local_sources/logs_local_source_impl.dart';
import 'package:trusttunnel/data/datasources/local_sources/mtu_settings_datasource_impl.dart';
import 'package:trusttunnel/data/datasources/local_sources/routing_datasource_impl.dart';
import 'package:trusttunnel/data/datasources/local_sources/ru_services_settings_datasource_impl.dart';
import 'package:trusttunnel/data/datasources/local_sources/server_datasource_impl.dart';
import 'package:trusttunnel/data/datasources/local_sources/server_sort_preference_datasource_impl.dart';
import 'package:trusttunnel/data/datasources/local_sources/server_test_timeout_datasource_impl.dart';
import 'package:trusttunnel/data/datasources/local_sources/settings_datasource_impl.dart';
import 'package:trusttunnel/data/datasources/local_sources/subscription_datasource_impl.dart';
import 'package:trusttunnel/data/datasources/logging_settings_datasource.dart';
import 'package:trusttunnel/data/datasources/logs_export_destination_datasource.dart';
import 'package:trusttunnel/data/datasources/logs_local_source.dart';
import 'package:trusttunnel/data/datasources/mtu_settings_datasource.dart';
import 'package:trusttunnel/data/datasources/native_sources/endpoint_ca_resolver.dart';
import 'package:trusttunnel/data/datasources/native_sources/launch_at_login_datasource_impl.dart';
import 'package:trusttunnel/data/datasources/native_sources/open_main_window_on_login_datasource_impl.dart';
import 'package:trusttunnel/data/datasources/native_sources/vpn_datasource_impl.dart';
import 'package:trusttunnel/data/datasources/open_main_window_on_login_datasource.dart';
import 'package:trusttunnel/data/datasources/routing_datasource.dart';
import 'package:trusttunnel/data/datasources/ru_services_settings_datasource.dart';
import 'package:trusttunnel/data/datasources/server_datasource.dart';
import 'package:trusttunnel/data/datasources/server_sort_preference_datasource.dart';
import 'package:trusttunnel/data/datasources/server_test_timeout_datasource.dart';
import 'package:trusttunnel/data/datasources/settings_datasource.dart';
import 'package:trusttunnel/data/datasources/subscription_datasource.dart';
import 'package:trusttunnel/data/datasources/vpn_datasource.dart';
import 'package:trusttunnel/data/domain/subscription_sync_service.dart';
import 'package:trusttunnel/data/ru_lists/ru_lists_service.dart';
import 'package:trusttunnel/feature/app/controller/app_window_controller.dart';
import 'package:trusttunnel/feature/app/controller/macos_app_window_controller.dart';
import 'package:vpn_plugin/deep_link_manager.dart';
import 'package:vpn_plugin/vpn_plugin.dart';

abstract class DependencyFactory {
  abstract final SharedPreferences sharedPreferences;

  abstract final FileLogAppender fileLogAppender;

  abstract final FileLogStorage logStorage;

  ThemeData get lightThemeData;

  ThemeData get darkThemeData;

  VpnPlugin get vpnPlugin;

  DeepLinkManager get deepLinkManager;

  SettingsDataSource get settingsDataSource;

  ServerDataSource get serverDataSource;

  RoutingDataSource get routingDataSource;

  VpnDataSource get vpnDataSource;

  CertificateDataSource get certificateDataSource;

  ConnectionNotificationsSettingsDataSource get connectionNotificationsSettingsDataSource;

  KillSwitchSettingsDataSource get killSwitchSettingsDataSource;

  RuServicesSettingsDataSource get ruServicesSettingsDataSource;

  AppSplitSettingsDataSource get appSplitSettingsDataSource;

  RuListsService get ruListsService;

  LoggingSettingsDataSource get loggingSettingsDataSource;

  AppStateLoggingDataSource get appStateLoggingDataSource;

  LogsLocalSource get exportLogsLocalSource;

  LogsExportDestinationDataSource get logsExportDestinationDataSource;

  LaunchAtLoginDataSource get launchAtLoginDataSource;

  OpenMainWindowOnLoginDataSource get openMainWindowOnLoginDataSource;

  AutoConnectOnLaunchSettingsDataSource get autoConnectOnLaunchSettingsDataSource;

  SubscriptionDataSource get subscriptionDataSource;

  SubscriptionSyncService get subscriptionSyncService;

  MtuSettingsDataSource get mtuSettingsDataSource;

  ServerSortPreferenceDataSource get serverSortPreferenceDataSource;

  ServerTestTimeoutDataSource get serverTestTimeoutDataSource;

  AppWindowController get appWindowController;

  db.AppDatabase get database;
}

class DependencyFactoryImpl implements DependencyFactory {
  @override
  final SharedPreferences sharedPreferences;

  @override
  final FileLogAppender fileLogAppender;

  @override
  final FileLogStorage logStorage;

  DependencyFactoryImpl({
    required this.sharedPreferences,
    required this.fileLogAppender,
    required this.logStorage,
  });

  ThemeData? _lightThemeData;

  ThemeData? _darkThemeData;

  VpnPlugin? _vpnPlugin;

  DeepLinkManager? _deepLinkManager;

  SettingsDataSource? _settingsDataSource;

  ServerDataSource? _serverDataSource;

  RoutingDataSource? _routingDataSource;

  VpnDataSource? _vpnDataSource;

  CertificateDataSource? _certificateDataSource;

  ConnectionNotificationsSettingsDataSource? _connectionNotificationsSettingsDataSource;

  LoggingSettingsDataSource? _loggingSettingsDataSource;

  AppStateLoggingDataSource? _appStateLoggingDataSource;

  LogsLocalSource? _exportLogsLocalSource;

  LogsExportDestinationDataSource? _logsExportDestinationDataSource;

  LaunchAtLoginDataSource? _launchAtLoginDataSource;

  OpenMainWindowOnLoginDataSource? _openMainWindowOnLoginDataSource;

  AutoConnectOnLaunchSettingsDataSource? _autoConnectOnLaunchSettingsDataSource;

  KillSwitchSettingsDataSource? _killSwitchSettingsDataSource;

  RuServicesSettingsDataSource? _ruServicesSettingsDataSource;

  AppSplitSettingsDataSource? _appSplitSettingsDataSource;

  RuListsService? _ruListsService;

  SubscriptionDataSource? _subscriptionDataSource;

  SubscriptionSyncService? _subscriptionSyncService;

  MtuSettingsDataSource? _mtuSettingsDataSource;

  ServerSortPreferenceDataSource? _serverSortPreferenceDataSource;

  ServerTestTimeoutDataSource? _serverTestTimeoutDataSource;

  AppWindowController? _appWindowController;

  db.AppDatabase? _database;

  @override
  ThemeData get lightThemeData => _lightThemeData ??= AppTheme(ThemePalette.light).data;

  @override
  ThemeData get darkThemeData => _darkThemeData ??= AppTheme(ThemePalette.dark).data;

  @override
  VpnPlugin get vpnPlugin => _vpnPlugin ??= VpnPluginImpl();

  @override
  DeepLinkManager get deepLinkManager => _deepLinkManager ??= DeepLinkManagerImpl();

  @override
  SettingsDataSource get settingsDataSource => _settingsDataSource ??= SettingsDataSourceImpl(database: database);

  @override
  ServerDataSource get serverDataSource => _serverDataSource ??= ServerDataSourceImpl(
    database: database,
    deepLinkManager: deepLinkManager,
  );

  @override
  RoutingDataSource get routingDataSource => _routingDataSource ??= RoutingDataSourceImpl(
    database: database,
  );

  @override
  VpnDataSource get vpnDataSource => _vpnDataSource ??= VpnDataSourceImpl(
    vpnPlugin: vpnPlugin,
    killSwitchSettingsDataSource: killSwitchSettingsDataSource,
    mtuSettingsDataSource: mtuSettingsDataSource,
    ruServicesSettingsDataSource: ruServicesSettingsDataSource,
    appSplitSettingsDataSource: appSplitSettingsDataSource,
    ruListsService: ruListsService,
    endpointCaResolver: EndpointCaResolver(preferences: sharedPreferences),
  );

  @override
  CertificateDataSource get certificateDataSource => _certificateDataSource ??= CertificateDataSourceImpl(
    filePicker: FilePicker.platform,
    decoder: const RawCertificateDecoder(),
  );

  @override
  ConnectionNotificationsSettingsDataSource get connectionNotificationsSettingsDataSource =>
      _connectionNotificationsSettingsDataSource ??= ConnectionNotificationsSettingsDataSourceImpl(
        preferences: sharedPreferences,
      );

  @override
  LoggingSettingsDataSource get loggingSettingsDataSource =>
      _loggingSettingsDataSource ??= LoggingSettingsDataSourceImpl(
        preferences: sharedPreferences,
      );

  @override
  AppStateLoggingDataSource get appStateLoggingDataSource =>
      _appStateLoggingDataSource ??= AppStateLoggingDataSourceImpl(
        database: database,
        serverDataSource: serverDataSource,
        routingDataSource: routingDataSource,
        settingsDataSource: settingsDataSource,
        vpnDataSource: vpnDataSource,
        loggingSettingsDataSource: loggingSettingsDataSource,
      );

  @override
  LogsLocalSource get exportLogsLocalSource => _exportLogsLocalSource ??= LogsLocalSourceImpl(
    logAppender: fileLogAppender,
    appStateLoggingDataSource: appStateLoggingDataSource,
    filePicker: FilePicker.platform,
    vpnPlugin: vpnPlugin,
    sharedPreferences: sharedPreferences,
  );

  @override
  LogsExportDestinationDataSource get logsExportDestinationDataSource =>
      _logsExportDestinationDataSource ??= LogsExportDestinationDataSourceImpl(
        filePicker: FilePicker.platform,
      );

  @override
  LaunchAtLoginDataSource get launchAtLoginDataSource => _launchAtLoginDataSource ??= LaunchAtLoginDataSourceImpl();

  @override
  OpenMainWindowOnLoginDataSource get openMainWindowOnLoginDataSource =>
      _openMainWindowOnLoginDataSource ??= OpenMainWindowOnLoginDataSourceImpl();

  @override
  AutoConnectOnLaunchSettingsDataSource get autoConnectOnLaunchSettingsDataSource =>
      _autoConnectOnLaunchSettingsDataSource ??= AutoConnectOnLaunchSettingsDataSourceImpl(
        preferences: sharedPreferences,
      );

  @override
  KillSwitchSettingsDataSource get killSwitchSettingsDataSource =>
      _killSwitchSettingsDataSource ??= KillSwitchSettingsDataSourceImpl(
        preferences: sharedPreferences,
      );

  @override
  RuServicesSettingsDataSource get ruServicesSettingsDataSource =>
      _ruServicesSettingsDataSource ??= RuServicesSettingsDataSourceImpl(
        preferences: sharedPreferences,
      );

  @override
  RuListsService get ruListsService => _ruListsService ??= RuListsService();

  @override
  AppSplitSettingsDataSource get appSplitSettingsDataSource =>
      _appSplitSettingsDataSource ??= AppSplitSettingsDataSourceImpl(
        preferences: sharedPreferences,
      );

  @override
  SubscriptionDataSource get subscriptionDataSource =>
      _subscriptionDataSource ??= SubscriptionDataSourceImpl(database: database);

  @override
  SubscriptionSyncService get subscriptionSyncService =>
      _subscriptionSyncService ??= SubscriptionSyncService(
        subscriptionDataSource: subscriptionDataSource,
        serverDataSource: serverDataSource,
      );

  @override
  MtuSettingsDataSource get mtuSettingsDataSource =>
      _mtuSettingsDataSource ??= MtuSettingsDataSourceImpl(
        preferences: sharedPreferences,
      );

  @override
  ServerSortPreferenceDataSource get serverSortPreferenceDataSource =>
      _serverSortPreferenceDataSource ??= ServerSortPreferenceDataSourceImpl(
        preferences: sharedPreferences,
      );

  @override
  ServerTestTimeoutDataSource get serverTestTimeoutDataSource =>
      _serverTestTimeoutDataSource ??= ServerTestTimeoutDataSourceImpl(
        preferences: sharedPreferences,
      );

  @override
  AppWindowController get appWindowController => _appWindowController ??= switch (defaultTargetPlatform) {
    TargetPlatform.macOS => MacOSAppWindowController(),
    _ => throw UnsupportedError('AppWindowController is not supported on ${defaultTargetPlatform.name}'),
  };

  @override
  db.AppDatabase get database => _database ??= db.AppDatabase();
}
