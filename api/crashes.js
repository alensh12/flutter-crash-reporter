const express = require('express');
const app = express();

app.use(express.json());

app.post('/api/crashes', async (req, res) => {
  try {
    const crash = req.body;
    
    console.log("🚨 NEW CRASH REPORT RECEIVED:");
    console.log("Time:", new Date().toISOString());
    console.log("Error:", crash.error);
    console.log("Platform:", crash.platform);
    console.log("App Version:", crash.app_version);
    // You can see full logs in Vercel Dashboard

    // TODO: Later you can save to database (MongoDB, Supabase, etc.)

    res.status(200).json({ 
      status: "success", 
      message: "Crash reported" 
    });
  } catch (err) {
    console.error("Error saving crash:", err);
    res.status(500).json({ status: "error" });
  }
});

// Export for Vercel
module.exports = app;
