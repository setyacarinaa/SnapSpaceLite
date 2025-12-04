# Ringkasan Perubahan Bahasa Indonesia

## ✅ Perubahan yang Sudah Dilakukan:

### File User (Customer):

1. **profile_screen.dart**

   - ✅ "Profile" → "Profil" (AppBar title)
   - ✅ "Reset Password" → "Reset Kata Sandi"

2. **register_popup.dart**

   - ✅ "User / Customer" → "Pengguna / Pelanggan"

3. **detail_booking_screen.dart**
   - ✅ "Download" → "Unduh"
   - ✅ "Edit" → "Ubah"
   - ✅ "Delete" → "Hapus"

### File Admin Photobooth:

1. **admin_profile_screen.dart**

   - ✅ "Reset Password" → "Atur Ulang Kata Sandi"

2. **admin_booths_screen.dart**
   - ✅ "Tambah Booth" → "Tambah Studio"
   - ✅ "Belum ada data booth." → "Belum ada data studio."

### File Admin Sistem:

1. **admin_users_screen.dart**
   - ✅ "Customer" → "Pelanggan" (filter chip)

---

## ⏳ Perubahan yang Masih Perlu Dilakukan:

### File Admin Photobooth:

#### admin_booths_screen.dart (masih ada):

- Line ~227: "Konfirmasi Hapus" (OK)
- Line ~229: "Hapus booth ini?" → "Hapus studio ini?"
- Line ~245: "Studio dihapus" (OK)
- Line ~250: "Ubah" (OK)
- Line ~251: "Hapus" (OK)
- Line ~340: "Studio" (OK)
- Line ~502: "Booth berhasil disimpan" → "Studio berhasil disimpan"

#### admin_bookings_screen.dart:

- Line ~47: "Anda belum memiliki booth" → "Anda belum memiliki studio"
- Line ~113: "Menunggu Verif" → "Menunggu Verifikasi"
- Line ~606: "Booth" → "Studio"
- Line ~662: "Upload Foto" → "Unggah Foto"

### File Admin Sistem:

#### admin_dashboard.dart:

- Line ~227: "Customers" → "Pelanggan"
- Line ~96: "Verification Stats" → "Statistik Verifikasi"
- Line ~148: "Accounts Photobooth" → "Akun Photobooth"
- Line ~153: "Accounts Customer" → "Akun Pelanggan"
- Line ~228: Sudah OK ("Lihat Verifikasi")

#### admin_verification_screen.dart:

- Line ~160: "Konfirmasi Reject" → "Konfirmasi Tolak"
- Line ~162: "rejected" → "ditolak"
- Line ~171: "Reject" → "Tolak"

#### verification_detail.dart:

- Line ~254: "Accept" → "Terima"
- Line ~254: "Decline" → "Tolak"

#### system_admin_profile_screen.dart:

- Line ~75: "Delete Account" → "Hapus Akun"
- Line ~76: "Are you sure..." → "Apakah Anda yakin..."
- Line ~78: "Cancel" → "Batal"
- Line ~82: "Delete" → "Hapus"
- Line ~104: "Account deleted successfully" → "Akun berhasil dihapus"
- Line ~109: "Failed to delete account" → "Gagal menghapus akun"
- Line ~231: "Delete" → "Hapus"
- Line ~343: "Users" → "Pengguna"
- Line ~370: "All Accounts" → "Semua Akun"
- Line ~370: "Admin Photobooth Accounts" → "Akun Admin Photobooth"
- Line ~370: "Customer Accounts" → "Akun Pelanggan"
- Line ~379: "View All" → "Lihat Semua"
- Line ~379: "Customer" → "Pelanggan"
- Line ~406: "No accounts found" → "Tidak ada akun ditemukan"
- Line ~432: "View" → "Lihat"
- Line ~453: "No admin accounts found" → "Tidak ada akun admin ditemukan"
- Line ~479: "View" → "Lihat"
- Line ~494: "No customer accounts found" → "Tidak ada akun pelanggan ditemukan"
- Line ~520: "View" → "Lihat"

---

## 📝 Catatan Penting:

1. Sebagian besar teks sudah dalam bahasa Indonesia
2. Perubahan utama yang diperlukan adalah:

   - "Booth" → "Studio" (di konteks yang tepat)
   - "Delete" → "Hapus"
   - "View" → "Lihat"
   - "Upload" → "Unggah"
   - "Verification" → "Verifikasi"
   - "Accept" → "Terima"
   - "Decline/Reject" → "Tolak"
   - "Account(s)" → "Akun"
   - "Customer" → "Pelanggan"
   - "Reset Password" → "Atur Ulang Kata Sandi"

3. Hindari mengubah:
   - Nama class, variabel, atau method
   - Komentar kode (boleh dibiarkan bahasa Inggris)
   - Nama field database (tetap bahasa Inggris)
   - Log message internal (boleh dibiarkan bahasa Inggris)

---

## 🔍 Cara Melanjutkan Perubahan:

Gunakan VS Code Find & Replace (Ctrl+Shift+H) dengan opsi:

- Match Case: ON
- Match Whole Word: OFF
- Use Regular Expression: OFF

Cari dan ganti satu per satu untuk memastikan konteks tepat:

### Contoh Pencarian:

```
'Delete'           → 'Hapus'
'View'             → 'Lihat'
'Upload'           → 'Unggah'
'Booth'            → 'Studio' (hati-hati, cek konteks!)
'Customer'         → 'Pelanggan'
'Reset Password'   → 'Atur Ulang Kata Sandi'
```

Pastikan hanya mengubah teks yang ada di dalam:

- Text('...')
- const Text('...')
- label: Text('...')
- title: Text('...')
- hintText: '...'
- labelText: '...'
- Dialog content/title
- SnackBar messages
