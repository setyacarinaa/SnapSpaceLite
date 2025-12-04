#!/usr/bin/env node
// Utility to create or update the admin user in Firebase Auth and Firestore.
// Requirements:
// - Node.js installed
// - A Firebase service account key JSON file
// Usage (PowerShell example):
//   $env:GOOGLE_APPLICATION_CREDENTIALS="D:/path/to/serviceAccountKey.json";
//   $env:ADMIN_EMAIL="snapspacelite@gmail.com";
//   $env:ADMIN_PASSWORD="<your-password>";
//   node scripts/create_admin_user.mjs

import fs from 'fs'
import path from 'path'
import process from 'process'
import { initializeApp, applicationDefault, cert } from 'firebase-admin/app'
import { getAuth } from 'firebase-admin/auth'
import { getFirestore, FieldValue } from 'firebase-admin/firestore'

const log = (msg) => console.log(`[create-admin] ${msg}`)
const error = (msg) => console.error(`[create-admin] ERROR: ${msg}`)

// Read inputs from env or CLI args. Provide a sensible default for the admin email
const DEFAULT_ADMIN_EMAIL = 'snapspacelite@gmail.com'
const args = process.argv.slice(2)
const email = process.env.ADMIN_EMAIL || args[0] || DEFAULT_ADMIN_EMAIL
const password = process.env.ADMIN_PASSWORD || args[1]

if (!email || !password) {
  error('Missing ADMIN_EMAIL or ADMIN_PASSWORD.')
  console.log('Usage: ADMIN_EMAIL=<email> ADMIN_PASSWORD=<password> node scripts/create_admin_user.mjs')
  console.log(`Note: default admin email is ${DEFAULT_ADMIN_EMAIL} if ADMIN_EMAIL not provided.`)
  process.exit(1)
}

// Resolve credentials
let appInitDone = false
try {
  const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS || path.resolve(process.cwd(), 'serviceAccountKey.json')
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS && !fs.existsSync(process.env.GOOGLE_APPLICATION_CREDENTIALS)) {
    log(`WARNING: File path in GOOGLE_APPLICATION_CREDENTIALS not found: ${process.env.GOOGLE_APPLICATION_CREDENTIALS}`)
    log('Fallback ke applicationDefault() (hapus env var jika tetap gagal).')
  }
  if (fs.existsSync(credPath)) {
    const serviceAccount = JSON.parse(fs.readFileSync(credPath, 'utf8'))
    initializeApp({ credential: cert(serviceAccount) })
    appInitDone = true
    log(`Initialized Firebase Admin dengan service account: ${credPath}`)
  }
} catch (e) {
  log('Gagal membaca service account, mencoba applicationDefault() ...')
}

if (!appInitDone) {
  try {
    initializeApp({ credential: applicationDefault() })
    appInitDone = true
    log('Initialized Firebase Admin dengan applicationDefault() credentials')
    log('Pastikan Anda sudah login gcloud atau GOOGLE_APPLICATION_CREDENTIALS menunjuk file yang valid.')
  } catch (e) {
    error(`Failed to initialize Firebase Admin SDK: ${e.message}`)
    error('Perbaikan: Generate key di Firebase Console: Project Settings > Service Accounts > Generate new private key.')
    error('Simpan file misal di ./keys/firebase-sa.json lalu set: $env:GOOGLE_APPLICATION_CREDENTIALS="./keys/firebase-sa.json"')
    process.exit(1)
  }
}

const auth = getAuth()
const db = getFirestore()

async function ensureAdminUser(email, password) {
  log(`Ensuring admin user exists: ${email}`)
  let userRecord
  try {
    userRecord = await auth.getUserByEmail(email)
    log('User already exists, updating password...')
    await auth.updateUser(userRecord.uid, { password })
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      log('User not found, creating a new one...')
      userRecord = await auth.createUser({
        email,
        password,
        emailVerified: true,
        displayName: 'Admin',
        disabled: false,
      })
    } else {
      throw e
    }
  }

  // Set custom claims for admin
  await auth.setCustomUserClaims(userRecord.uid, { system_admin: true })
  log('Custom claim { system_admin: true } set')

  // Upsert Firestore profile
  const userRef = db.collection('users').doc(userRecord.uid)
  await userRef.set(
    {
      uid: userRecord.uid,
      email,
      name: userRecord.displayName || 'Admin',
      role: 'system_admin',
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  )
  log('Firestore user document upserted with role=admin')
}

ensureAdminUser(email, password)
  .then(() => {
    log('Admin user is ready.')
    process.exit(0)
  })
  .catch((e) => {
    error(e?.stack || e?.message || String(e))
    process.exit(1)
  })
