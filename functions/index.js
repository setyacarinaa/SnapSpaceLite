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
