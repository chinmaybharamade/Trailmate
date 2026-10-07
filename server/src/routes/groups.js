const express = require('express');
const { nanoid } = require('nanoid');
const Group = require('../models/Group');
const { authenticate } = require('../middleware/auth');

const router = express.Router();

// All group routes require authentication
router.use(authenticate);

/**
 * POST /api/groups
 * Create a new group (caller becomes leader)
 */
router.post('/', async (req, res) => {
  try {
    const { name, origin, destination, waypoints, polyline, distanceMeters, durationSeconds, transportMode, routeMode, aiWaypoints, routeCharacter } = req.body;

    if (!name) {
      return res.status(400).json({ error: 'Group name is required' });
    }

    // Generate a strictly alphanumeric 6-character invite code
    const generateInviteCode = require('nanoid').customAlphabet('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ', 6);
    const inviteCode = generateInviteCode();

    const group = new Group({
      name: name.trim(),
      inviteCode,
      leaderId: req.userId,
      members: [{
        userId: req.userId,
        name: req.user.name,
        avatar: req.user.avatar,
        role: 'leader',
      }],
      route: {
        transportMode: transportMode || 'driving',
        routeMode: routeMode || 'highway',
        origin: origin || {},
        destination: destination || {},
        waypoints: waypoints || [],
        aiWaypoints: aiWaypoints || [],
        steps: req.body.steps || [],
        routeCharacter: routeCharacter || '',
        polyline: polyline || null,
        distanceMeters: distanceMeters || 0,
        durationSeconds: durationSeconds || 0,
      },
    });

    await group.save();

    res.status(201).json({
      message: 'Group created successfully',
      group,
    });
  } catch (error) {
    console.error('Create group error:', error);
    res.status(500).json({ error: 'Failed to create group' });
  }
});

/**
 * GET /api/groups/my
 * Get all groups the current user is part of
 */
router.get('/my', async (req, res) => {
  try {
    const groups = await Group.find({
      'members.userId': req.userId,
    }).sort({ updatedAt: -1 });

    res.json({ groups });
  } catch (error) {
    console.error('Get my groups error:', error);
    res.status(500).json({ error: 'Failed to fetch groups' });
  }
});

/**
 * GET /api/groups/:id
 * Get group details by ID
 */
router.get('/:id', async (req, res) => {
  try {
    const group = await Group.findById(req.params.id);
    if (!group) {
      return res.status(404).json({ error: 'Group not found' });
    }

    if (!group.isMember(req.userId)) {
      return res.status(403).json({ error: 'Not a member of this group' });
    }

    res.json({ group });
  } catch (error) {
    console.error('Get group error:', error);
    res.status(500).json({ error: 'Failed to fetch group' });
  }
});

/**
 * POST /api/groups/join
 * Join a group using invite code
 */
router.post('/join', async (req, res) => {
  try {
    const { inviteCode } = req.body;

    if (!inviteCode) {
      return res.status(400).json({ error: 'Invite code is required' });
    }

    const group = await Group.findOne({
      inviteCode: inviteCode.toUpperCase().trim(),
    });

    if (!group) {
      return res.status(404).json({ error: 'Invalid invite code' });
    }

    if (group.status === 'completed') {
      return res.status(400).json({ error: 'This trip has already ended' });
    }

    if (group.isMember(req.userId)) {
      return res.status(400).json({ error: 'You are already a member of this group' });
    }

    if (group.members.length >= group.maxMembers) {
      return res.status(400).json({ error: 'Group is full' });
    }

    // Add member
    group.members.push({
      userId: req.userId,
      name: req.user.name,
      avatar: req.user.avatar,
      role: 'member',
    });

    await group.save();

    res.json({
      message: 'Joined group successfully',
      group,
    });
  } catch (error) {
    console.error('Join group error:', error);
    res.status(500).json({ error: 'Failed to join group' });
  }
});

/**
 * DELETE /api/groups/:id/members/:userId
 * Remove a member (leader only) or leave group (self)
 */
router.delete('/:id/members/:memberId', async (req, res) => {
  try {
    const group = await Group.findById(req.params.id);
    if (!group) {
      return res.status(404).json({ error: 'Group not found' });
    }

    const targetUserId = req.params.memberId;
    const isSelf = targetUserId === req.userId;
    const isLeader = group.isLeader(req.userId);

    if (!isSelf && !isLeader) {
      return res.status(403).json({ error: 'Only the leader can remove members' });
    }

    // Leader cannot remove themselves (must delete group instead)
    if (isSelf && isLeader) {
      return res.status(400).json({ error: 'Leader cannot leave. Delete the group instead.' });
    }

    group.members = group.members.filter(
      m => m.userId.toString() !== targetUserId
    );

    await group.save();

    res.json({ message: 'Member removed', group });
  } catch (error) {
    console.error('Remove member error:', error);
    res.status(500).json({ error: 'Failed to remove member' });
  }
});

/**
 * PUT /api/groups/:id/route
 * Update group route (leader only)
 */
router.put('/:id/route', async (req, res) => {
  try {
    const group = await Group.findById(req.params.id);
    if (!group) {
      return res.status(404).json({ error: 'Group not found' });
    }

    if (!group.isLeader(req.userId)) {
      return res.status(403).json({ error: 'Only the leader can update the route' });
    }

    const { origin, destination, waypoints, polyline, polylinePoints, distanceMeters, durationSeconds } = req.body;

    if (origin) group.route.origin = origin;
    if (destination) group.route.destination = destination;
    if (waypoints) group.route.waypoints = waypoints;
    if (polyline) group.route.polyline = polyline;
    if (polylinePoints) group.route.polylinePoints = polylinePoints;
    if (distanceMeters !== undefined) group.route.distanceMeters = distanceMeters;
    if (durationSeconds !== undefined) group.route.durationSeconds = durationSeconds;

    await group.save();

    res.json({ message: 'Route updated', group });
  } catch (error) {
    console.error('Update route error:', error);
    res.status(500).json({ error: 'Failed to update route' });
  }
});

/**
 * PUT /api/groups/:id/status
 * Update group status (leader only): planning → active → completed
 */
router.put('/:id/status', async (req, res) => {
  try {
    const group = await Group.findById(req.params.id);
    if (!group) {
      return res.status(404).json({ error: 'Group not found' });
    }

    if (!group.isLeader(req.userId)) {
      return res.status(403).json({ error: 'Only the leader can change trip status' });
    }

    const { status } = req.body;
    const validTransitions = {
      planning: ['active'],
      active: ['paused', 'completed'],
      paused: ['active', 'completed'],
    };

    const allowed = validTransitions[group.status] || [];
    if (!allowed.includes(status)) {
      return res.status(400).json({
        error: `Cannot transition from '${group.status}' to '${status}'`,
      });
    }

    group.status = status;
    await group.save();

    res.json({ message: `Trip ${status}`, group });
  } catch (error) {
    console.error('Update status error:', error);
    res.status(500).json({ error: 'Failed to update status' });
  }
});

/**
 * DELETE /api/groups/:id
 * Delete group (leader only, only in planning status)
 */
router.delete('/:id', async (req, res) => {
  try {
    const group = await Group.findById(req.params.id);
    if (!group) {
      return res.status(404).json({ error: 'Group not found' });
    }

    if (!group.isLeader(req.userId)) {
      return res.status(403).json({ error: 'Only the leader can delete the group' });
    }

    await Group.findByIdAndDelete(req.params.id);
    res.json({ message: 'Group deleted' });
  } catch (error) {
    console.error('Delete group error:', error);
    res.status(500).json({ error: 'Failed to delete group' });
  }
});

module.exports = router;
