/**
 * Migration script: move documents with role == 'photobooth_admin'
 * from 'users' collection to 'photobooth_admins' collection.
 *
 * Usage:
 *   # dry-run (default): shows what would be done
 *   node migrate-users-to-photobooth_admins.js
 *
 *   # perform migration and mark originals as migrated
 *   node migrate-users-to-photobooth_admins.js --apply
 *
 *   # perform migration and delete originals (USE WITH CAUTION)
 *   node migrate-users-to-photobooth_admins.js --apply --delete
 *
 * Requirements:
 * - Node.js installed
 * - `npm install firebase-admin` in repo (or globally)
 * - Set GOOGLE_APPLICATION_CREDENTIALS to a service account JSON with Firestore access
 */

const admin = require('firebase-admin');

const args = process.argv.slice(2);
const APPLY = args.includes('--apply');
const DELETE = args.includes('--delete');

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error('ERROR: Set GOOGLE_APPLICATION_CREDENTIALS to your service account JSON path');
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.applicationDefault() });
const db = admin.firestore();

async function migrate() {
  console.log('Starting migration: users.role == "photobooth_admin" -> photobooth_admins');
  const q = await db.collection('users').where('role', '==', 'photobooth_admin').get();
  console.log('Found', q.size, 'documents to consider');
  if (q.empty) return;

  let migrated = 0;
  for (const doc of q.docs) {
    const uid = doc.id;
    const data = doc.data();
    const targetRef = db.collection('photobooth_admins').doc(uid);

    const copy = Object.assign({}, data);
    // ensure verified field exists and is boolean
    if (typeof copy.verified === 'undefined') copy.verified = false;

    console.log(`\n[${uid}] Will copy to photobooth_admins/${uid}`);
    console.log(' Fields:', Object.keys(copy).join(', '));

    if (!APPLY) continue;

    // perform copy
    await targetRef.set(copy, { merge: true });
    migrated++;

    if (DELETE) {
      console.log(` Deleting original users/${uid}`);
      await db.collection('users').doc(uid).delete();
    } else {
      // mark original as migrated
      console.log(` Marking original users/${uid} as migrated`);
      await db.collection('users').doc(uid).set({ migrated: true, migratedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    }
  }

  console.log('\nSummary:');
  console.log('  found:', q.size);
  console.log('  migrated (applied):', migrated);
  console.log('  apply flag used:', APPLY);
  console.log('  delete originals:', DELETE);
}

migrate().then(() => process.exit(0)).catch(err => { console.error(err); process.exit(2); });
