const express = require('express');
const jwt = require('jsonwebtoken');
const { OAuth2Client } = require('google-auth-library');
const User = require('../models/User');
const Otp = require('../models/Otp');
const { authenticate } = require('../middleware/auth');

const router = express.Router();

/**
 * Helper to generate a 6-digit OTP
 */
function generateOTP() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

/**
 * POST /api/auth/send-otp
 * Send an OTP to a phone number (Mock implementation)
 */
router.post('/send-otp', async (req, res) => {
  try {
    const { phone } = req.body;
    
    if (!phone) {
      return res.status(400).json({ error: 'Phone number is required' });
    }

    const otpCode = generateOTP();

    // In a real app, integrate Twilio/Firebase Auth/AWS SNS here.
    console.log(`\n\n[MOCK SMS] OTP for ${phone} is: ${otpCode}\n\n`);

    // Remove existing OTPs for this phone to prevent spam issues
    await Otp.deleteMany({ phone });

    const newOtp = new Otp({
      phone,
      otp: otpCode,
    });
    
    await newOtp.save();

    res.json({ message: 'OTP sent successfully' });
  } catch (error) {
    console.error('Send OTP error:', error);
    res.status(500).json({ error: 'Server error while sending OTP' });
  }
});

/**
 * POST /api/auth/register
 * Register with name, email, phone, password, and OTP
 */
