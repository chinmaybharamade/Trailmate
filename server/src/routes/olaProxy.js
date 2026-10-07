const express = require('express');
const axios = require('axios');
const { authenticate } = require('../middleware/auth');
const ApiUsage = require('../models/ApiUsage');

const router = express.Router();

// ── Public routes (no auth) ──────────────────────────────────────────────────
// /nearby is intentionally public: it's a maps proxy with a server-side API key.
// No user data is returned — it only forwards location-based search queries.


const OLA_BASE_URL = 'https://api.olamaps.io';
const getApiKey = () => process.env.OLA_MAPS_API_KEY;

/**
 * Helper to calculate perpendicular midpoints for alternative routes
 */
function getOffsetMidpoints(lat1, lon1, lat2, lon2) {
  const midLat = (lat1 + lat2) / 2;
  const midLon = (lon1 + lon2) / 2;
  
  // Calculate approximate distance between origin and destination in km
  const distDegrees = Math.sqrt(Math.pow(lat2 - lat1, 2) + Math.pow(lon2 - lon1, 2));
  const distKm = distDegrees * 111.0;
  
  // Scale offset to 20% of the total distance to force completely different highway corridors.
  // Cap it between 20km (for short trips) and 100km (to avoid crazy detours).
  const dynamicOffsetKm = Math.min(Math.max(distKm * 0.20, 20), 100);
  
  // Angle of the route
  const angle = Math.atan2(lat2 - lat1, lon2 - lon1);
  
  // Offset in degrees (approximate)
  const offsetDegrees = dynamicOffsetKm / 111.0; 
  
  // Perpendicular offsets (+90 deg and -90 deg)
  const wp1 = {
      lat: midLat + Math.sin(angle + Math.PI / 2) * offsetDegrees,
      lng: midLon + Math.cos(angle + Math.PI / 2) * offsetDegrees
  };
  
  const wp2 = {
      lat: midLat + Math.sin(angle - Math.PI / 2) * offsetDegrees,
      lng: midLon + Math.cos(angle - Math.PI / 2) * offsetDegrees
  };
  
  return [wp1, wp2];
}

/**
 * Helper to proxy requests to Ola Maps API
 */
async function proxyToOla(olaPath, queryParams, res) {
  try {
    const params = { ...queryParams, api_key: getApiKey() };
    const response = await axios.get(`${OLA_BASE_URL}${olaPath}`, {
      params,
      headers: {
        'X-Request-Id': `rouniity-${Date.now()}`,
      },
      timeout: 15000,
    });
    return res.json(response.data);
  } catch (error) {
    const status = error.response?.status || 500;
    const message = error.response?.data?.error || error.message;
    console.error(`Ola Maps proxy error [${olaPath}]:`, message);
    return res.status(status).json({ error: `Maps API error: ${message}` });
  }
}

/**
 * GET /api/maps/nearby  ── PUBLIC (no auth required)
 * Proxy to Ola Maps Nearby Search API
 * Query: location (lat,lng), types (gas_station, restaurant, etc.)
 */
router.get('/nearby', async (req, res) => {
  const { location, types, radius } = req.query;
  if (!location || !types) {
    return res.status(400).json({ error: 'location and types are required' });
  }
  const params = { layers: 'venue', location, types, limit: 20, size: 20 };
  if (radius) params.radius = radius;
  
  try {
    const apiKey = getApiKey();
    params.api_key = apiKey;
    const response = await axios.get(`${OLA_BASE_URL}/places/v1/nearbysearch`, {
      params,
      headers: { 'X-Request-Id': `rouniity-nearby-${Date.now()}` },
      timeout: 15000,
    });
    
    const data = response.data;
    if (data && data.predictions) {
      // Limit to first 20 predictions to avoid excessive detail requests
      const limit = Math.min(data.predictions.length, 20);
      data.predictions = data.predictions.slice(0, limit);
      
      const promises = data.predictions.map(async (p) => {
        try {
          if (p.place_id) {
            const detailUrl = `${OLA_BASE_URL}/places/v1/details?place_id=${p.place_id}&api_key=${apiKey}`;
            const detailRes = await axios.get(detailUrl, { timeout: 5000 });
            const geom = detailRes.data?.result?.geometry?.location;
            if (geom) {
              p.geometry = { location: geom };
              console.log(`[OlaProxy] Successfully fetched geometry for ${p.place_id}:`, geom);
            } else {
              console.log(`[OlaProxy] No geometry found in details for ${p.place_id}`);
            }
          }
        } catch (e) {
          console.error(`[OlaProxy] Failed to fetch details for ${p.place_id}:`, e.message);
        }
        return p;
      });
      await Promise.all(promises);
    }
    
    res.json(data);
  } catch (error) {
    const status = error.response?.status || 500;
    const data = error.response?.data || {};
    const message = data.reason || data.status || data.error || error.message;
    console.error('Nearby search proxy error:', message);
    if (error.response?.data) {
      console.error('Full Ola API Error:', JSON.stringify(data, null, 2));
    }
    console.error('Request query was:', req.query);
    res.status(status).json({ error: `Nearby Search API error: ${message}` });
  }
});

