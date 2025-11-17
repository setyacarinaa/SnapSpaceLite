#!/usr/bin/env node
// Verify admin helper: prints Auth user info, custom claims, and Firestore role for an email.
// Usage:
//   $env:GOOGLE_APPLICATION_CREDENTIALS='D:/keys/firebase-sa.json'; node .\scripts\verify_admin.mjs admin@example.com
// or
//   $env:GOOGLE_APPLICATION_CREDENTIALS='D:/keys/firebase-sa.json'; $env:ADMIN_EMAIL='admin@example.com'; node .\scripts\verify_admin.mjs

import fs from 'fs'
import path from 'path'
import process from 'process'
import { initializeApp, applicationDefault, cert } from 'firebase-admin/app'
import { getAuth } from 'firebase-admin/auth'
import { getFirestore } from 'firebase-admin/firestore'

const args = process.argv.slice(2)
const email = process.env.ADMIN_EMAIL || args[0]

if (!email) {
  console.error('Usage: ADMIN_EMAIL=<email> node scripts/verify_admin.mjs OR pass email as arg')
  process.exit(1)
}

let appInit = false
try {
  const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS || path.resolve(process.cwd(), 'serviceAccountKey.json')
  if (fs.existsSync(credPath)) {
    const sa = JSON.parse(fs.readFileSync(credPath, 'utf8'))
    initializeApp({ credential: cert(sa) })
    appInit = true
    console.log(`[verify-admin] Initialized with service account at ${credPath}`)
  }
} catch (e) {
  // fallthrough
}

if (!appInit) {
  try {
    initializeApp({ credential: applicationDefault() })
    appInit = true
    console.log('[verify-admin] Initialized with applicationDefault()')
  } catch (e) {
    console.error('[verify-admin] Failed to initialize Firebase Admin:', e?.message || e)
    process.exit(1)
  }
}

const auth = getAuth()
const db = getFirestore()

async function run() {
  try {
    console.log(`[verify-admin] Looking up user by email: ${email}`)
    const user = await auth.getUserByEmail(email)
    console.log('[verify-admin] Auth user:')
    console.log(`  uid: ${user.uid}`)
    console.log(`  email: ${user.email}`)
    console.log(`  displayName: ${user.displayName || '<none>'}`)
    console.log('  customClaims:', JSON.stringify(user.customClaims || {}, null, 2))

    const doc = await db.collection('users').doc(user.uid).get()
    if (doc.exists) {
      console.log('[verify-admin] Firestore user document found:')
      console.log(JSON.stringify(doc.data(), null, 2))
    } else {
      console.log('[verify-admin] No Firestore user document found for this UID.')
    }

    process.exit(0)
  } catch (e) {
    console.error('[verify-admin] Error:', e?.stack || e?.message || String(e))
    process.exit(1)
  }
}

run()
