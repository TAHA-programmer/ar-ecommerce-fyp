import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/feedback/app_toast.dart';
import '../models/review_validation.dart';
import '../viewmodels/write_review_viewmodel.dart';
import '../widgets/review_rating_input.dart';

/// The Write/Edit Review form (Ratings/Reviews v1 Stage 7) - reached from
/// Product Details' "Write a Review"/"Edit Your Review" entry, Order
/// Detail's per-item "Rate this product", or the My Reviews list's own
/// "Edit" action. Pops with `true` on a successful submit so the caller can
/// refresh its own review state; pops with nothing (`null`) on cancel/back.
class WriteReviewView extends StatefulWidget {
  final String productTitle;

  const WriteReviewView({super.key, required this.productTitle});

  @override
  State<WriteReviewView> createState() => _WriteReviewViewState();
}

class _WriteReviewViewState extends State<WriteReviewView> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  /// Pre-fills the controllers from a loaded existing review EXACTLY once -
  /// re-running this on every rebuild (e.g. after the customer starts
  /// typing) would clobber their in-progress edits back to the original
  /// text on every keystroke-triggered `notifyListeners()`.
  bool _controllersInitialized = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<WriteReviewViewModel>();

    if (!_controllersInitialized && !viewModel.isLoading) {
      _titleController.text = viewModel.title;
      _bodyController.text = viewModel.body;
      _controllersInitialized = true;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(
          viewModel.isEditing ? 'Edit Your Review' : 'Write a Review',
          style: AppTypography.title,
        ),
      ),
      body: viewModel.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.productTitle,
                      style: AppTypography.headingMedium,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Your rating',
                      style: AppTypography.label.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ReviewRatingInput(
                      rating: viewModel.rating,
                      onChanged: viewModel.setRating,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _titleController,
                      maxLength: ReviewValidation.maxTitleLength,
                      onChanged: viewModel.setTitle,
                      decoration: const InputDecoration(
                        labelText: 'Title (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _bodyController,
                      maxLength: ReviewValidation.maxBodyLength,
                      maxLines: 6,
                      onChanged: viewModel.setBody,
                      decoration: InputDecoration(
                        labelText: 'Your review',
                        alignLabelWithHint: true,
                        border: const OutlineInputBorder(),
                        helperText:
                            'At least ${ReviewValidation.minBodyLength} '
                            'characters',
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: viewModel.isValid && !viewModel.isSubmitting
                            ? () => _submit(context, viewModel)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.white,
                          disabledBackgroundColor: AppColors.neutralMediumLight,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: viewModel.isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.white,
                                ),
                              )
                            : Text(
                                viewModel.isEditing
                                    ? 'Update Review'
                                    : 'Submit Review',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _submit(
    BuildContext context,
    WriteReviewViewModel viewModel,
  ) async {
    final error = await viewModel.submit();
    if (!context.mounted) return;
    if (error != null) {
      AppToast.error(context, error);
      return;
    }
    AppToast.success(
      context,
      viewModel.isEditing
          ? 'Your review has been updated.'
          : 'Thanks for your review!',
    );
    Navigator.pop(context, true);
  }
}
