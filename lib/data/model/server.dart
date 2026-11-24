// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:trusttunnel/data/model/server_data.dart';

class Server {
  final String id;
  final ServerData serverData;

  /// Pinned to the top of every list, under any sort.
  final bool favorite;

  /// Index of the server in the subscription response; null for manual servers.
  final int? subscriptionPosition;

  Server({
    required this.id,
    required this.serverData,
    this.favorite = false,
    this.subscriptionPosition,
  });

  @override
  int get hashCode => Object.hashAll([
    id.hashCode,
    serverData.hashCode,
    favorite,
    subscriptionPosition,
  ]);

  @override
  String toString() =>
      'Server(id: $id, serverData: $serverData, favorite: $favorite, subscriptionPosition: $subscriptionPosition)';

  @override
  bool operator ==(covariant Server other) {
    if (identical(this, other)) return true;

    return other.id == id &&
        other.serverData == serverData &&
        other.favorite == favorite &&
        other.subscriptionPosition == subscriptionPosition;
  }

  Server copyWith({
    String? id,
    ServerData? serverData,
    bool? favorite,
    int? subscriptionPosition,
  }) => Server(
    id: id ?? this.id,
    serverData: serverData ?? this.serverData,
    favorite: favorite ?? this.favorite,
    subscriptionPosition: subscriptionPosition ?? this.subscriptionPosition,
  );
}