// ── Authenticated routes ─────────────────────────────────────────────────────
// All routes below this line require a valid Bearer token.
router.use(authenticate);

// Middleware to track API usage for authenticated routes
router.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', async () => {
    try {
      const latency = Date.now() - start;
      const endpoint = req.path;
      await ApiUsage.create({
        userId: req.userId,
        endpoint,
        method: req.method,
        status: res.statusCode,
        latency,
        error: res.statusCode >= 400 ? (res.statusMessage || 'Error') : null,
      });
    } catch (err) {
      console.error('Failed to log API usage:', err.message);
    }
  });
  next();
});

/**
 * GET /api/maps/usage
 * Get API token usage for the current user
 */
router.get('/usage', async (req, res) => {
  try {
    const used = await ApiUsage.countDocuments({ userId: req.userId });
    const limit = 10000; // Mock fixed token limit per user
    res.json({ used, limit });
  } catch (error) {
    console.error('Failed to get API usage:', error.message);
    res.status(500).json({ error: 'Failed to retrieve API usage' });
  }
});


/**
 * POST /api/maps/directions
 * Proxy to Ola Maps Directions API
 * Query: origin, destination, waypoints (optional, pipe-separated)
 */
router.post('/directions', async (req, res) => {
  try {
    const { origin, destination, waypoints, mode } = req.body;

    if (!origin || !destination) {
      return res.status(400).json({ error: 'Origin and destination are required' });
    }

    const params = {
      origin,
      destination,
      api_key: getApiKey(),
      steps: true,
    };
    if (mode) {
      if (mode === 'two_wheeler' || mode === 'bike') {
        params.mode = 'motorcycle';
      } else if (mode === 'walking' || mode === 'walk') {
        params.mode = 'walking';
      } else {
        params.mode = mode;
      }
    }
    if (waypoints) {
      const wpArray = waypoints.split('|');
      if (wpArray.length > 20) {
        const step = Math.ceil(wpArray.length / 20);
        params.waypoints = wpArray.filter((_, i) => i % step === 0).slice(0, 20).join('|');
        console.log(`[OlaProxy] Downsampled ${wpArray.length} waypoints to 20`);
      } else {
        params.waypoints = waypoints;
      }
    }
    if (req.body.alternatives && !req.body.waypoints) {
      // -------------------------------------------------------------
      // CUSTOM ALTERNATIVE ROUTE LOGIC
      // -------------------------------------------------------------
      // To force distinct alternative routes, we calculate offset midpoints
      // and request routes through them, rather than relying on the API's native alternatives.
      
      const [originLat, originLng] = origin.split(',').map(Number);
      const [destLat, destLng] = destination.split(',').map(Number);
      
      const offsets = getOffsetMidpoints(originLat, originLng, destLat, destLng);

      const reqOptions = {
        headers: { 'X-Request-Id': `rouniity-dir-${Date.now()}` },
        timeout: 15000,
      };

      const routePromises = [
        // 1. Direct Route
        axios.post(`${OLA_BASE_URL}/routing/v1/directions`, null, { params, ...reqOptions }),
        
        // 2. Left Offset Route
        axios.post(`${OLA_BASE_URL}/routing/v1/directions`, null, { 
          params: { ...params, waypoints: `${offsets[0].lat},${offsets[0].lng}` },
          ...reqOptions 
        }),
        
        // 3. Right Offset Route
        axios.post(`${OLA_BASE_URL}/routing/v1/directions`, null, { 
          params: { ...params, waypoints: `${offsets[1].lat},${offsets[1].lng}` },
          ...reqOptions 
        })
      ];

      const results = await Promise.allSettled(routePromises);
      
      let allRoutes = [];
      let baseData = null;

      results.forEach((res, index) => {
        if (res.status === 'fulfilled' && res.value.data && res.value.data.routes) {
          if (index === 0) baseData = res.value.data;
          
          const validRoutes = res.value.data.routes.filter(r => r != null);
          if (validRoutes.length > 0) {
             let route = validRoutes[0];
             
             // If the route has multiple legs (because of our synthesized waypoint), 
             // merge them into a single leg so the Flutter client calculates total ETA/distance correctly.
             if (route.legs && route.legs.length > 1) {
                let totalDistance = 0;
                let totalDuration = 0;
                let allSteps = [];
                route.legs.forEach(leg => {
                  totalDistance += leg.distance || 0;
                  totalDuration += leg.duration || 0;
                  if (leg.steps) allSteps = allSteps.concat(leg.steps);
                });
                route.legs[0].distance = totalDistance;
                route.legs[0].duration = totalDuration;
                route.legs[0].steps = allSteps;
                route.legs = [route.legs[0]];
             }
             
             // Only take the primary route from each request
             allRoutes.push(route);
          }
        } else if (res.status === 'rejected') {
          console.log(`[OlaProxy] Alternative route ${index} failed:`, res.reason.message);
        }
      });

      if (!baseData || allRoutes.length === 0) {
        throw new Error('Failed to fetch any valid routes');
      }

      // Return combined routes
      return res.json({
        ...baseData,
        routes: allRoutes
      });

    } else {
      // -------------------------------------------------------------
      // STANDARD ROUTING (or smart routes that have predefined waypoints)
      // -------------------------------------------------------------
      if (req.body.alternatives) {
        params.alternatives = true;
      }

      const response = await axios.post(
        `${OLA_BASE_URL}/routing/v1/directions`,
        null,
        {
          params,
          headers: { 'X-Request-Id': `rouniity-dir-${Date.now()}` },
          timeout: 15000,
        }
      );

      const data = response.data;

      // If user-defined waypoints produced multi-leg routes, merge them
      // into a single leg so the Flutter client calculates totals correctly.
      if (data && data.routes) {
        data.routes.forEach(route => {
          if (route.legs && route.legs.length > 1) {
            let totalDistance = 0;
            let totalDuration = 0;
            let allSteps = [];
            route.legs.forEach(leg => {
              totalDistance += leg.distance || 0;
              totalDuration += leg.duration || 0;
              if (leg.steps) allSteps = allSteps.concat(leg.steps);
            });
            route.legs[0].distance = totalDistance;
            route.legs[0].duration = totalDuration;
            route.legs[0].steps = allSteps;
            route.legs = [route.legs[0]];
          }
        });
      }

      res.json(data);
    }
  } catch (error) {
    const status = error.response?.status || 500;
    const data = error.response?.data || {};
    const message = data.reason || data.status || data.error || error.message;
    
    console.error('Directions proxy error:', message);
    if (error.response?.data) {
      console.error('Full Ola API Error:', JSON.stringify(error.response.data, null, 2));
    }
    console.error('Request params were:', req.body);
    res.status(status).json({ error: `Directions API error: ${message}` });
  }
});


