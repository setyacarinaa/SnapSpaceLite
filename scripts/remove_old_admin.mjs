#!/usr/bin/env node
// Script: remove_old_admin.mjs
// Tujuan: Menurunkan / menghapus status system_admin dari akun lama.
// Aksi default:
//  - Menghapus custom claim system_admin
//  - Update dokumen Firestore di koleksi 'customers' & 'users' (jika ada) -> role: 'customer', deprecated: true
//  - Menambahkan timestamp updatedAt
// Opsi tambahan via ENV:
//   OLD_ADMIN_EMAIL (wajib) -> email lama
//   DELETE_USER=true -> juga hapus user dari Firebase Auth
//   DELETE_DOCS=true -> hapus dokumen Firestore bukan downgrade
// Contoh:
//   $env:GOOGLE_APPLICATION_CREDENTIALS='./keys/firebase-sa.json'; $env:OLD_ADMIN_EMAIL='adminsnapspacelite29@gmail.com'; node scripts/remove_old_admin.mjs
//   $env:GOOGLE_APPLICATION_CREDENTIALS='./keys/firebase-sa.json'; $env:OLD_ADMIN_EMAIL='adminsnapspacelite29@gmail.com'; $env:DELETE_USER='true'; $env:DELETE_DOCS='true'; node scripts/remove_old_admin.mjs

import process from 'process';
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

function log(msg) { console.log(`[remove-old-admin] ${msg}`); }
function error(msg) { console.error(`[remove-old-admin] ERROR: ${msg}`); }

const OLD_EMAIL = (process.env.OLD_ADMIN_EMAIL || '').toLowerCase().trim();
const DELETE_USER = (process.env.DELETE_USER || '').toLowerCase() === 'true';
const DELETE_DOCS = (process.env.DELETE_DOCS || '').toLowerCase() === 'true';

if (!OLD_EMAIL) {
    error('ENV OLD_ADMIN_EMAIL belum di-set.');
    console.log('Contoh: $env:OLD_ADMIN_EMAIL="adminsnapspacelite29@gmail.com"');
    process.exit(1);
}

try {
    initializeApp({ credential: applicationDefault() });
    log('Initialized Firebase Admin (applicationDefault)');
} catch (e) {
    error('Gagal init Firebase Admin: ' + e.message);
    process.exit(1);
}

const auth = getAuth();
const db = getFirestore();

async function downgradeOldAdmin() {
    log(`Memproses email lama: ${OLD_EMAIL}`);
    let user;
    try {
        user = await auth.getUserByEmail(OLD_EMAIL);
    } catch (e) {
        if (e.code === 'auth/user-not-found') {
            error('User lama tidak ditemukan. Tidak ada tindakan.');
            return;
        }
        throw e;
    }
    log(`UID ditemukan: ${user.uid}`);

    // Remove custom claims
    await auth.setCustomUserClaims(user.uid, {});
    log('Custom claim system_admin dihapus (set empty claims)');

    const userDocRef = db.collection('users').doc(user.uid);
    const customerDocRef = db.collection('customers').doc(user.uid);

    if (DELETE_DOCS) {
        const doc1 = await userDocRef.get();
        if (doc1.exists) {
            await userDocRef.delete();
            log('Dokumen users/* dihapus');
        }
        const doc2 = await customerDocRef.get();
        if (doc2.exists) {
            await customerDocRef.delete();
            log('Dokumen customers/* dihapus');
        }
    } else {
        // Downgrade role
        await userDocRef.set({
            role: 'customer',
            deprecated: true,
            updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
        await customerDocRef.set({
            role: 'customer',
            deprecated: true,
            updated_at: FieldValue.serverTimestamp(),
        }, { merge: true });
        log('Role di Firestore diubah menjadi customer + deprecated:true');
    }

    if (DELETE_USER) {
        await auth.deleteUser(user.uid);
        log('User Auth dihapus.');
    }

    log('Selesai memproses akun lama.');
}

downgradeOldAdmin().catch(e => { error(e.stack || e.message); process.exit(1); });
