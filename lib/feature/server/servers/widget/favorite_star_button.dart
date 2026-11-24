import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';

/// Star on a server row: one tap marks or unmarks the server as a favorite.
class FavoriteStarButton extends StatelessWidget {
  final Server server;

  const FavoriteStarButton({super.key, required this.server});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: server.favorite ? context.ln.favoriteRemoveTooltip : context.ln.favoriteAddTooltip,
    visualDensity: VisualDensity.compact,
    icon: Icon(
      server.favorite ? Icons.star_rounded : Icons.star_border_rounded,
      size: 24,
      color: server.favorite ? context.colors.accent : context.colors.neutralDark,
    ),
    onPressed: () => ServersScope.controllerOf(
      context,
      listen: false,
    ).toggleFavorite(server.id),
  );
}