/**
 * GET /api/maps/autocomplete
 * Proxy to Ola Maps Autocomplete API
 * Query: input (search text), location (optional, for bias)
 */
router.get('/autocomplete', (req, res) => {
  const { input, location } = req.query;
  if (!input) {
    return res.status(400).json({ error: 'input is required' });
  }
  const params = { input };
  if (location) params.location = location;
  return proxyToOla('/places/v1/autocomplete', params, res);
});

/**
 * GET /api/maps/geocode
 * Proxy to Ola Maps Geocoding API
 * Query: address
 */
router.get('/geocode', (req, res) => {
  const { address } = req.query;
  if (!address) {
    return res.status(400).json({ error: 'address is required' });
  }
  return proxyToOla('/places/v1/geocode', { address }, res);
});

/**
 * GET /api/maps/reverse-geocode
 * Proxy to Ola Maps Reverse Geocoding API
 * Query: latlng (lat,lng)
 */
router.get('/reverse-geocode', (req, res) => {
  const { latlng } = req.query;
  if (!latlng) {
    return res.status(400).json({ error: 'latlng is required' });
  }
  return proxyToOla('/places/v1/reverse-geocode', { latlng }, res);
});

/**
 * POST /api/maps/distance-matrix
 * Proxy to Ola Maps Distance Matrix API
 * Body: origins, destinations (pipe-separated lat,lng pairs)
 */
router.post('/distance-matrix', async (req, res) => {
  try {
    const { origins, destinations } = req.body;
    if (!origins || !destinations) {
      return res.status(400).json({ error: 'origins and destinations are required' });
    }

    const response = await axios.get(
      `${OLA_BASE_URL}/routing/v1/distanceMatrix`,
      {
        params: { origins, destinations, api_key: getApiKey() },
        headers: { 'X-Request-Id': `rouniity-dm-${Date.now()}` },
        timeout: 15000,
      }
    );

    res.json(response.data);
  } catch (error) {
    const status = error.response?.status || 500;
    const message = error.response?.data?.error || error.message;
    console.error('Distance matrix proxy error:', message);
    res.status(status).json({ error: `Distance Matrix error: ${message}` });
  }
});

/**
 * POST /api/maps/snap-to-road
 * Proxy to Ola Maps Snap to Road API
 * Body: points (pipe-separated lat,lng pairs)
 */
router.post('/snap-to-road', async (req, res) => {
  try {
    const { points } = req.body;
    if (!points) {
      return res.status(400).json({ error: 'points are required' });
    }

    const response = await axios.post(
      `${OLA_BASE_URL}/routing/v1/snapToRoad`,
      null,
      {
        params: { points, api_key: getApiKey() },
        headers: { 'X-Request-Id': `rouniity-snap-${Date.now()}` },
        timeout: 15000,
      }
    );

    res.json(response.data);
  } catch (error) {
    const status = error.response?.status || 500;
    const message = error.response?.data?.error || error.message;
    console.error('Snap to road proxy error:', message);
    res.status(status).json({ error: `Snap to Road error: ${message}` });
  }
});

module.exports = router;
