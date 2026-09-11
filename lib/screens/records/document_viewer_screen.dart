import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../app/theme_controller.dart';
import '../../models/patient_document.dart';
import '../../repositories/patient_repository.dart';
import '../../widgets/app_toast.dart';

/// Opens an X-ray or document inside the app.
///
/// Images render in a zoomable view and PDFs in an embedded reader, so the
/// patient never leaves the app to look at their own record. Anything the app
/// cannot draw itself is handed to whichever app on the device can.
class DocumentViewerScreen extends StatefulWidget {
  final PatientDocument document;

  const DocumentViewerScreen({super.key, required this.document});

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  final PatientRepository _repository = PatientRepository();

  String? _imageUrl;
  Uint8List? _pdfBytes;
  String? _error;
  bool _isLoading = true;

  PatientDocument get _document => widget.document;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_document.isImage) {
        // The cached link from the list is reused when it is there, so opening
        // a thumbnail the patient can already see costs no extra round trip.
        final url = _repository.previewUrlFor(_document) ??
            await _repository.documentUrl(_document);
        if (url == null) throw StateError('no link');
        if (!mounted) return;
        setState(() {
          _imageUrl = url;
          _isLoading = false;
        });
        return;
      }

      if (_document.isPdf) {
        final bytes = await _repository.documentBytes(_document);
        if (bytes == null) throw StateError('no file');
        if (!mounted) return;
        setState(() {
          _pdfBytes = bytes;
          _isLoading = false;
        });
        return;
      }

      // Nothing the app can draw: hand it off and close.
      await _openExternally();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'We could not open this file. Please try again.';
      });
    }
  }

  Future<void> _openExternally() async {
    final url = await _repository.documentUrl(_document);
    if (url == null) {
      if (mounted) {
        showAppToast(context, 'That file is not available to open.', isError: true);
      }
      return;
    }
    final launched = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      showAppToast(context, 'No app on this device can open that file.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController(),
      builder: (context, _) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(_document.name, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'Open outside the app',
              icon: const Icon(CupertinoIcons.arrow_up_right_square),
              onPressed: _openExternally,
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.exclamationmark_circle,
                  size: 44, color: AppColors.textSecondary),
              const SizedBox(height: 16),
              Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: _open,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    final bytes = _pdfBytes;
    if (bytes != null) {
      return PdfPreview(
        build: (_) => bytes,
        // The patient is reading their own record, not printing a new one;
        // the toolbar's sharing and paper-size controls have nothing to do here.
        allowPrinting: false,
        allowSharing: false,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
      );
    }

    final url = _imageUrl;
    if (url != null) {
      // An X-ray is unreadable at phone width without zoom, so the image is
      // pannable and scalable rather than fitted once and left.
      return InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: Center(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : Center(child: CircularProgressIndicator(color: AppColors.primary)),
            errorBuilder: (context, _, __) => Center(
              child: Text(
                'This image could not be displayed.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
