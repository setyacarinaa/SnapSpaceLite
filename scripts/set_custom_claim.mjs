#!/usr/bin/env node
// Set a custom claim on a user by email. Usage:
//   $env:GOOGLE_APPLICATION_CREDENTIALS="D:/path/to/serviceAccountKey.json";
//   node scripts/set_custom_claim.mjs user@example.com claimKey claimValue
// Example: node scripts/set_custom_claim.mjs alice@example.com photobooth_admin true

import fs from 'fs'
import path from 'path'
import process from 'process'
import { initializeApp, applicationDefault, cert } from 'firebase-admin/app'
import { getAuth } from 'firebase-admin/auth'

const log = (m) => console.log(`[set-claim] ${m}`)
const error = (m) => console.error(`[set-claim] ERROR: ${m}`)

const [email, claimKey, claimValueRaw] = process.argv.slice(2)
if (!email || !claimKey) {
  error('Usage: node scripts/set_custom_claim.mjs <email> <claimKey> [claimValue]')
  process.exit(1)
}
const claimValue = claimValueRaw === undefined ? true : (claimValueRaw === 'true' ? true : (claimValueRaw === 'false' ? false : claimValueRaw))

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

async function setClaimByEmail(email, claimKey, claimValue) {
  const user = await auth.getUserByEmail(email)
  const existing = user.customClaims || {}
  existing[claimKey] = claimValue
  await auth.setCustomUserClaims(user.uid, existing)
  log(`Set claim ${claimKey}=${claimValue} on ${email}`)
}

setClaimByEmail(email, claimKey, claimValue)
  .then(() => process.exit(0))
  .catch((e) => {
    error(e?.stack || e?.message || String(e))
    process.exit(1)
  })
