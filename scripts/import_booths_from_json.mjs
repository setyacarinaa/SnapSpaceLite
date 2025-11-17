#!/usr/bin/env node
// Restore/Import booths from a JSON file into Firestore.
// Requirements:
// - Node.js
// - firebase-admin installed (already in package.json)
// - Service account key via GOOGLE_APPLICATION_CREDENTIALS env var
// Usage (PowerShell):
//   $env:GOOGLE_APPLICATION_CREDENTIALS="D:/path/to/serviceAccountKey.json";
//   node scripts/import_booths_from_json.mjs D:/path/to/booths.json

import fs from 'fs'
import path from 'path'
import process from 'process'
import { initializeApp, applicationDefault, cert } from 'firebase-admin/app'
import { getFirestore, FieldValue } from 'firebase-admin/firestore'

const log = (m) => console.log(`[import-booths] ${m}`)
const error = (m) => console.error(`[import-booths] ERROR: ${m}`)

// Resolve credentials
let appInited = false
try {
  const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS
  if (credPath && fs.existsSync(credPath)) {
    const key = JSON.parse(fs.readFileSync(credPath, 'utf8'))
    initializeApp({ credential: cert(key) })
    appInited = true
    log(`Initialized with service account: ${credPath}`)
  }
} catch (e) {}
if (!appInited) {
  try {
    initializeApp({ credential: applicationDefault() })
    appInited = true
    log('Initialized with applicationDefault credentials')
  } catch (e) {
    error(`Failed to init Firebase Admin: ${e.message}`)
    process.exit(1)
  }
}

const db = getFirestore()

function normalizeBooth(raw) {
  const firstNonEmpty = (arr) => {
    if (!Array.isArray(arr)) return undefined
    for (const x of arr) if (typeof x === 'string' && x.trim()) return x.trim()
    return undefined
  }

  const name = raw.name ?? raw.title ?? 'Tanpa Nama'
  const price = Number(raw.price ?? 0) || 0
  const duration = raw.duration ?? raw.time ?? ''
  const capacity = raw.capacity ?? raw.cap ?? ''
  const description = raw.description ?? raw.desc ?? ''

  // pick imageUrl or first element of images/photos/gallery
  let imageUrl = raw.imageUrl ?? raw.imageURL ?? raw.image ?? raw.url ?? raw.photoUrl ?? raw.path ?? raw.storagePath ?? raw.image_path
  if (!imageUrl || typeof imageUrl !== 'string' || !imageUrl.trim()) {
    imageUrl = firstNonEmpty(raw.images) || firstNonEmpty(raw.photos) || firstNonEmpty(raw.gallery) || ''
  }

  return {
    name,
    price,
    duration,
    capacity,
    description,
    imageUrl: (typeof imageUrl === 'string' ? imageUrl.trim() : ''),
    created_at: FieldValue.serverTimestamp(),
    updated_at: FieldValue.serverTimestamp(),
  }
}

async function importFile(jsonPath) {
  const abs = path.resolve(jsonPath)
  if (!fs.existsSync(abs)) {
    error(`JSON file not found: ${abs}`)
    process.exit(1)
  }
  const content = JSON.parse(fs.readFileSync(abs, 'utf8'))
  const arr = Array.isArray(content)
    ? content
    : (Array.isArray(content.items) ? content.items : Object.values(content))
  if (!Array.isArray(arr) || arr.length === 0) {
    error('JSON must contain an array of booths or an object with items')
    process.exit(1)
  }

  const batch = db.batch()
  const col = db.collection('booths')
  let count = 0
  for (const item of arr) {
    const docData = normalizeBooth(item)
    const id = (typeof item.id === 'string' && item.id.trim()) ? item.id.trim() : undefined
    const ref = id ? col.doc(id) : col.doc()
    batch.set(ref, docData, { merge: true })
    count++
    if (count % 400 === 0) { // chunk commits
      await batch.commit()
    }
  }
  if (count % 400 !== 0) await batch.commit()
  log(`Imported ${count} booth(s) from ${abs}`)
}

const jsonArg = process.argv[2] || 'assets/booths.sample.json'
importFile(jsonArg).catch((e) => {
  error(e?.stack || e?.message || String(e))
  process.exit(1)
})
