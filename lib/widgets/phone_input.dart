import 'package:flutter/services.dart';

/// This app only serves Philippine mobile numbers, so the calling code is
/// fixed rather than offered as a choice.
const kPhCountryCode = '+63';

/// PH mobile numbers are commonly typed with their local trunk prefix
/// ("09171234567"), but E.164 drops it — the country code replaces it, not
/// precedes it. Concatenating "+63" directly onto a leading-0 number would
/// produce an invalid "+6309171234567" that send-semaphore-otp rejects, so
/// a leading 0 is stripped live as it's typed (see [phoneInputFormatters])
/// rather than requiring the user to type exactly 10 digits with no zero.
class StripLeadingTrunkZeroFormatter extends TextInputFormatter {
  const StripLeadingTrunkZeroFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.text.startsWith('0')) return newValue;
    final stripped = newValue.text.substring(1);
    final newOffset = (newValue.selection.baseOffset - 1).clamp(
      0,
      stripped.length,
    );
    return TextEditingValue(
      text: stripped,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }
}

/// Digits only, a leading trunk "0" silently dropped, capped at 10 —
/// exactly the digits that follow "+63" in a valid PH mobile E.164 number,
/// so anything left in the field once these formatters have run is either
/// a complete number or an in-progress prefix of one, never something
/// send-semaphore-otp would reject as malformed.
final phoneInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.digitsOnly,
  const StripLeadingTrunkZeroFormatter(),
  LengthLimitingTextInputFormatter(10),
];
