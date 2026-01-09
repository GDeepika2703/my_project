const ExcelJS = require('exceljs');
const pool = require('../dao/dao');
const db = require('../dao/dao');
const nodemailer = require('nodemailer');
const { MailerSend, EmailParams, Sender, Recipient } = require('mailersend');

const generateRandomNumber = () => Math.floor(1000000 + Math.random() * 9000000);
const admin = require('firebase-admin');
const serviceAccount = require('../firebase-service-messaging.json');

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp({

    credential: admin.credential.cert(serviceAccount),
  });
  console.log('Messaging instance:', admin.messaging());
  console.log('sendMulticast available?', typeof admin.messaging().sendMulticast);
  console.log('Messaging methods:', Object.getOwnPropertyNames(admin.messaging().__proto__));
}

// Send push notification helper
const sendPushNotification = async (token, title, body) => {
  const message = { notification: { title, body }, token };
  try {
    const response = await admin.messaging().send(message);
    console.log('✅ Notification sent:', response);
  } catch (err) {
    console.error('❌ Error sending notification:', err);
  }
};
// Register FCM token
const registerToken = (req, res) => {
  const { userId, fcmToken, region, company } = req.body;
  if (!userId || !fcmToken || !region || !company) {
    return res.status(400).json({ error: 'userId, fcmToken, region, and company required' });
  }

  // Validate user exists
  db.query(
    'SELECT phone_no FROM users WHERE user_id = ? AND company_name = ?',
    [userId, company],
    (err, userResults) => {
      if (err) {
        console.error('❌ DB error fetching user:', err.sqlMessage || err);
        return res.status(500).json({ error: 'DB error' });
      }
      if (!userResults.length) {
        return res.status(404).json({ error: `User ${userId} not found for ${company}` });
      }
      const phoneNo = userResults[0].phone_no;

      // Get region_id
      db.query(
        'SELECT region_id FROM regions WHERE region_name = ? AND company_name = ?',
        [region, company],
        (err, regionResults) => {
          if (err) {
            console.error('❌ DB error fetching region:', err.sqlMessage || err);
            return res.status(500).json({ error: 'DB error' });
          }
          if (!regionResults.length) {
            return res.status(404).json({ error: `Region ${region} not found for ${company}` });
          }
          const regionId = regionResults[0].region_id;

          // Insert into user_regions (using phone_no)
          db.query(
            'INSERT INTO user_regions (phone_no, region_id) VALUES (?, ?) ON DUPLICATE KEY UPDATE region_id = ?',
            [phoneNo, regionId, regionId],
            (err) => {
              if (err) {
                console.error('❌ DB error in user_regions:', err.sqlMessage || err);
                return res.status(500).json({ error: 'DB error' });
              }

              // Insert into user_tokens (under user_id)
              db.query(
                'INSERT INTO user_tokens (user_id, fcm_token) VALUES (?, ?) ON DUPLICATE KEY UPDATE fcm_token = ?',
                [userId, fcmToken, fcmToken],
                (err) => {
                  if (err) {
                    console.error('❌ DB error in user_tokens:', err.sqlMessage || err);
                    return res.status(500).json({ error: 'DB error' });
                  }
                  console.log(`✅ FCM token registered for userId: ${userId} (phone: ${phoneNo}) in region: ${region}`);
                  res.json({ success: true });
                }
              );
            }
          );
        }
      );
    }
  );
};

