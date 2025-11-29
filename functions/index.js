const functions = require('firebase-functions');
const admin = require('firebase-admin');
const cors = require('cors')({ origin: true });

try {
  admin.initializeApp();
} catch (e) {
  // already initialized in emulator or subsequent invocations
}

const db = admin.firestore();

// HTTP endpoint to set photobooth_admin claim for a user (by email or uid).
// Security: caller must be signed-in and have custom claim `system_admin: true`.
exports.setPhotoboothAdmin = functions.https.onRequest((req, res) => {
  cors(req, res, async () => {
    if (req.method !== 'POST') return res.status(405).json({ error: 'Only POST' });

    const authHeader = req.get('Authorization') || '';
    const match = authHeader.match(/^Bearer\s+(.*)$/i);
    const idToken = match ? match[1] : (req.body && req.body.idToken) || null;
    if (!idToken) return res.status(401).json({ error: 'Missing ID token' });

    let caller;
    try {
      caller = await admin.auth().verifyIdToken(idToken);
    } catch (e) {
      return res.status(401).json({ error: 'Invalid ID token', detail: String(e) });
    }

    if (!caller || !caller.system_admin) {
      return res.status(403).json({ error: 'Forbidden: requires system_admin claim' });
    }

    const { email, uid } = req.body || {};
    if (!email && !uid) return res.status(400).json({ error: 'Provide email or uid' });

    try {
      let targetUser;
      if (email) {
        targetUser = await admin.auth().getUserByEmail(email);
      } else {
        targetUser = await admin.auth().getUser(uid);
      }

      const existing = targetUser.customClaims || {};
      existing.photobooth_admin = true;
      await admin.auth().setCustomUserClaims(targetUser.uid, existing);

      // Update Firestore user doc as well
      const userRef = db.collection('users').doc(targetUser.uid);
      await userRef.set({
        role: 'photobooth_admin',
        verified: true,
        verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      return res.json({ success: true, uid: targetUser.uid });
    } catch (e) {
      console.error('setPhotoboothAdmin error', e);
      return res.status(500).json({ error: String(e) });
    }
  });
});

// Send an email to photobooth admin owner when their Firestore user doc
// gets verified (verified changes from falsy -> true).
const nodemailer = require('nodemailer');

exports.onUserVerified = functions.firestore
  .document('users/{uid}')
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};

    try {
      const role = after.role || '';
      const wasVerified = !!before.verified;
      const isVerified = !!after.verified;

      if (role !== 'photobooth_admin') return null;
      if (wasVerified || !isVerified) return null; // only when it becomes verified

      const toEmail = after.email;
      if (!toEmail) {
        console.warn('onUserVerified: no email on user doc', context.params.uid);
        return null;
      }

      // Read SMTP config from functions config (set via `firebase functions:config:set`)
      const cfg = functions.config();
      const smtpUser = cfg.smtp && cfg.smtp.user;
      const smtpPass = cfg.smtp && cfg.smtp.pass;
      const smtpHost = cfg.smtp && cfg.smtp.host;
      const smtpPort = cfg.smtp && cfg.smtp.port;
      const smtpFrom = (cfg.smtp && cfg.smtp.from) || smtpUser;
      const appLoginUrl = (cfg.app && cfg.app.login_url) || 'snapspace://login';

      if (!smtpUser || !smtpPass) {
        console.error('SMTP credentials not configured. Set functions config smtp.user and smtp.pass');
        return null;
      }

      // Configure transporter. Prefer explicit host/port when provided, else use Gmail service.
      let transporter;
      if (smtpHost && smtpPort) {
        transporter = nodemailer.createTransport({
          host: smtpHost,
          port: Number(smtpPort),
          secure: Number(smtpPort) === 465, // true for 465, false for other ports
          auth: { user: smtpUser, pass: smtpPass },
        });
      } else {
        transporter = nodemailer.createTransport({
          service: 'gmail',
          auth: { user: smtpUser, pass: smtpPass },
        });
      }

      const subject = 'Pendaftaran Admin Photobooth Diterima';
      const text = `Halo ${after.name || ''},\n\nPendaftaran Anda sebagai Admin Photobooth telah disetujui oleh admin sistem. Silakan masuk ke aplikasi menggunakan akun Anda.`;
      const html = `<p>Halo ${after.name || ''},</p>
        <p>Pendaftaran Anda sebagai <strong>Admin Photobooth</strong> telah disetujui oleh admin sistem.</p>
        <p>Klik tautan berikut untuk membuka aplikasi dan menuju halaman login:</p>
        <p><a href="${appLoginUrl}">Buka Aplikasi untuk Login</a></p>
        <p>Jika tautan tidak berfungsi, buka aplikasi dan masuk secara manual.</p>
        <p>Salam,<br/>Tim SnapSpace</p>`;

      await transporter.sendMail({
        from: smtpFrom,
        to: toEmail,
        subject,
        text,
        html,
      });

      console.log('Sent verification email to', toEmail);
      return null;
    } catch (err) {
      console.error('onUserVerified error', err);
      return null;
    }
  });

