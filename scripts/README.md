# Admin provisioning scripts

This folder contains utilities to provision and manage admin users for the Snapspace project.

create_admin_user.mjs
- Purpose: create or update the System Admin account in Firebase Authentication, set a custom claim `system_admin: true`, and upsert the Firestore `users/{uid}` document with `role: 'system_admin'`.
- Requirements:
  - Node.js installed (>=16 recommended).
  - A Firebase service account JSON file with proper permissions (Firebase Admin).

Example PowerShell usage (recommended):
```powershell
# set path to your service account JSON
$env:GOOGLE_APPLICATION_CREDENTIALS='D:\keys\firebase-sa.json'; \
# set the admin email you want to create (defaults to adminsnapspacelite29@gmail.com if omitted)
$env:ADMIN_EMAIL='adminsnapspacelite29@gmail.com'; \
# set the admin password (required)
$env:ADMIN_PASSWORD='adminku290925'; \
# run the script
node .\scripts\create_admin_user.mjs
```

Or pass email/password as CLI args:
```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS='D:\keys\firebase-sa.json'; \
node .\scripts\create_admin_user.mjs adminsnapspacelite29@gmail.com adminku290925
```

Troubleshooting
- If you see "Failed to initialize Firebase Admin SDK", ensure `GOOGLE_APPLICATION_CREDENTIALS` points to a valid service account JSON file, or that you have Application Default Credentials available.
- If the script exits with permission errors, confirm the service account has `Firebase Admin` privileges.

Security note
- Do not commit service account JSON files or plaintext passwords to version control. Use environment variables or a secure secrets manager.

Other scripts
- `set_custom_claim.mjs` — helper to assign custom claims to an existing user (inspect script for usage).
- `reset_user_password.mjs` — helper to reset a user's password via the Admin SDK.

- `set_system_admin_claim.mjs` — helper to set the `system_admin` custom claim on an existing user and upsert their Firestore profile with `role: 'system_admin'`.

Example PowerShell usage for `set_system_admin_claim.mjs`:
```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS='D:\keys\firebase-sa.json'; $env:ADMIN_EMAIL='adminsnapspacelite29@gmail.com'; node .\scripts\set_system_admin_claim.mjs
```

`verify_admin.mjs`
- Purpose: Verify an admin user's Auth record, custom claims, and Firestore profile `users/{uid}`.
- Usage example:
```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS='D:\keys\firebase-sa.json'; node .\scripts\verify_admin.mjs adminsnapspacelite29@gmail.com
```

This script prints the Auth user UID, any custom claims (e.g., `system_admin`), and the Firestore document contents so you can confirm provisioning succeeded.

If you want, I can also add a one-line PowerShell helper that prompts for the password so you don't set it in the environment, or create a small wrapper that reads the service account and runs the script for you.
