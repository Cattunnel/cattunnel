package com.adguard.trusttunnel

import androidx.core.content.FileProvider

/**
 * Own subclass so the update provider (AndroidManifest, UpdateChannel) doesn't
 * collide with adg_share's plain FileProvider in the manifest merge.
 */
class UpdateFileProvider : FileProvider()
