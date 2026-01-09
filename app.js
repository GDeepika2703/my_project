const express = require('express');
const router = express.Router();
const fetch = require('./routes/fetch');
const insert = require('./routes/insert');
const path = require('path');
const cors = require('cors');
const fs = require('fs');
const db = require('./dao/dao');   // ✅ Add this line
const app = express();

app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

const PORT = 5001;

// Company/region APIs
app.get('/getcompanies', fetch.getcompanies);
app.get('/sectors', fetch.getsectors);
app.get('/getregions', fetch.getregions);

// Dashboard APIs
app.get('/fetch-dashboard-data', insert.fetchDashboardData);
app.get('/api/get_last_10_zaxis', insert.getLast10ZAxis);
app.post('/api/sensor-data', insert.receiveSensorData);
app.post('/insert-realtime-data', insert.insertRealtimeData);

// Auth / Registration
app.post('/register', insert.register);
app.post('/signin', insert.signin);
app.post('/forgot-password', insert.forgotPassword);

// New: register FCM token from Flutter
app.post('/register-token', insert.registerToken);

// NEW 24-hour data routes - Add them to your insert module
// Make sure these functions exist in your insert.js file
app.get('/fetch-24h-data', insert.fetchLast24HoursData);
app.get('/fetch-all-devices-24h', insert.fetchAllDevicesLast24Hours);
// ==================== ROUTES ====================
// Add these routes to your Express app:

app.get('/fetch-30d-data', insert.fetchLast30DaysData);
app.get('/fetch-all-devices-30d', insert.fetchAllDevicesLast30Days);
// Test route
app.get(
  '/fetch-all-devices-30d-excel',
  insert.fetchAllDevicesLast30DaysExcel
);
app.post('/test', (req, res) => {
  console.log("Test API called with:", req.body);
  res.json({ message: "Test successful", received: req.body });
});

// Dashboard route (serves dashboard.html with latest data)
// Dashboard route
app.get('/dashboard', (req, res) => {
  const sql = 'SELECT * FROM dashboard_parameters ORDER BY timestamp DESC LIMIT 1';
  db.query(sql, (err, results) => {
    if (err) {
      console.error('DB query error:', err);
      return res.status(500).send('Failed to load dashboard');
    }

    const dashboardData = results.length > 0 ? results[0] : {};

    let html;
    try {
      html = fs.readFileSync(path.join(__dirname, 'public', 'dashboard.html'), 'utf8');
    } catch (fileErr) {
      console.error('Error reading dashboard.html:', fileErr);
      return res.status(500).send('Failed to load dashboard HTML');
    }

    const scriptTag = `<script>const dashboardData = ${JSON.stringify(dashboardData)};</script>`;
    const updatedHtml = html.replace('</body>', `${scriptTag}</body>`);

    res.send(updatedHtml);
  });
});

//Root
app.get('/', (req, res) => {
  res.send('');
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server is running on http://0.0.0.0:${PORT}`);
  console.log(`📡 24-hour data endpoints available:`);
  console.log(`   GET /fetch-24h-data?device_id=D3&company=TMC&region=Kache`);
  console.log(`   GET /fetch-all-devices-24h?company=TMC&region=Kache`);
});
