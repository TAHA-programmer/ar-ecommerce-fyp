import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/viewmodels/customer_address_state.dart';
import 'package:twin_ar/core/data/mock_address_repository.dart';
import 'package:twin_ar/features/address/viewmodels/address_form_viewmodel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AddressFormViewModel.save', () {
    test('a failed Form.validate() (no Form attached, so '
        'formKey.currentState is null) returns validationFailed - never '
        'success - and never calls the repository. Regression test for the '
        'bug where this used to return null, the SAME value as success, '
        'which AddressFormView treated as "pop the screen"', () async {
      final repository = MockAddressRepository();
      final state = CustomerAddressState(repository);
      final viewModel = AddressFormViewModel(state);

      final result = await viewModel.save();

      expect(result.shouldNavigateBack, isFalse);
      expect(result.shouldShowError, isFalse);
      expect(repository.addresses, isEmpty);
    });
  });
}
