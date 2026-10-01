import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../app/theme_controller.dart';
import '../../services/auth_service.dart';
import '../../widgets/app_overlays.dart';
import '../../widgets/app_toast.dart';

/// Six-digit code entry, used to confirm a patient owns the email address they
/// signed up with.
///
/// The caller has already had Supabase email the code (sign-up, or a resend
/// for an unconfirmed account). This screen checks it with the same
/// `verifyOtp` type 'signup' call the website uses, which confirms the account
/// and opens its session.
///
/// Pops `true` once the code is accepted, so the caller decides what verifying
/// unlocks rather than this screen hard-coding a destination.
class OtpVerificationScreen extends StatefulWidget {
  /// Where the code was sent — shown back to the patient so a typo in the
  /// previous screen is obvious before they wait for an email that cannot come.
  final String destination;

  const OtpVerificationScreen({super.key, required this.destination});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  static const int _length = 6;

  /// Matches the website's resend cooldown. Supabase enforces its own limit
  /// on top, and that error is shown if it is hit anyway.
  static const int _resendCooldownSeconds = 60;

  // Sizes taken from assets/reference_ui/otp.webp, scaled to a 375pt screen.
  static const double _gutter = 16;
  static const double _boxGap = 8;
  static const double _maxBoxWidth = 52;

  /// One real field behind the six boxes. The boxes only draw its value, so
  /// typing, backspace, paste and one-time-code autofill all behave like a
  /// single input instead of six fields passing focus between them.
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocus = FocusNode();

  Timer? _cooldownTimer;
  int _cooldown = 0;
  bool _isResending = false;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(() => setState(() {}));
    _codeFocus.addListener(() => setState(() {}));
    // A code was sent just before this screen opened.
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  String get _code => _codeController.text;

  bool get _isComplete => _code.length == _length;

  Future<void> _verify() async {
    if (_isVerifying) return;
    if (!_isComplete) {
      showAppToast(context, 'Please enter all 6 digits of your code.', isError: true);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isVerifying = true);
    showBlockingLoader(context, 'Verifying code, please wait...');

    final result = await AuthService.verifySignupCode(
      email: widget.destination,
      code: _code,
    );
    if (!mounted) return;
    hideBlockingLoader(context);
    setState(() => _isVerifying = false);

    if (!result.success) {
      _clearCode();
      showAppToast(context, result.message ?? 'Could not verify the code.', isError: true);
      return;
    }
    Navigator.pop(context, true);
  }

  Future<void> _resend() async {
    if (_cooldown > 0 || _isResending) return;

    setState(() => _isResending = true);
    final result = await AuthService.resendSignupCode(widget.destination);
    if (!mounted) return;
    setState(() => _isResending = false);

    if (!result.success) {
      showAppToast(context, result.message ?? 'Could not send a new code.', isError: true);
      return;
    }
    _clearCode();
    _startCooldown();
    showAppToast(context, 'A new code is on its way to ${widget.destination}.');
  }

  void _clearCode() {
    _codeController.clear();
    _codeFocus.requestFocus();
  }

  /// Only ever one timer: a restart cancels the running one first, and
  /// [dispose] cancels whatever is left.
  void _startCooldown() {
    _cooldownTimer?.cancel();
    _cooldown = _resendCooldownSeconds;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _cooldown--);
      if (_cooldown <= 0) timer.cancel();
    });
    if (mounted) setState(() {});
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
        // The content scrolls and the button stays pinned above the keyboard,
        // so a short screen with the keyboard open never overflows.
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(_gutter, 8, _gutter, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Enter 6-digit code',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text.rich(
                        TextSpan(
                          text: 'We sent a verification code to\n',
                          children: [
                            TextSpan(
                              text: widget.destination,
                              style: TextStyle(color: AppColors.primary),
                            ),
                          ],
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _codeRow(),
                      const SizedBox(height: 32),
                      _resendRow(),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(_gutter, 8, _gutter, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: const StadiumBorder(),
                    ),
                    onPressed: _isVerifying ? null : _verify,
                    child: const Text(
                      'Continue',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Six equal boxes filling the row, with no divider between the halves.
  /// They grow up to the reference size and shrink together on narrow phones.
  Widget _codeRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = (constraints.maxWidth - _boxGap * (_length - 1)) / _length;
        final width = fit.clamp(0.0, _maxBoxWidth);
        final height = width * 1.08;
        return SizedBox(
          height: height,
          child: Stack(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < _length; i++)
                    SizedBox(width: width, height: height, child: _digitBox(i)),
                ],
              ),
              // The real input sits over the boxes, invisible, so a tap on any
              // box opens the numeric keyboard and a long-press can paste.
              Positioned.fill(child: _hiddenField()),
            ],
          ),
        );
      },
    );
  }

  Widget _hiddenField() {
    return TextField(
      controller: _codeController,
      focusNode: _codeFocus,
      autofocus: true,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.oneTimeCode],
      // digitsOnly first, so a pasted "123 456" or "Code: 123456" keeps its
      // six digits before the length cap applies.
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(_length),
      ],
      showCursor: false,
      enableSuggestions: false,
      autocorrect: false,
      style: const TextStyle(color: Colors.transparent, fontSize: 1),
      cursorColor: Colors.transparent,
      decoration: const InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        counterText: '',
        contentPadding: EdgeInsets.zero,
      ),
      onSubmitted: (_) => _verify(),
    );
  }

  Widget _digitBox(int index) {
    final code = _code;
    final digit = index < code.length ? code[index] : '';
    // The box the next digit lands in; the last box stays marked once full.
    final isActive = _codeFocus.hasFocus &&
        (index == code.length || (code.length == _length && index == _length - 1));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive ? AppColors.primary : AppColors.border,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Text(
        digit,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _resendRow() {
    final waiting = _cooldown > 0;
    final disabled = waiting || _isResending;
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            "Didn't receive any code? ",
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          GestureDetector(
            onTap: disabled ? null : _resend,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                _isResending
                    ? 'Sending...'
                    : waiting
                        ? 'Resend code (${_cooldown}s)'
                        : 'Resend code',
                style: TextStyle(
                  color: disabled ? AppColors.textSecondary : AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
