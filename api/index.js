const express = require('express');
const app = express();

app.use(express.json());

app.post('/crashes', (req, res) => {
  try {
    const crash = req.body;
    
    console.log("🚨 NEW CRASH REPORT RECEIVED:");
    console.log("Time:", new Date().toISOString());
    console.log("Error:", crash.error);
    console.log("Platform:", crash.platform);
    console.log("App Version:", crash.app_version);

    res.status(200).json({
      status: "success",
      message: "Crash reported"
    });
  } catch (err) {
    console.error("Error processing crash:", err);
    res.status(500).json({ status: "error" });
  }
});

module.exports = app;