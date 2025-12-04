class CloudinaryConfig {
  // Cloudinary credentials
  // Daftar gratis di: https://cloudinary.com/users/register/free
  // Setelah daftar, ambil Cloud Name dan Upload Preset dari dashboard

  static const String cloudName = 'dqoarpwft'; // Ganti dengan cloud name Anda
  static const String uploadPreset =
      'snapspace_booth_images'; // Ganti dengan upload preset Anda

  // Folder untuk menyimpan gambar (opsional)
  static const String boothImagesFolder = 'snapspace/booths';
  static const String userAvatarsFolder = 'snapspace/avatars';
}