// Also handle verification events for photobooth_admins collection
exports.onPhotoboothAdminVerified = functions.firestore
  .document('photobooth_admins/{uid}')
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};

    try {
      const wasVerified = !!before.verified;
      const isVerified = !!after.verified;
      if (wasVerified || !isVerified) return null;

      const toEmail = after.email;
      if (!toEmail) {
        console.warn('onPhotoboothAdminVerified: no email on user doc', context.params.uid);
        return null;
      }

      const cfg = functions.config();
      const smtpUser = cfg.smtp && cfg.smtp.user;
      const smtpPass = cfg.smtp && cfg.smtp.pass;
      const smtpHost = cfg.smtp && cfg.smtp.host;
      const smtpPort = cfg.smtp && cfg.smtp.port;
      const smtpFrom = (cfg.smtp && cfg.smtp.from) || smtpUser;
      const appLoginUrl = (cfg.app && cfg.app.login_url) || 'snapspace://login';

      if (!smtpUser || !smtpPass) {
        console.error('SMTP credentials not configured. Set functions config smtp.user and smtp.pass');
        return null;
      }

      let transporter;
      if (smtpHost && smtpPort) {
        transporter = nodemailer.createTransport({
          host: smtpHost,
          port: Number(smtpPort),
          secure: Number(smtpPort) === 465,
          auth: { user: smtpUser, pass: smtpPass },
        });
      } else {
        transporter = nodemailer.createTransport({
          service: 'gmail',
          auth: { user: smtpUser, pass: smtpPass },
        });
      }

      const subject = 'Pendaftaran Admin Photobooth Diterima';
      const text = `Halo ${after.name || ''},\n\nPendaftaran Anda sebagai Admin Photobooth telah disetujui oleh admin sistem. Silakan masuk ke aplikasi menggunakan akun Anda.`;
      const html = `<p>Halo ${after.name || ''},</p>
        <p>Pendaftaran Anda sebagai <strong>Admin Photobooth</strong> telah disetujui oleh admin sistem.</p>
        <p>Klik tautan berikut untuk membuka aplikasi dan menuju halaman login:</p>
        <p><a href="${appLoginUrl}">Buka Aplikasi untuk Login</a></p>
        <p>Jika tautan tidak berfungsi, buka aplikasi dan masuk secara manual.</p>
        <p>Salam,<br/>Tim SnapSpace</p>`;

      await transporter.sendMail({
        from: smtpFrom,
        to: toEmail,
        subject,
        text,
        html,
      });

      console.log('Sent verification email to', toEmail);
      return null;
    } catch (err) {
      console.error('onPhotoboothAdminVerified error', err);
      return null;
    }
  });
