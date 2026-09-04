import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app/routes/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/feedback/app_toast.dart';

import '../services/checkout_payment_service.dart';
import '../viewmodels/checkout_viewmodel.dart';
import '../widgets/checkout_step_header.dart';
import '../widgets/checkout_address_card.dart';
import '../widgets/checkout_order_item.dart';
import '../widgets/checkout_payment_method_card.dart';
import '../widgets/checkout_price_summary.dart';

class CheckoutPaymentView extends StatefulWidget {
  const CheckoutPaymentView({super.key});

  @override
  State<CheckoutPaymentView> createState() => _CheckoutPaymentViewState();
}

class _CheckoutPaymentViewState extends State<CheckoutPaymentView> {
  CheckoutViewModel? _viewModel;
  bool _navigatedToResult = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final vm = context.read<CheckoutViewModel>();
    if (!identical(vm, _viewModel)) {
      _viewModel?.removeListener(_onViewModelChanged);
      _viewModel = vm;
      _viewModel!.addListener(_onViewModelChanged);
    }
  }

  @override
  void dispose() {
    _viewModel?.removeListener(_onViewModelChanged);
    super.dispose();
  }

  void _onViewModelChanged() {
    final vm = _viewModel;
    if (vm == null || !mounted) return;

    if (vm.phase == CheckoutPhase.succeeded &&
        vm.succeededOrderId != null &&
        !_navigatedToResult) {
      _navigatedToResult = true;
      Navigator.pushNamedAndRemoveUntil(
        context,
        RouteNames.orderResult,
        (route) => route.settings.name == RouteNames.home || route.isFirst,
        arguments: vm.succeededOrderId,
      );
      return;
    }

    final error = vm.error;
    if (error != null && vm.phase != CheckoutPhase.paymentUnavailable) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (vm.lastErrorKind == CheckoutErrorKind.paymentSheetCancelled) {
          AppToast.info(context, error);
        } else {
          AppToast.error(context, error);
        }
        vm.acknowledgeError();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CheckoutViewModel>(
      builder: (context, viewModel, child) {
        return PopScope(
          canPop: !viewModel.isBusy,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              AppToast.info(
                context,
                'Please wait — your payment is being processed.',
              );
            }
          },
          child: Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: Column(
                children: [
                  _buildHeader(context, viewModel),
                  Expanded(child: _buildBody(context, viewModel)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, CheckoutViewModel viewModel) {
    if (viewModel.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (viewModel.isMissingAddress) {
      return _buildErrorState(
        context,
        'No address selected',
        'Return to Delivery Address',
        () => Navigator.pop(context),
      );
    }

    if (viewModel.isEmptyCart) {
      return _buildErrorState(
        context,
        'Your cart is empty',
        'Return to Cart',
        () => Navigator.popUntil(context, ModalRoute.withName(RouteNames.cart)),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),

          // Step 1: Delivery Information
          const CheckoutStepHeader(
            stepNumber: 1,
            title: 'Delivery Information',
          ),
          const SizedBox(height: 12),
          CheckoutAddressCard(
            address: viewModel.selectedAddress!,
            onChange: viewModel.isBusy ? () {} : () => Navigator.pop(context),
          ),
          const SizedBox(height: 24),

          // Step 2: Order Summary
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const CheckoutStepHeader(stepNumber: 2, title: 'Order Summary'),
              Text(
                '${viewModel.totalItems} Items',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.neutralMediumLight),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: viewModel.isBusy
                          ? null
                          : () => Navigator.popUntil(
                              context,
                              ModalRoute.withName(RouteNames.cart),
                            ),
                      child: Text(
                        'Edit Cart',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...viewModel.populatedItems.map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: CheckoutOrderItem(item: item),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Step 3: Payment Method
          const CheckoutStepHeader(stepNumber: 3, title: 'Payment Method'),
          const SizedBox(height: 12),
          const CheckoutPaymentMethodCard(),
          const SizedBox(height: 24),

          // Step 4: Price Summary
          const CheckoutStepHeader(stepNumber: 4, title: 'Price Summary'),
          const SizedBox(height: 12),
          CheckoutPriceSummary(
            subtotal: viewModel.subtotal,
            deliveryFee: viewModel.deliveryFee,
            discount: viewModel.discount,
            total: viewModel.total,
          ),
          const SizedBox(height: 24),

          if (viewModel.unavailableItemsMessage != null) ...[
            Text(
              viewModel.unavailableItemsMessage!,
              style: AppTypography.bodySmall.copyWith(color: AppColors.error),
            ),
            const SizedBox(height: 12),
          ],

          _buildPaymentAction(context, viewModel),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildPaymentAction(
    BuildContext context,
    CheckoutViewModel viewModel,
  ) {
    switch (viewModel.phase) {
      case CheckoutPhase.processingTimeout:
        return _buildProcessingCard(context);
      case CheckoutPhase.paymentUnavailable:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _payButton(
              enabled: false,
              busy: false,
              label: 'Pay Securely With Stripe',
            ),
            const SizedBox(height: 8),
            Text(
              'Card payment is temporarily unavailable. Please try again later.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        );
      case CheckoutPhase.reserving:
        return _payButton(
          enabled: false,
          busy: true,
          label: 'Setting up secure payment…',
        );
      case CheckoutPhase.presenting:
        return _payButton(
          enabled: false,
          busy: true,
          label: 'Complete payment in the sheet',
        );
      case CheckoutPhase.finalizing:
        return _payButton(
          enabled: false,
          busy: true,
          label: 'Finalizing your order…',
        );
      case CheckoutPhase.succeeded:
        return _payButton(
          enabled: false,
          busy: true,
          label: 'Finalizing your order…',
        );
      case CheckoutPhase.idle:
        return _payButton(
          enabled: !viewModel.hasUnavailableItems,
          busy: false,
          label: 'Pay Securely With Stripe',
          onTap: () => viewModel.startCheckout(),
        );
    }
  }

  Widget _payButton({
    required bool enabled,
    required bool busy,
    required String label,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: enabled ? onTap : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        child: busy
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: AppColors.white,
                      strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: AppTypography.bodyLarge.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildProcessingCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neutralLight),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Payment received — finalizing your order',
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'This is taking a little longer than usual. You don\'t need to pay again — your order will appear in My Orders shortly.',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: OutlinedButton(
              onPressed: () => Navigator.pushNamedAndRemoveUntil(
                context,
                RouteNames.orders,
                (route) =>
                    route.settings.name == RouteNames.home || route.isFirst,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Go to My Orders',
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, CheckoutViewModel viewModel) {
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: viewModel.isBusy ? null : () => Navigator.maybePop(context),
            child: Icon(
              Icons.arrow_back,
              color: viewModel.isBusy
                  ? AppColors.textSecondary
                  : AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 16),
          Text('Checkout & Payment', style: AppTypography.headingMedium),
        ],
      ),
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    String message,
    String actionLabel,
    VoidCallback onAction,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(message, style: AppTypography.bodyLarge),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}
