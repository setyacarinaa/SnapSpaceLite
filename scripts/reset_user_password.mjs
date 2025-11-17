#!/usr/bin/env node
// Reset a user's password directly using Firebase Admin SDK (no email link).
// Requirements:
// - Node.js
// - firebase-admin (already in package.json)
// - Service account key via GOOGLE_APPLICATION_CREDENTIALS or serviceAccountKey.json in repo root
// Usage (PowerShell):
//   $env:GOOGLE_APPLICATION_CREDENTIALS="D:/path/to/serviceAccountKey.json";
//   node scripts/reset_user_password.mjs <email> <newPassword>

import fs from 'fs'
import path from 'path'
import process from 'process'
import { initializeApp, applicationDefault, cert } from 'firebase-admin/app'
import { getAuth } from 'firebase-admin/auth'

const log = (m) => console.log(`[reset-password] ${m}`)
const error = (m) => console.error(`[reset-password] ERROR: ${m}`)

const [email, newPassword] = process.argv.slice(2)
if (!email || !newPassword) {
  error('Usage: node scripts/reset_user_password.mjs <email> <newPassword>')
  process.exit(1)
}

// init credentials
let inited = false
try {
  const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS || path.resolve(process.cwd(), 'serviceAccountKey.json')
  if (fs.existsSync(credPath)) {
    const key = JSON.parse(fs.readFileSync(credPath, 'utf8'))
    initializeApp({ credential: cert(key) })
    inited = true
    log(`Initialized with service account: ${credPath}`)
  }
} catch (_) {}
if (!inited) {
  try {
    initializeApp({ credential: applicationDefault() })
    inited = true
    log('Initialized with applicationDefault credentials')
  } catch (e) {
    error(`Failed to init Firebase Admin SDK: ${e.message}`)
    process.exit(1)
  }
}

const auth = getAuth()

async function resetPassword(email, newPassword) {
  const user = await auth.getUserByEmail(email)
  await auth.updateUser(user.uid, { password: newPassword })
  log(`Password updated for ${email}`)
}

resetPassword(email, newPassword)
  .then(() => process.exit(0))
  .catch((e) => {
    error(e?.stack || e?.message || String(e))
    process.exit(1)
  })