// Utility: distance between coordinates (meters)
function getDistance(lat1, lon1, lat2, lon2) {
  const R = 6371e3; // Earth's radius in meters
  const toRad = x => (x * Math.PI) / 180;
  const φ1 = toRad(lat1), φ2 = toRad(lat2);
  const Δφ = toRad(lat2 - lat1);
  const Δλ = toRad(lon2 - lon1);
  const a = Math.sin(Δφ / 2) ** 2 + Math.cos(φ1) * Math.cos(φ2) * Math.sin(Δλ / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c; // Distance in meters
}


const fetchDashboardData = (req, res) => {
  const { company, region } = req.query;
  
  if (!company || !region) {
    return res.status(400).json({ error: 'Company and region are required' });
  }

  const SEA_LEVEL_RL = 525.5;

  const makeRLFn = (altitudeRef) => {
    if (!Number.isFinite(altitudeRef)) return null;
    const C = SEA_LEVEL_RL - altitudeRef;
    return (altitude) => {
      if (!Number.isFinite(Number(altitude))) return null;
      return Number((Number(altitude) + C).toFixed(2));
    };
  };

  const regionName = region.trim();
  const isKache = regionName.toLowerCase() === 'kache';

  if (isKache) {
    let regionIds = [];
    const parsed = parseInt(region);

    if (!isNaN(parsed)) {
      regionIds = [parsed];
      proceedWithKacheQuery();
    } else {
      const regionQuery = `
        SELECT region_id FROM regions 
        WHERE region_name = ? AND company_name = ?
      `;
      db.query(regionQuery, [regionName, company], (err, results) => {
        if (err) return res.status(500).json({ error: 'DB error fetching region ID' });
        if (!results.length) return res.status(404).json({ error: 'Region not found' });
        regionIds = results.map(r => r.region_id);
        proceedWithKacheQuery();
      });
    }

    function proceedWithKacheQuery() {
      const deviceQuery = `
        SELECT DISTINCT UPPER(d.device_id) AS device_id
        FROM realtime_sensor_data d
        JOIN devices dev ON UPPER(d.device_id) = UPPER(dev.device_id)
        JOIN regions r ON dev.region_id = r.region_id
        WHERE r.company_name = ?
          AND r.region_id IN (?)
          AND d.device_id IN ('D3','D7','D8','D9','D12')
      `;

      db.query(deviceQuery, [company, regionIds], (err, devices) => {
        if (err) return res.status(500).json({ error: 'DB error fetching devices' });
        const deviceIds = devices.map(d => d.device_id);
        if (!deviceIds.length) return res.status(404).json({ error: 'No devices found' });

        const placeholders = deviceIds.map(() => '?').join(',');

        /* STEP 1: Get FIRST altitude reading (for RL reference) */
        const firstAltitudeQuery = `
          SELECT *
          FROM (
            SELECT *,
                   ROW_NUMBER() OVER (PARTITION BY device_id ORDER BY id ASC) rn
            FROM realtime_sensor_data
            WHERE device_id IN (${placeholders})
              AND altitude IS NOT NULL
          ) t
          WHERE rn = 1
        `;

        db.query(firstAltitudeQuery, deviceIds, (err, firstRows) => {
          if (err) return res.status(500).json({ error: 'DB error fetching reference altitude' });

          const RL_CALC = {};
          firstRows.forEach(r => {
            RL_CALC[r.device_id] = makeRLFn(Number(r.altitude));
          });

          /* STEP 2A: Latest reading (even if lat/lon = 0,0) */
          const latestQuery = `
            SELECT *
            FROM (
              SELECT *,
                     ROW_NUMBER() OVER (PARTITION BY device_id ORDER BY id DESC) rn
              FROM realtime_sensor_data
              WHERE device_id IN (${placeholders})
            ) t
            WHERE rn = 1
          `;

          /* STEP 2B: Latest real (non-zero) lat/lon */
          const lastValidPosQuery = `
            SELECT *
            FROM (
              SELECT *,
                     ROW_NUMBER() OVER (PARTITION BY device_id ORDER BY id DESC) rn
              FROM realtime_sensor_data
              WHERE device_id IN (${placeholders})
                AND latitude <> 0
                AND longitude <> 0
            ) x
            WHERE rn = 1
          `;

          db.query(latestQuery, deviceIds, (err, latestRows) => {
            if (err) return res.status(500).json({ error: 'DB error fetching latest data' });

            db.query(lastValidPosQuery, deviceIds, (err, posRows) => {
              if (err) return res.status(500).json({ error: 'DB error fetching valid coordinates' });

              const posMap = {};
              posRows.forEach(r => posMap[r.device_id] = r);

              const sites = {};
              const haulers = [];

              latestRows.forEach(row => {
                const pos = posMap[row.device_id];  // get last REAL coordinates
                
                const rlFn = RL_CALC[row.device_id];

                if (pos) {
                  const rl = rlFn ? rlFn(Number(pos.altitude)) : null;

                  sites[row.device_id] = {
                    id: row.device_id,
                    timestamp:row.timestamp,
                    pos: [pos.latitude, pos.longitude],
                    rl,
                    bottomRL: rl,
                    topRL: rl,
                    altitude: pos.altitude,
                    pitch: pos.pitch,      // <-- ADD THIS
                    roll: pos.roll,
                    speed: pos.speed,
                    movement: pos.movement,
                    vibration: pos.vibration
                  };
                }

                haulers.push({
                  id: row.device_id,
                  timestamp: row.timestamp,
                  load: row.current_load_tonnes ?? 0,
                  pitch: row.pitch,    // <-- ADD
                  roll: row.roll, 
                  speed: row.speed, 
                  altitude: row.altitude,    // <-- ADD
                  outward: [],
                  inward: []
                });
              });

              return res.json({
                status: 'success',
                company,
                region: regionIds,
                sites,
                haulers
              });
            });
          });
        });
      });
    }
    return;
  }

  /* OTHER REGIONS (unchanged) */
  const deviceQuery = `
    SELECT d.device_id
    FROM devices d
    JOIN regions r ON d.region_id = r.region_id
    WHERE r.company_name = ?
      AND r.region_name = ?
  `;

  db.query(deviceQuery, [company, regionName], (err, devices) => {
    if (err) return res.status(500).json({ error: 'DB error fetching devices' });
    if (!devices.length) return res.status(404).json({ error: 'No devices found' });

    const deviceIds = devices.map(d => d.device_id);
    const placeholders = deviceIds.map(() => '?').join(',');

    const sensorQuery = `
      SELECT *
      FROM dummy
      WHERE device_id IN (${placeholders})
      ORDER BY timestamp DESC
      LIMIT 6
    `;

    db.query(sensorQuery, deviceIds, (err, sensorResults) => {
      if (err) return res.status(500).json({ error: 'DB error fetching dummy data' });

      return res.json({
        status: 'success',
        company,
        region: regionName,
        devices: deviceIds,
        data: sensorResults
      });
    });
  });
};
// Add these constants at the top of your file
// Add this constant at the top
// -------- GRADIENT MULTIPLIER (based on pitch) --------
function getGradientMultiplier(pitch = 0) {
  if (pitch <= -5) return 0.25;        // Downhill
  if (pitch > -5 && pitch <= 3) return 0.65; // Flat
  if (pitch > 3 && pitch <= 8) return 1.3;   // Mild uphill
  return 2.0;                          // Steep uphill
}

// -------- SPEED MULTIPLIER --------
function getSpeedMultiplier(speed = 0) {
  if (speed <= 5) return 0.9;      // Idle / slow
  if (speed <= 20) return 1.0;     // Normal
  if (speed <= 35) return 1.1;     // Loaded
  return 1.25;                     // Overspeed / stress
}

// Diesel price per liter
const DIESEL_PRICE_PER_LITER = 94.5; // ₹ per liter

// Haversine formula to calculate distance between two coordinates
function haversineKm(coord1, coord2) {
  const toRad = x => (x * Math.PI) / 180;
  const R = 6371; // km
  const dLat = toRad(coord2[0] - coord1[0]);
  const dLon = toRad(coord2[1] - coord1[1]);
  const lat1 = toRad(coord1[0]);
  const lat2 = toRad(coord2[0]);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.sin(dLon / 2) ** 2 * Math.cos(lat1) * Math.cos(lat2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function calculateFuelAndCost(distance, pitch, speed, deviceId, timeDiffHours = 0) {
  let fuel = 0;

  // Excavator (time based – unchanged)
  if (deviceId === 'D7') {
    fuel = 15 * timeDiffHours;
  } 
  // Haulers (distance + gradient + speed based)
  else if (distance > 0) {
    const gradientMultiplier = getGradientMultiplier(pitch);
    const speedMultiplier = getSpeedMultiplier(speed);

    fuel =
      (distance / 1.52) *
      gradientMultiplier *
      speedMultiplier;
  }

  const cost = fuel * DIESEL_PRICE_PER_LITER;

  return {
    fuel: parseFloat(fuel.toFixed(6)),
    cost: parseFloat(cost.toFixed(2))
  };
}


// Updated fetchLast24HoursData function
const fetchLast24HoursData = (req, res) => {
  const { device_id, company, region } = req.query;
  
  if (!device_id) {
    return res.status(400).json({ error: 'Device ID is required' });
  }

  const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const formattedTime = twentyFourHoursAgo.toISOString().slice(0, 19).replace('T', ' ');
  
  const query = `
    SELECT 
      device_id,
      latitude,
      longitude,
      altitude,
      timestamp,
      pitch,
      roll,
      speed,
      movement,
      vibration
    FROM realtime_sensor_data 
    WHERE device_id = ? 
      AND timestamp >= ?
      AND latitude IS NOT NULL 
      AND longitude IS NOT NULL
      AND latitude != 0 
      AND longitude != 0
    ORDER BY timestamp ASC
  `;
  
  db.query(query, [device_id, formattedTime], (err, results) => {
    if (err) {
      console.error('❌ Database error fetching 24-hour data:', err);
      return res.status(500).json({ error: 'Database error' });
    }
    
    const pathData = [];
    let previousPoint = null;
    let totalDistance = 0;
    let totalFuel = 0;
    let totalFuelCost = 0;
    
    results.forEach((row, index) => {
      // Calculate distance from previous point
      let distance = 0;
      let timeDiffHours = 0;
      
      if (previousPoint) {
        distance = haversineKm(
          [previousPoint.latitude, previousPoint.longitude],
          [row.latitude, row.longitude]
        );
        
        // Calculate time difference for excavator
        if (device_id === 'D7') {
          const currentTime = new Date(row.timestamp);
          const prevTime = new Date(previousPoint.timestamp);
          timeDiffHours = (currentTime - prevTime) / 3600000; // hours
        }
      }
      totalDistance += distance;
      
      // Calculate fuel and cost (SIMPLE CALCULATION)
      const result = calculateFuelAndCost(
        distance,
        row.pitch || 0,
        row.speed || 0,
        device_id,
        timeDiffHours
      );

      
      totalFuel += result.fuel;
      totalFuelCost += result.cost;
      
      const pointData = {
        pos: [row.latitude, row.longitude],
        timestamp: row.timestamp,
        altitude: row.altitude || 0,
        pitch: row.pitch || 0,
        roll: row.roll || 0,
        speed: row.speed || 0,
        movement: row.movement || 0,
        vibration: row.vibration || 0,
        rl: row.altitude ? (row.altitude + 525.5) : null,
        distance: parseFloat(distance.toFixed(6)),
        fuel: result.fuel,
        fuel_cost: result.cost, // ✅ This should now have values
        cumulative_distance: parseFloat(totalDistance.toFixed(6)),
        cumulative_fuel: parseFloat(totalFuel.toFixed(6)),
        cumulative_fuel_cost: parseFloat(totalFuelCost.toFixed(2))
      };
      
      pathData.push(pointData);
      previousPoint = row;
    });
    
    console.log(`✅ Fetched ${pathData.length} data points for device ${device_id}`);
    console.log(`💰 Fuel cost calculation: Total = ₹${totalFuelCost.toFixed(2)}`);
    
    // Debug: Show first calculation
    if (pathData.length > 1) {
      console.log('First fuel cost calculation:', {
        distance: pathData[1].distance,
        fuel: pathData[1].fuel,
        calculated_cost: pathData[1].fuel * DIESEL_PRICE_PER_LITER,
        stored_cost: pathData[1].fuel_cost
      });
    }
    
    res.json({
      status: 'success',
      device_id,
      data: pathData,
      count: pathData.length,
      totals: {
        total_distance: parseFloat(totalDistance.toFixed(4)),
        total_fuel: parseFloat(totalFuel.toFixed(4)),
        total_fuel_cost: parseFloat(totalFuelCost.toFixed(2)),
        fuel_price_per_liter: DIESEL_PRICE_PER_LITER,
        currency: 'INR (₹)'
      },
      time_range: {
        from: formattedTime,
        to: new Date().toISOString()
      }
    });
  });
};

// Updated fetchAllDevicesLast24Hours function
const fetchAllDevicesLast24Hours = (req, res) => {
  const { company, region } = req.query;
  
  if (!company || !region) {
    return res.status(400).json({ error: 'Company and region are required' });
  }

  const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const formattedTime = twentyFourHoursAgo.toISOString().slice(0, 19).replace('T', ' ');
  
  const deviceQuery = `
    SELECT DISTINCT UPPER(d.device_id) AS device_id
    FROM realtime_sensor_data d
    JOIN devices dev ON UPPER(d.device_id) = UPPER(dev.device_id)
    JOIN regions r ON dev.region_id = r.region_id
    WHERE r.company_name = ?
      AND r.region_name = ?
      AND d.device_id IN ('D3','D7','D8','D9','D12')
  `;
  
  db.query(deviceQuery, [company, region], (err, devices) => {
    if (err) {
      console.error('❌ Database error fetching devices:', err);
      return res.status(500).json({ error: 'Database error' });
    }
    
    if (!devices.length) {
      return res.json({
        status: 'success',
        data: {},
        count: 0
      });
    }
    
    const deviceIds = devices.map(d => d.device_id);
    const placeholders = deviceIds.map(() => '?').join(',');
    
    const dataQuery = `
      SELECT 
        device_id,
        latitude,
        longitude,
        altitude,
        timestamp,
        pitch,
        roll,
        speed,
        movement,
        vibration
      FROM realtime_sensor_data 
      WHERE device_id IN (${placeholders})
        AND timestamp >= ?
        AND latitude IS NOT NULL 
        AND longitude IS NOT NULL
        AND latitude != 0 
        AND longitude != 0
      ORDER BY device_id, timestamp ASC
    `;
    
    const queryParams = [...deviceIds, formattedTime];
    
    db.query(dataQuery, queryParams, (err, results) => {
      if (err) {
        console.error('❌ Database error fetching 24-hour data:', err);
        return res.status(500).json({ error: 'Database error' });
      }
      
      const groupedData = {};
      const deviceTotals = {};
      
      deviceIds.forEach(id => {
        groupedData[id] = [];
        deviceTotals[id] = {
          totalDistance: 0,
          totalFuel: 0,
          totalFuelCost: 0,
          previousPoint: null
        };
      });
      
      results.forEach(row => {
        const deviceId = row.device_id;
        
        if (!groupedData[deviceId]) {
          groupedData[deviceId] = [];
          deviceTotals[deviceId] = {
            totalDistance: 0,
            totalFuel: 0,
            totalFuelCost: 0,
            previousPoint: null
          };
        }
        
        let distance = 0;
        let timeDiffHours = 0;
        
        if (deviceTotals[deviceId].previousPoint) {
          const prev = deviceTotals[deviceId].previousPoint;
          
          distance = haversineKm(
            [prev.latitude, prev.longitude],
            [row.latitude, row.longitude]
          );
          
          if (deviceId === 'D7') {
            const currentTime = new Date(row.timestamp);
            const prevTime = new Date(prev.timestamp);
            timeDiffHours = (currentTime - prevTime) / 3600000;
          }
        }
        
        // SIMPLE FUEL AND COST CALCULATION
        let fuel = 0;

        if (deviceId === 'D7') {
          fuel = 15 * timeDiffHours;
        } else if (distance > 0) {
          const gradientMultiplier = getGradientMultiplier(row.pitch || 0);
          const speedMultiplier = getSpeedMultiplier(row.speed || 0);

          fuel =
            (distance / 1.52) *
            gradientMultiplier *
            speedMultiplier;
        }

        const cost = fuel * DIESEL_PRICE_PER_LITER;

        
        deviceTotals[deviceId].totalDistance += distance;
        deviceTotals[deviceId].totalFuel += fuel;
        deviceTotals[deviceId].totalFuelCost += cost;
        
        const pointData = {
          pos: [row.latitude, row.longitude],
          timestamp: row.timestamp,
          altitude: row.altitude || 0,
          pitch: row.pitch || 0,
          roll: row.roll || 0,
          speed: row.speed || 0,
          movement: row.movement || 0,
          vibration: row.vibration || 0,
          rl: row.altitude ? (row.altitude + 525.5) : null,
          distance: parseFloat(distance.toFixed(6)),
          fuel: parseFloat(fuel.toFixed(6)),
          fuel_cost: parseFloat(cost.toFixed(2)), // ✅ Simple calculation
          cumulative_distance: parseFloat(deviceTotals[deviceId].totalDistance.toFixed(6)),
          cumulative_fuel: parseFloat(deviceTotals[deviceId].totalFuel.toFixed(6)),
          cumulative_fuel_cost: parseFloat(deviceTotals[deviceId].totalFuelCost.toFixed(2))
        };
        
        groupedData[deviceId].push(pointData);
        deviceTotals[deviceId].previousPoint = row;
      });
      
      console.log(`✅ Fetched 24-hour data for devices: ${deviceIds.join(', ')}`);
      
      let overallTotalDistance = 0;
      let overallTotalFuel = 0;
      let overallTotalFuelCost = 0;
      
      for (const deviceId in deviceTotals) {
        overallTotalDistance += deviceTotals[deviceId].totalDistance;
        overallTotalFuel += deviceTotals[deviceId].totalFuel;
        overallTotalFuelCost += deviceTotals[deviceId].totalFuelCost;
      }
      
      res.json({
        status: 'success',
        company,
        region,
        data: groupedData,
        device_count: deviceIds.length,
        total_points: results.length,
        totals: {
          overall_distance: parseFloat(overallTotalDistance.toFixed(4)),
          overall_fuel: parseFloat(overallTotalFuel.toFixed(4)),
          overall_fuel_cost: parseFloat(overallTotalFuelCost.toFixed(2)),
          fuel_price_per_liter: DIESEL_PRICE_PER_LITER,
          currency: 'INR (₹)',
          by_device: Object.keys(deviceTotals).reduce((acc, deviceId) => {
            acc[deviceId] = {
              total_distance: parseFloat(deviceTotals[deviceId].totalDistance.toFixed(4)),
              total_fuel: parseFloat(deviceTotals[deviceId].totalFuel.toFixed(4)),
              total_fuel_cost: parseFloat(deviceTotals[deviceId].totalFuelCost.toFixed(2))
            };
            return acc;
          }, {})
        },
        time_range: {
          from: formattedTime,
          to: new Date().toISOString()
        }
      });
    });
  });
};
// ==================== MONTHLY DATA ENDPOINTS ====================

// Single device monthly data (last 30 days)
const fetchLast30DaysData = (req, res) => {
  const { device_id, company, region } = req.query;
  
  if (!device_id) {
    return res.status(400).json({ error: 'Device ID is required' });
  }

  const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  const formattedTime = thirtyDaysAgo.toISOString().slice(0, 19).replace('T', ' ');
  
  const query = `
    SELECT 
      device_id,
      latitude,
      longitude,
      altitude,
      timestamp,
      pitch,
      roll,
      speed,
      movement,
      vibration
    FROM realtime_sensor_data 
    WHERE device_id = ? 
      AND timestamp >= ?
      AND latitude IS NOT NULL 
      AND longitude IS NOT NULL
      AND latitude != 0 
      AND longitude != 0
    ORDER BY timestamp ASC
  `;
  
  db.query(query, [device_id, formattedTime], (err, results) => {
    if (err) {
      console.error('❌ Database error fetching 30-day data:', err);
      return res.status(500).json({ error: 'Database error' });
    }
    
    const pathData = [];
    let previousPoint = null;
    let totalDistance = 0;
    let totalFuel = 0;
    let totalFuelCost = 0;
    
    results.forEach((row, index) => {
      let distance = 0;
      let timeDiffHours = 0;
      
      if (previousPoint) {
        distance = haversineKm(
          [previousPoint.latitude, previousPoint.longitude],
          [row.latitude, row.longitude]
        );
        
        if (device_id === 'D7') {
          const currentTime = new Date(row.timestamp);
          const prevTime = new Date(previousPoint.timestamp);
          timeDiffHours = (currentTime - prevTime) / 3600000;
        }
      }
      totalDistance += distance;
      
      const result = calculateFuelAndCost(distance, device_id, timeDiffHours);
      
      totalFuel += result.fuel;
      totalFuelCost += result.cost;
      
      const pointData = {
        pos: [row.latitude, row.longitude],
        timestamp: row.timestamp,
        altitude: row.altitude || 0,
        pitch: row.pitch || 0,
        roll: row.roll || 0,
        speed: row.speed || 0,
        movement: row.movement || 0,
        vibration: row.vibration || 0,
        rl: row.altitude ? (row.altitude + 525.5) : null,
        distance: parseFloat(distance.toFixed(6)),
        fuel: result.fuel,
        fuel_cost: result.cost,
        cumulative_distance: parseFloat(totalDistance.toFixed(6)),
        cumulative_fuel: parseFloat(totalFuel.toFixed(6)),
        cumulative_fuel_cost: parseFloat(totalFuelCost.toFixed(2))
      };
      
      pathData.push(pointData);
      previousPoint = row;
    });
    
    console.log(`✅ Fetched ${pathData.length} data points for device ${device_id} (30 days)`);
    console.log(`💰 Monthly fuel cost: ₹${totalFuelCost.toFixed(2)}`);
    
    res.json({
      status: 'success',
      device_id,
      data: pathData,
      count: pathData.length,
      totals: {
        total_distance: parseFloat(totalDistance.toFixed(4)),
        total_fuel: parseFloat(totalFuel.toFixed(4)),
        total_fuel_cost: parseFloat(totalFuelCost.toFixed(2)),
        fuel_price_per_liter: DIESEL_PRICE_PER_LITER,
        currency: 'INR (₹)',
        period: '30_days'
      },
      time_range: {
        from: formattedTime,
        to: new Date().toISOString()
      }
    });
  });
};

// All devices monthly data (last 30 days)
const fetchAllDevicesLast30Days = (req, res) => {
  const { company, region } = req.query;
  
  if (!company || !region) {
    return res.status(400).json({ error: 'Company and region are required' });
  }

  const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  const formattedTime = thirtyDaysAgo.toISOString().slice(0, 19).replace('T', ' ');
  
  const deviceQuery = `
    SELECT DISTINCT UPPER(d.device_id) AS device_id
    FROM realtime_sensor_data d
    JOIN devices dev ON UPPER(d.device_id) = UPPER(dev.device_id)
    JOIN regions r ON dev.region_id = r.region_id
    WHERE r.company_name = ?
      AND r.region_name = ?
      AND d.device_id IN ('D3','D7','D8','D9','D12')
  `;
  
  db.query(deviceQuery, [company, region], (err, devices) => {
    if (err) {
      console.error('❌ Database error fetching devices:', err);
      return res.status(500).json({ error: 'Database error' });
    }
    
    if (!devices.length) {
      return res.json({
        status: 'success',
        data: {},
        count: 0
      });
    }
    
    const deviceIds = devices.map(d => d.device_id);
    const placeholders = deviceIds.map(() => '?').join(',');
    
    const dataQuery = `
      SELECT 
        device_id,
        latitude,
        longitude,
        altitude,
        timestamp,
        pitch,
        roll,
        speed,
        movement,
        vibration
      FROM realtime_sensor_data 
      WHERE device_id IN (${placeholders})
        AND timestamp >= ?
        AND latitude IS NOT NULL 
        AND longitude IS NOT NULL
        AND latitude != 0 
        AND longitude != 0
      ORDER BY device_id, timestamp ASC
    `;
    
    const queryParams = [...deviceIds, formattedTime];
    
    db.query(dataQuery, queryParams, (err, results) => {
      if (err) {
        console.error('❌ Database error fetching 30-day data:', err);
        return res.status(500).json({ error: 'Database error' });
      }
      
      const groupedData = {};
      const deviceTotals = {};
      
      deviceIds.forEach(id => {
        groupedData[id] = [];
        deviceTotals[id] = {
          totalDistance: 0,
          totalFuel: 0,
          totalFuelCost: 0,
          previousPoint: null
        };
      });
      
      results.forEach(row => {
        const deviceId = row.device_id;
        
        if (!groupedData[deviceId]) {
          groupedData[deviceId] = [];
          deviceTotals[deviceId] = {
            totalDistance: 0,
            totalFuel: 0,
            totalFuelCost: 0,
            previousPoint: null
          };
        }
        
        let distance = 0;
        let timeDiffHours = 0;
        
        if (deviceTotals[deviceId].previousPoint) {
          const prev = deviceTotals[deviceId].previousPoint;
          
          distance = haversineKm(
            [prev.latitude, prev.longitude],
            [row.latitude, row.longitude]
          );
          
          if (deviceId === 'D7') {
            const currentTime = new Date(row.timestamp);
            const prevTime = new Date(prev.timestamp);
            timeDiffHours = (currentTime - prevTime) / 3600000;
          }
        }
        
        const result = calculateFuelAndCost(distance, deviceId, timeDiffHours);
        
        deviceTotals[deviceId].totalDistance += distance;
        deviceTotals[deviceId].totalFuel += result.fuel;
        deviceTotals[deviceId].totalFuelCost += result.cost;
        
        const pointData = {
          pos: [row.latitude, row.longitude],
          timestamp: row.timestamp,
          altitude: row.altitude || 0,
          pitch: row.pitch || 0,
          roll: row.roll || 0,
          speed: row.speed || 0,
          movement: row.movement || 0,
          vibration: row.vibration || 0,
          rl: row.altitude ? (row.altitude + 525.5) : null,
          distance: parseFloat(distance.toFixed(6)),
          fuel: result.fuel,
          fuel_cost: result.cost,
          cumulative_distance: parseFloat(deviceTotals[deviceId].totalDistance.toFixed(6)),
          cumulative_fuel: parseFloat(deviceTotals[deviceId].totalFuel.toFixed(6)),
          cumulative_fuel_cost: parseFloat(deviceTotals[deviceId].totalFuelCost.toFixed(2))
        };
        
        groupedData[deviceId].push(pointData);
        deviceTotals[deviceId].previousPoint = row;
      });
      
      console.log(`✅ Fetched 30-day data for devices: ${deviceIds.join(', ')}`);
      
      let overallTotalDistance = 0;
      let overallTotalFuel = 0;
      let overallTotalFuelCost = 0;
      
      for (const deviceId in deviceTotals) {
        overallTotalDistance += deviceTotals[deviceId].totalDistance;
        overallTotalFuel += deviceTotals[deviceId].totalFuel;
        overallTotalFuelCost += deviceTotals[deviceId].totalFuelCost;
      }
      
      res.json({
        status: 'success',
        company,
        region,
        data: groupedData,
        device_count: deviceIds.length,
        total_points: results.length,
        totals: {
          overall_distance: parseFloat(overallTotalDistance.toFixed(4)),
          overall_fuel: parseFloat(overallTotalFuel.toFixed(4)),
          overall_fuel_cost: parseFloat(overallTotalFuelCost.toFixed(2)),
          fuel_price_per_liter: DIESEL_PRICE_PER_LITER,
          currency: 'INR (₹)',
          period: '30_days',
          by_device: Object.keys(deviceTotals).reduce((acc, deviceId) => {
            acc[deviceId] = {
              total_distance: parseFloat(deviceTotals[deviceId].totalDistance.toFixed(4)),
              total_fuel: parseFloat(deviceTotals[deviceId].totalFuel.toFixed(4)),
              total_fuel_cost: parseFloat(deviceTotals[deviceId].totalFuelCost.toFixed(2))
            };
            return acc;
          }, {})
        },
        time_range: {
          from: formattedTime,
          to: new Date().toISOString()
        }
      });
    });
  });
};


const fetchAllDevicesLast30DaysExcel = (req, res) => {
  const { company, region } = req.query;

  if (!company || !region) {
    return res.status(400).json({ error: 'Company and region are required' });
  }

  // ---------- FIXED DATE RANGE (VARCHAR TIMESTAMP FORMAT) ----------
  // DB timestamp format: 1/4/2026, 11:11:37 AM
  const formattedStartTime = '1/4/2026, 6:00:00 AM';
  const formattedEndTime   = '1/5/2026, 6:00:00 AM';

  // ---------- DEVICE LIST ----------
  const deviceQuery = `
    SELECT DISTINCT UPPER(d.device_id) AS device_id
    FROM realtime_sensor_data d
    JOIN devices dev ON UPPER(d.device_id) = UPPER(dev.device_id)
    JOIN regions r ON dev.region_id = r.region_id
    WHERE r.company_name = ?
      AND r.region_name = ?
      AND UPPER(d.device_id) IN ('D3','D7','D8','D9','D12')
  `;

  db.query(deviceQuery, [company, region], (err, devices) => {
    if (err) return res.status(500).json({ error: 'Device fetch failed', details: err });
    if (!devices.length) return res.status(404).json({ message: 'No devices found' });

    const deviceIds = devices.map(d => d.device_id.toUpperCase());
    const placeholders = deviceIds.map(() => '?').join(',');

    // ---------- DATA QUERY (VARCHAR → DATETIME SAFE) ----------
    const dataQuery = `
      SELECT
        UPPER(device_id) AS device_id,
        latitude,
        longitude,
        altitude,
        timestamp,
        pitch,
        roll,
        speed
      FROM realtime_sensor_data
      WHERE UPPER(device_id) IN (${placeholders})
        AND STR_TO_DATE(timestamp, '%m/%d/%Y, %h:%i:%s %p')
            >= STR_TO_DATE(?, '%m/%d/%Y, %h:%i:%s %p')
        AND STR_TO_DATE(timestamp, '%m/%d/%Y, %h:%i:%s %p')
            <  STR_TO_DATE(?, '%m/%d/%Y, %h:%i:%s %p')
        AND latitude IS NOT NULL
        AND longitude IS NOT NULL
        AND latitude != 0
        AND longitude != 0
      ORDER BY
        device_id,
        STR_TO_DATE(timestamp, '%m/%d/%Y, %h:%i:%s %p') ASC
    `;

    db.query(
      dataQuery,
      [...deviceIds, formattedStartTime, formattedEndTime],
      async (err, results) => {
        if (err) return res.status(500).json({ error: 'Data fetch failed', details: err });

        // ---------- DEVICE STATE ----------
        const deviceState = {};
        deviceIds.forEach(id => {
          deviceState[id] = {
            prev: null,
            rows: [],
            totalDistance: 0,
            totalFuel: 0,
            totalFuelCost: 0
          };
        });

        // ---------- PROCESS DATA ----------
        for (const row of results) {
          const deviceId = row.device_id.toUpperCase();
          const device = deviceState[deviceId];

          let distance = 0;
          let timeDiffHours = 0;

          const currentTime = new Date(Date.parse(row.timestamp));

          if (device.prev) {
            distance = haversineKm(
              [device.prev.latitude, device.prev.longitude],
              [row.latitude, row.longitude]
            );

            const prevTime = new Date(Date.parse(device.prev.timestamp));
            timeDiffHours = (currentTime - prevTime) / 3600000;
          }

          const fuelResult = calculateFuelAndCost(distance, deviceId, timeDiffHours);

          device.totalDistance += distance;
          device.totalFuel += fuelResult.fuel;
          device.totalFuelCost += fuelResult.cost;

          device.rows.push({
            device_id: deviceId,
            timestamp: currentTime, // IMPORTANT: Date object
            latitude: row.latitude,
            longitude: row.longitude,
            altitude: row.altitude || 0,
            pitch: row.pitch || 0,
            roll: row.roll || 0,
            speed: row.speed || 0,
            distance,
            fuel: fuelResult.fuel,
            fuel_cost: fuelResult.cost,
            cum_distance: device.totalDistance,
            cum_fuel: device.totalFuel,
            cum_fuel_cost: device.totalFuelCost
          });

          device.prev = row;
        }

        // ---------- CREATE EXCEL ----------
        const workbook = new ExcelJS.Workbook();

        // DATA SHEET
        const dataSheet = workbook.addWorksheet('DATA (Latest First)');
        dataSheet.columns = [
          { header: 'DEVICE ID', key: 'device_id', width: 12 },
          { header: 'TIMESTAMP', key: 'timestamp', width: 24 },
          { header: 'LATITUDE', key: 'latitude', width: 14 },
          { header: 'LONGITUDE', key: 'longitude', width: 14 },
          { header: 'ALTITUDE', key: 'altitude', width: 12 },
          { header: 'PITCH', key: 'pitch', width: 8 },
          { header: 'ROLL', key: 'roll', width: 8 },
          { header: 'DISTANCE (KM)', key: 'distance', width: 14 },
          { header: 'FUEL (L)', key: 'fuel', width: 10 },
          { header: 'FUEL COST (₹)', key: 'fuel_cost', width: 14 }
        ];

        deviceIds.forEach(id => {
          deviceState[id].rows.slice().reverse().forEach(r => {
            dataSheet.addRow({
              device_id: r.device_id,
              timestamp: r.timestamp,
              latitude: r.latitude,
              longitude: r.longitude,
              altitude: r.altitude,
              pitch: r.pitch,
              roll: r.roll,
              speed: r.speed,
              distance: r.distance.toFixed(6),
              fuel: r.fuel.toFixed(4),
              fuel_cost: r.fuel_cost.toFixed(2),
              cum_distance: r.cum_distance.toFixed(6),
              cum_fuel: r.cum_fuel.toFixed(4),
              cum_fuel_cost: r.cum_fuel_cost.toFixed(2)
            });
          });
        });

        // FORCE AM / PM FORMAT
        dataSheet.getColumn('timestamp').numFmt = 'm/d/yyyy, h:mm:ss AM/PM';

        // SUMMARY SHEET
        const summarySheet = workbook.addWorksheet('SUMMARY');
        summarySheet.columns = [
          { header: 'DEVICE ID', key: 'device_id', width: 12 },
          { header: 'TOTAL DISTANCE (KM)', key: 'distance', width: 20 },
          { header: 'TOTAL FUEL (L)', key: 'fuel', width: 18 },
          { header: 'TOTAL FUEL COST (₹)', key: 'fuel_cost', width: 22 }
        ];

        deviceIds.forEach(id => {
          const d = deviceState[id];
          summarySheet.addRow({
            device_id: id,
            distance: d.totalDistance.toFixed(4),
            fuel: d.totalFuel.toFixed(4),
            fuel_cost: d.totalFuelCost.toFixed(2)
          });
        });

        // ---------- SEND EXCEL ----------
        res.setHeader(
          'Content-Type',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
        );
        res.setHeader(
          'Content-Disposition',
          'attachment; filename=devices_Jan4_6AM_to_Jan5_6AM.xlsx'
        );

        await workbook.xlsx.write(res);
        res.end();
      }
    );
  });
};



module.exports = {
  register: (req, res) => {
    console.log("📥 POST /register called");
    console.log("Body:", req.body);

    const { name, phone_no, email, password, sector_name, company_name, region_ids } = req.body;

    if (!name || !phone_no || !email || !password || !sector_name || !company_name || !region_ids || !Array.isArray(region_ids) || region_ids.length === 0) {
        return res.status(400).send({ status: "error", message: "All fields are required, and region_ids must be a non-empty array" });
    }

    // Validate region_ids belong to the company
    db.query(
        "SELECT region_id FROM regions WHERE company_name = ? AND region_id IN (?)",
        [company_name, region_ids],
        (err, results) => {
            if (err) {
                console.error("DB error:", err);
                return res.status(500).send({ status: "error", message: "DB error" });
            }

            const validRegionIds = results.map(r => r.region_id.toString());
            if (validRegionIds.length !== region_ids.length) {
                return res.status(400).send({ status: "error", message: "Invalid region_ids for the selected company" });
            }

            // Insert into users table (exclude user_id, let it auto-increment)
            db.query(
                "INSERT INTO users (name, phone_no, email, password, company_name, sector_name, access) VALUES (?, ?, ?, ?, ?, ?, 'in progress')",
                [name, phone_no, email, password, company_name, sector_name],
                (err, userResult) => {
                    if (err) {
                        console.error("DB error:", err);
                        return res.status(500).send({ status: "error", message: "DB error: " + err.message });
                    }

                    const user_id = userResult.insertId;

                    // Insert into user_regions table
                    const regionValues = region_ids.map(id => [phone_no, id]);
                    db.query(
                        "INSERT INTO user_regions (phone_no, region_id) VALUES ?",
                        [regionValues],
                        (err) => {
                            if (err) {
                                console.error("DB error:", err);
                                return res.status(500).send({ status: "error", message: "DB error: " + err.message });
                            }

                            res.status(201).send({
                                status: "success",
                                user_id,
                                name,
                                company_name,
                                message: "User successfully registered"
                            });
                        }
                    );
                }
            );
        }
    );
},

  signin: (req, res) => {
  const { phone_no, password } = req.body;

    if (!/^\d{4}$/.test(password)) {
    return res.status(401).json({ message: 'Invalid credentials' }); // generic message
    }

    if (!phone_no || !password)
      return res.status(400).json({ message: 'Please provide valid credentials.' });

  const query = 'SELECT * FROM users WHERE phone_no = ? AND password = ?';
  db.query(query, [phone_no, password], (err, result) => {
    if (err) return res.status(500).json({ message: 'Database error' });

    if (result.length > 0) {
      const user = result[0];

      /*if (user.access !== 'verified') {
        return res.status(403).json({
          status: 'pending',
          message: 'Access not verified yet. Please wait for company approval.',
        });
      }*/

        // Fetch regions
      const regionQuery = `
        SELECT r.region_name
        FROM user_regions ur
        JOIN regions r ON ur.region_id = r.region_id
        WHERE ur.phone_no = ?`;

      db.query(regionQuery, [phone_no], (err, regions) => {
      if (err) return res.status(500).json({ message: 'Error fetching regions' });

      return res.status(200).json({
        status: 'success',
        message: 'Login successful',
        user: {
          user_id: user.user_id,
          name: user.name,
          phone_no: user.phone_no,
          email: user.email,
          sector_name: user.sector_name,
          company_name: user.company_name,
          access: user.access,
          regions: regions.map(r => r.region_name),
        },
      });
      });
    } else {
      return res.status(401).json({ message: 'Invalid credentials' });
    }
  });
},

  forgotPassword: (req, res) => {
    const { phone_no, password } = req.body;
    if (!phone_no || !password)
      return res.status(400).json({ message: 'Phone number and password required' });
    if (!/^\d{4}$/.test(password)) {
      return res.status(400).json({ message: 'PIN must be exactly 4 digits' });
    }

    const cleanPhone = phone_no.trim();

    const checkQuery = `SELECT * FROM users WHERE phone_no = ?`;
    db.query(checkQuery, [cleanPhone], (err, result) => {
      if (err) return res.status(500).json({ message: 'Database error' });

      if (result.length === 0)
        return res.status(404).json({ message: 'User not found' });

      const updateQuery = `UPDATE users SET password = ? WHERE phone_no = ?`;
      db.query(updateQuery, [password, cleanPhone], (err, updateResult) => {
        if (err) return res.status(500).json({ message: 'Error updating password' });

        return res.status(200).json({ message: 'Password updated successfully' });
      });
    });
  },
  
  receiveSensorData: (req, res) => {
    const { device_id, temperature, humidity, dust } = req.body;

    if (
      device_id ===undefined ||
      temperature === undefined ||
      humidity === undefined ||
      /*air_quality === undefined ||
      mq7_co === undefined ||*/
      dust === undefined
    ) {
      return res.status(400).json({ error: 'Missing sensor data' });
    }

    const insertQuery = `
      INSERT INTO dummy (device_id, temperature, humidity,  dust, timestamp)
      VALUES (?, ?, ?, ?,  NOW())
    `;

    db.query(insertQuery, [device_id, temperature, humidity,  dust], (err, result) => {
      if (err) return res.status(500).json({ error: 'SQL insert failed' });

      return res.status(201).json({
        message: 'Sensor data stored successfully',
        id: result.insertId,
      });
    });
  },

insertRealtimeData: (req, res) => {
  const {
    device_id,
    latitude,
    longitude,
    altitude,
    gps_status,
    z_axis,
    movement,
    pitch,
    roll,
    speed,
    vibration,
    timestamp   // ✅ accepted from backend
  } = req.body;

  // ------------------------------------------
  // Validate required fields
  // ------------------------------------------
  if (!device_id || latitude === undefined || longitude === undefined) {
    return res.status(400).json({ error: "Missing required fields" });
  }
   console.log(`📡 Received data from device ${device_id}`);
   console.log(req.body);


  // ------------------------------------------
  // Optional: log device timestamp (NOT inserted)
  // ------------------------------------------
  if (timestamp) {
    console.log("⏱ Device sent timestamp:", timestamp);
  }

  // ------------------------------------------
  // SQL INSERT → timestamp is ALWAYS NOW()
  // ------------------------------------------
  const query = `
    INSERT INTO realtime_sensor_data (
      device_id,
      timestamp,
      latitude,
      longitude,
      altitude,
      gps_status,
      z_axis,
      movement,
      pitch,
      roll,
      speed,
      vibration
    )
    VALUES (?, NOW(), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `;

  const values = [
    device_id,
    latitude,
    longitude,
    altitude || null,
    gps_status || null,
    z_axis || null,
    movement || null,
    pitch || null,
    roll || null,
    speed || null,
    vibration || null
  ];

  // ------------------------------------------
  // Execute query
  // ------------------------------------------
  db.query(query, values, (err, result) => {
    if (err) {
      console.error("❌ Database insert error:", err);
      return res.status(500).json({ error: "Database insert error" });
    }

    res.json({
      status: "success",
      inserted_id: result.insertId
    });
  });
},


getLast10ZAxis: (req, res) => {
  const query = `
    SELECT device_id, pitch AS z_axis, timestamp
    FROM (
      SELECT device_id, pitch, timestamp,
             ROW_NUMBER() OVER (PARTITION BY device_id ORDER BY timestamp DESC) as rn
      FROM realtime_sensor_data
      WHERE device_id LIKE 'D%'
    ) t
    WHERE rn <= 10
    ORDER BY device_id, timestamp DESC
  `;
  pool.query(query, (err, rows) => {
    if (err) {
      console.error('Error fetching last 10 z_axis per Hauler:', err);
      return res.status(500).json({ error: "Error fetching z_axis values" });
    }

    // Group data by device_id
    const haulerData = {};
    rows.forEach(row => {
      const equipment = row.device_id;
      if (!haulerData[equipment]) {
        haulerData[equipment] = [];
      }
      haulerData[equipment].push({
        z_axis: Number(row.z_axis), // Use z_axis instead of pitch
        timestamp: row.timestamp
      });
    });

    // Send response
    res.json(haulerData);
  });
},
registerToken,
fetchDashboardData,
// Add these new exports
fetchLast24HoursData,
fetchAllDevicesLast24Hours,
fetchLast30DaysData,
fetchAllDevicesLast30Days,
fetchAllDevicesLast30DaysExcel
}
