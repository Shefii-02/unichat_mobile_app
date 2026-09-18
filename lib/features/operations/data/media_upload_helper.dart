import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Media library upload helper — used by MediaLibraryPage. Split out of the former
/// `ops_pages.dart` grab-bag into Operations' own data layer.
Future<bool> pickAndUploadMedia(BuildContext context, {int? folderId}) async {
  final picker = ImagePicker();
  final file = await picker.pickMedia();
  if (file == null) return false;
  try {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: file.name),
      if (folderId != null) 'folder_id': folderId,
    });
    await Api.raw.post('/media-library/upload', data: form);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Uploaded')));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
    return false;
  }
}
