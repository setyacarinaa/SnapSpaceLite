import 'package:cloudinary_public/cloudinary_public.dart';
import 'cloudinary_config.dart';

class CloudinaryService {
  static final CloudinaryPublic _cloudinary = CloudinaryPublic(
    CloudinaryConfig.cloudName,
    CloudinaryConfig.uploadPreset,
    cache: false,
  );

  /// Upload image to Cloudinary and return the secure URL
  ///
  /// Parameters:
  /// - [imagePath]: Local file path of the image to upload
  /// - [folder]: Optional folder name in Cloudinary (e.g., 'snapspace/booths')
  ///
  /// Returns: Secure HTTPS URL of the uploaded image
  static Future<String?> uploadImage(String imagePath, {String? folder}) async {
    try {
      // Upload image to Cloudinary
      final response = await _cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          imagePath,
          folder: folder ?? CloudinaryConfig.boothImagesFolder,
          resourceType: CloudinaryResourceType.Image,
        ),
      );

      // Return the secure URL
      return response.secureUrl;
    } catch (e) {
      print('Error uploading to Cloudinary: $e');
      return null;
    }
  }

  /// Upload multiple images to Cloudinary
  ///
  /// Parameters:
  /// - [imagePaths]: List of local file paths
  /// - [folder]: Optional folder name in Cloudinary
  ///
  /// Returns: List of secure URLs (null entries for failed uploads)
  static Future<List<String?>> uploadMultipleImages(
    List<String> imagePaths, {
    String? folder,
  }) async {
    final List<String?> urls = [];

    for (final path in imagePaths) {
      final url = await uploadImage(path, folder: folder);
      urls.add(url);
    }

    return urls;
  }

  /// Extract public ID from Cloudinary URL
  ///
  /// Example:
  /// URL: https://res.cloudinary.com/demo/image/upload/v1234567890/snapspace/booths/abc123.jpg
  /// Public ID: snapspace/booths/abc123
  static String? extractPublicId(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;

      // Find 'upload' segment and get everything after version
      final uploadIndex = pathSegments.indexOf('upload');
      if (uploadIndex == -1) return null;

      // Skip 'upload' and version (e.g., 'v1234567890')
      final afterUpload = pathSegments.skip(uploadIndex + 2).toList();

      // Join segments and remove extension
      final publicIdWithExt = afterUpload.join('/');
      final lastDotIndex = publicIdWithExt.lastIndexOf('.');
      if (lastDotIndex == -1) return publicIdWithExt;

      return publicIdWithExt.substring(0, lastDotIndex);
    } catch (e) {
      print('Error extracting public ID: $e');
      return null;
    }
  }

  /// Check if URL is from Cloudinary
  static bool isCloudinaryUrl(String url) {
    return url.contains('cloudinary.com') || url.contains('res.cloudinary');
  }
}
