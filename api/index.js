const express = require('express');
const app = express();

app.use(express.json({ limit: '10mb' }));

app.post('/crashes', (req, res) => {
  try {
    const crash = req.body;
    
    console.log("🚨 CRASH REPORT RECEIVED");
    console.log(JSON.stringify(crash, null, 2));

    res.status(200).json({ 
      status: "success", 
      message: "Crash reported successfully" 
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ status: "error" });
  }
});

module.exports = app;