router.post('/register', async (req, res) => {
  try {
    const { name, email, phone, password } = req.body;

    if (!name || !email || !phone || !password) {
      return res.status(400).json({ error: 'All fields (name, email, phone, password) are required' });
    }

    if (password.length < 6) {
      return res.status(400).json({ error: 'Password must be at least 6 characters' });
    }

    // Check if user already exists with this email or phone
    const existingUser = await User.findOne({
      $or: [
        { email: email.toLowerCase() },
        { phone: phone }
      ]
    });

    if (existingUser) {
      return res.status(409).json({ error: 'Email or phone number already registered' });
    }

    // NOTE: OTP is currently verified on the frontend via Firebase Auth.
    // In a production environment, you would receive the Firebase ID Token here and verify it using firebase-admin.
    // For now, we trust the frontend verification.

    // Create user (password is hashed in pre-save hook)
    const user = new User({
      name: name.trim(),
      email: email.toLowerCase().trim(),
      phone: phone.trim(),
      passwordHash: password,
    });
    await user.save();

    // Cleanup mock OTPs if any
    await Otp.deleteMany({ phone });

    // Generate JWT token
    const token = jwt.sign(
      { userId: user._id },
      process.env.JWT_SECRET || 'secret',
      { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
    );

    res.status(201).json({
      message: 'Account created successfully',
      token,
      user: safeUserJSON(user),
    });
  } catch (error) {
    console.error('Register error:', error);
    res.status(500).json({ error: 'Server error during registration' });
  }
});

/**
 * POST /api/auth/login
 * Login with email or phone and password
 */
router.post('/login', async (req, res) => {
  try {
    const { identifier, password } = req.body; // identifier can be email or phone

    if (!identifier || !password) {
      return res.status(400).json({ error: 'Email/Phone and password are required' });
    }

    const searchIdentifier = identifier.trim().toLowerCase();

    // Find user by email or phone
    const user = await User.findOne({
      $or: [
        { email: searchIdentifier },
        { phone: identifier.trim() }
      ]
    });

    if (!user) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Compare password
    const isMatch = await user.comparePassword(password);
    if (!isMatch) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Generate JWT token
    const token = jwt.sign(
      { userId: user._id },
      process.env.JWT_SECRET || 'secret',
      { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
    );

    res.json({
      message: 'Login successful',
      token,
      user: safeUserJSON(user),
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Server error during login' });
  }
});

function safeUserJSON(user) {
  if (!user) return null;
  if (typeof user.toJSON === 'function') return user.toJSON();
  if (typeof user.toObject === 'function') {
    const obj = user.toObject();
    delete obj.passwordHash;
    return obj;
  }
  const obj = user._doc ? { ...user._doc } : { ...user };
  delete obj.passwordHash;
  return obj;
}

/**
 * GET /api/auth/me
 * Get current user profile (requires auth)
 */
router.get('/me', authenticate, async (req, res) => {
  try {
    res.json({ user: safeUserJSON(req.user) });
  } catch (error) {
    console.error('Get profile error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

/**
 * PUT /api/auth/me
 * Update current user profile
 */
router.put('/me', authenticate, async (req, res) => {
  try {
    const { name, phone, avatar } = req.body;
    const user = await User.findById(req.userId);

    if (name) user.name = name.trim();
    if (phone) user.phone = phone;
    if (avatar) user.avatar = avatar;

    await user.save();
    res.json({ user: safeUserJSON(user) });
  } catch (error) {
    console.error('Update profile error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});
/**
 * POST /api/auth/dev-login
 * DEV ONLY — Auto-creates a test user and returns a valid JWT.
 * This exists so the Flutter app's bypass login can get a real token.
 */
router.post('/dev-login', async (req, res) => {
  try {
    const testEmail = 'dev@rouniity.test';
    const testPhone = '9999999999';
    
    let user = await User.findOne({ email: testEmail });
    
    if (!user) {
      user = new User({
        name: 'Dev User',
        email: testEmail,
        phone: testPhone,
        passwordHash: 'devpassword123',
      });
      await user.save();
      console.log('[DEV] Created test user:', testEmail);
    }
    
    const token = jwt.sign(
      { userId: user._id },
      process.env.JWT_SECRET || 'secret',
      { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
    );
    
    res.json({
      message: 'Dev login successful',
      token,
      user: safeUserJSON(user),
    });
  } catch (error) {
    console.error('Dev login error:', error);
    res.status(500).json({ error: 'Dev login failed' });
  }
});

// All valid Google OAuth client IDs (web + Android) that can appear as the
// token audience. verifyIdToken accepts an array so we don't reject tokens
// minted with the Android client ID.
const GOOGLE_CLIENT_IDS = [
  process.env.GOOGLE_CLIENT_ID,                 // Web client ID
  process.env.GOOGLE_ANDROID_CLIENT_ID,          // Android client ID (if set)
  '876773622898-0qc2ls5lc95ik9avrp4g3osp4ko4of11.apps.googleusercontent.com', // Debug Android Client ID
  '876773622898-eb84c6s762vdq32pglo7l4dc9an20jv4.apps.googleusercontent.com', // Upload Android Client ID
  '876773622898-oh27m67ig5ivq7if14oek43blehijona.apps.googleusercontent.com', // Play Store App Signing Client ID
].filter(Boolean);

/**
 * POST /api/auth/google
 * Login or Register with Google ID Token
 */
router.post('/google', async (req, res) => {
  try {
    const { idToken } = req.body;
    if (!idToken) {
      return res.status(400).json({ error: 'ID token is required' });
    }

    const client = new OAuth2Client(process.env.GOOGLE_CLIENT_ID || 'your_google_client_id_here');
    const ticket = await client.verifyIdToken({
      idToken,
      audience: GOOGLE_CLIENT_IDS,
    });
    
    const payload = ticket.getPayload();
    if (!payload) {
      return res.status(401).json({ error: 'Invalid Google token' });
    }

    const { email, name, picture, sub: googleId } = payload;
    const searchEmail = email.toLowerCase().trim();

    let user = await User.findOne({ email: searchEmail });

    if (!user) {
      // User doesn't exist, we need their phone number to register them
      return res.status(202).json({
        requiresPhone: true,
        googleData: {
          email: searchEmail,
          name: name || 'Google User',
          picture,
          googleId,
        }
      });
    } else if (!user.googleId) {
      // Link Google account to existing email user
      user.googleId = googleId;
      if (!user.avatar && picture) user.avatar = picture;
      await user.save();
    }

    const token = jwt.sign(
      { userId: user._id },
      process.env.JWT_SECRET || 'secret',
      { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
    );

    res.json({
      message: 'Google login successful',
      token,
      user: safeUserJSON(user),
    });

  } catch (error) {
    console.error('Google auth error:', error);
    res.status(500).json({ error: 'Server error during Google auth' });
  }
});

/**
 * POST /api/auth/register-google
 * Register a new user with Google ID Token and Phone Number
 */
router.post('/register-google', async (req, res) => {
  try {
    const { idToken, phone, otp } = req.body;

    if (!idToken || !phone || !otp) {
      return res.status(400).json({ error: 'ID token, phone, and otp are required' });
    }

    const client = new OAuth2Client(process.env.GOOGLE_CLIENT_ID || 'your_google_client_id_here');
    const ticket = await client.verifyIdToken({
      idToken,
      audience: GOOGLE_CLIENT_IDS,
    });
    
    const payload = ticket.getPayload();
    if (!payload) {
      return res.status(401).json({ error: 'Invalid Google token' });
    }

    const { email, name, picture, sub: googleId } = payload;
    const searchEmail = email.toLowerCase().trim();

    // Check if user already exists
    const existingUser = await User.findOne({
      $or: [
        { email: searchEmail },
        { phone: phone }
      ]
    });

    if (existingUser) {
      return res.status(409).json({ error: 'Email or phone number already registered' });
    }

    // NOTE: OTP is currently verified on the frontend via Firebase Auth.
    // In a production environment, you would receive the Firebase ID Token here and verify it using firebase-admin.
    // For now, we trust the frontend verification.

    const user = new User({
      name: name || 'Google User',
      email: searchEmail,
      phone: phone.trim(),
      googleId,
      avatar: picture,
    });
    
    await user.save();

    // Cleanup mock OTPs if any
    await Otp.deleteMany({ phone });

    // Generate JWT token
    const token = jwt.sign(
      { userId: user._id },
      process.env.JWT_SECRET || 'secret',
      { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
    );

    res.status(201).json({
      message: 'Google account created successfully',
      token,
      user: safeUserJSON(user),
    });

  } catch (error) {
    console.error('Register Google error:', error);
    res.status(500).json({ error: 'Server error during Google registration' });
  }
});

module.exports = router;
