#!/usr/bin/env node
// Script: check_claims.mjs
// Tujuan: Menampilkan daftar user yang memiliki custom claim system_admin atau photobooth_admin
// Opsional: Set ADMIN_EMAIL untuk memeriksa satu email saja.
// Contoh:
//   $env:GOOGLE_APPLICATION_CREDENTIALS='./keys/firebase-sa.json'; node scripts/check_claims.mjs
//   $env:GOOGLE_APPLICATION_CREDENTIALS='./keys/firebase-sa.json'; $env:ADMIN_EMAIL='snapspacelite@gmail.com'; node scripts/check_claims.mjs

import process from 'process';
import { initializeApp, applicationDefault, cert } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

function log(msg) { console.log(`[check-claims] ${msg}`); }
function error(msg) { console.error(`[check-claims] ERROR: ${msg}`); }

// Init Firebase Admin
try {
    initializeApp({ credential: applicationDefault() });
    log('Initialized Firebase Admin using applicationDefault credentials');
} catch (e) {
    error('Gagal inisialisasi Admin SDK: ' + e.message);
    process.exit(1);
}

const auth = getAuth();
const targetEmail = process.env.ADMIN_EMAIL ? process.env.ADMIN_EMAIL.toLowerCase().trim() : null;

async function run() {
    log('Mengambil daftar user (paging)...');
    let nextPageToken = undefined;
    let total = 0;
    const rows = [];
    do {
        const resp = await auth.listUsers(1000, nextPageToken);
        resp.users.forEach(u => {
            total++;
            const claims = u.customClaims || {};
            const emailLower = (u.email || '').toLowerCase();
            const hasAdmin = claims.system_admin === true;
            const hasPhotoboothAdmin = claims.photobooth_admin === true;
            if (targetEmail) {
                if (emailLower === targetEmail) {
                    rows.push({ email: u.email, uid: u.uid, system_admin: hasAdmin, photobooth_admin: hasPhotoboothAdmin });
                }
            } else {
                if (hasAdmin || hasPhotoboothAdmin) {
                    rows.push({ email: u.email, uid: u.uid, system_admin: hasAdmin, photobooth_admin: hasPhotoboothAdmin });
                }
            }
        });
        nextPageToken = resp.pageToken;
    } while (nextPageToken);

    if (rows.length === 0) {
        log(targetEmail ? `Tidak ditemukan claim untuk email ${targetEmail}` : 'Tidak ada user dengan claim admin.');
        return;
    }

    log(`Ditemukan ${rows.length} baris (dari total pengguna: ${total}).`);
    console.table(rows);
}

run().catch(e => { error(e.stack || e.message); process.exit(1); });
