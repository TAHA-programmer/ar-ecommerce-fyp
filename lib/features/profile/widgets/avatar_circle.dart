import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Renders a customer avatar from already-decoded bytes (fetched via an
/// authenticated Storage read elsewhere - see `CustomerProfileState`'s doc
/// comment on why this never takes a URL). Shared by [ProfileView] and
/// [EditProfileView] so both stay pixel-identical and only differ by
/// [radius], per this project's "Reusable Component Rules".
///
/// Three graceful states, never a broken image or a crash: [isLoading] shows
/// a spinner in place of the avatar; [bytes] non-null shows the photo;
/// otherwise shows a person-icon placeholder (covers both "no avatar
/// uploaded yet" and "the fetch failed" - both are visually identical to the
/// user, who has no actionable way to tell them apart anyway).
class AvatarCircle extends StatelessWidget {
  final double radius;
  final Uint8List? bytes;
  final bool isLoading;

  const AvatarCircle({
    super.key,
    required this.radius,
    this.bytes,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.neutralLight,
        child: SizedBox(
          width: radius * 0.6,
          height: radius * 0.6,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final imageBytes = bytes;
    if (imageBytes != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.neutralLight,
        backgroundImage: MemoryImage(imageBytes),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.neutralLight,
      child: Icon(Icons.person, size: radius, color: AppColors.textSecondary),
    );
  }
}
