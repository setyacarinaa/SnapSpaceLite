#!/usr/bin/env node
// Helper to set the `system_admin` custom claim for an existing Auth user
// and upsert the Firestore profile with role='system_admin'.
// Usage (PowerShell):
//   $env:GOOGLE_APPLICATION_CREDENTIALS='D:/keys/firebase-sa.json'; $env:ADMIN_EMAIL='admin@example.com'; node .\scripts\set_system_admin_claim.mjs

import fs from 'fs'
import path from 'path'
import process from 'process'
import { initializeApp, applicationDefault, cert } from 'firebase-admin/app'
import { getAuth } from 'firebase-admin/auth'
import { getFirestore, FieldValue } from 'firebase-admin/firestore'

const log = (m) => console.log(`[set-system-admin] ${m}`)
const err = (m) => console.error(`[set-system-admin] ERROR: ${m}`)

const args = process.argv.slice(2)
const email = process.env.ADMIN_EMAIL || args[0]

if (!email) {
  err('Missing ADMIN_EMAIL. Provide via env var or CLI arg.')
  console.log('Usage: ADMIN_EMAIL=<email> node scripts/set_system_admin_claim.mjs')
  process.exit(1)
}

// Initialize admin SDK
let appInit = false
try {
  const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS || path.resolve(process.cwd(), 'serviceAccountKey.json')
  if (fs.existsSync(credPath)) {
    const sa = JSON.parse(fs.readFileSync(credPath, 'utf8'))
    initializeApp({ credential: cert(sa) })
    appInit = true
    log(`Initialized with service account at ${credPath}`)
  }
} catch (e) {
  // continue
}

if (!appInit) {
  try {
    initializeApp({ credential: applicationDefault() })
    appInit = true
    log('Initialized with applicationDefault()')
  } catch (e) {
    err(`Failed to init Firebase Admin: ${e.message || e}`)
    process.exit(1)
  }
}

const auth = getAuth()
const db = getFirestore()

async function run() {
  try {
    log(`Looking up user by email: ${email}`)
    const user = await auth.getUserByEmail(email)
    log(`Found user uid=${user.uid}. Setting custom claim system_admin=true`)
    await auth.setCustomUserClaims(user.uid, { system_admin: true })
    log('Custom claim set')

    const userRef = db.collection('users').doc(user.uid)
    await userRef.set({
      uid: user.uid,
      email: user.email,
      name: user.displayName || 'Admin',
      role: 'system_admin',
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    }, { merge: true })
    log('Firestore upserted with role=system_admin')

    log('Done.')
    process.exit(0)
  } catch (e) {
    err(e?.stack || e?.message || String(e))
    process.exit(1)
  }
}

run()
