import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../app/theme_controller.dart';
import '../../widgets/app_overlays.dart';
import '../../widgets/app_toast.dart';

/// Six-digit code entry, used to confirm a patient owns the number they signed
/// up with.
///
/// Pops `true` once the code is accepted, so the caller decides what verifying
/// unlocks rather than this screen hard-coding a destination.
class OtpVerificationScreen extends StatefulWidget {
  /// Where the code was sent — shown back to the patient so a typo in the
  /// previous screen is obvious before they wait for an SMS that cannot come.
  final String destination;

  const OtpVerificationScreen({super.key, required this.destination});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  static const int _length = 6;

  final List<TextEditingController> _controllers =
      List.generate(_length, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(_length, (_) => FocusNode());

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  bool get _isComplete => _code.length == _length;

  /// Advances on entry and retreats on delete, so the six boxes behave like
  /// one field even though each holds a single digit.
  void _onDigitChanged(int index, String value) {
    if (value.length > 1) {
      // A paste or an autofilled SMS code: spread it across the boxes.
      _distribute(value);
      return;
    }
    if (value.isNotEmpty && index < _length - 1) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() {});
  }

  void _distribute(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    for (var i = 0; i < _length; i++) {
      _controllers[i].text = i < digits.length ? digits[i] : '';
    }
    final next = digits.length.clamp(0, _length - 1);
    _focusNodes[next].requestFocus();
    setState(() {});
  }

  Future<void> _verify() async {
    if (!_isComplete) {
      showAppToast(context, 'Please enter all 6 digits of your code.', isError: true);
      return;
    }

    FocusScope.of(context).unfocus();
    showBlockingLoader(context, 'Verifying code, please wait...');

    // TODO: swap for the real check (POST /auth/verify-otp with _code) once
    // the backend is ready, and only pop true on a 2xx response.
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    hideBlockingLoader(context);
    Navigator.pop(context, true);
  }

  void _resend() {
    for (final controller in _controllers) {
      controller.clear();
    }
    _focusNodes.first.requestFocus();
    setState(() {});
    showAppToast(context, 'A new code is on its way to ${widget.destination}.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController(),
      builder: (context, _) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          leading: IconButton(
            icon: const Icon(CupertinoIcons.chevron_back),
            onPressed: () => Navigator.pop(context, false),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 72,
                  width: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withOpacity(0.12),
                  ),
                  child: Icon(
                    CupertinoIcons.device_phone_portrait,
                    size: 32,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Verification Code',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter the 6-digit code we sent to ${widget.destination}.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < _length; i++)
                      Flexible(child: _digitBox(i)),
                  ],
                ),
                const SizedBox(height: 28),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _verify,
                    child: const Text(
                      'Continue',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        "Didn't receive code?",
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: _resend,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Resend Code',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _digitBox(int index) {
    final isFilled = _controllers[index].text.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(right: index == _length - 1 ? 0 : 8),
      child: AspectRatio(
        aspectRatio: 0.82,
        child: TextField(
          controller: _controllers[index],
          focusNode: _focusNodes[index],
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          // A box holds one digit, but paste and SMS autofill hand over all
          // six at once, so the length cap lives in _onDigitChanged instead of
          // an input formatter that would silently drop the rest.
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            counterText: '',
            contentPadding: EdgeInsets.zero,
            filled: true,
            fillColor: AppColors.surface,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isFilled ? AppColors.primary : AppColors.border,
                width: isFilled ? 1.5 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
          onChanged: (value) => _onDigitChanged(index, value),
        ),
      ),
    );
  }
}
