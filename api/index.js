const express = require('express');
const app = express();

app.use(express.json());

app.get('/', (req, res) => {
  res.send("🚀 Crash Reporter Backend is Running!");
});

app.post('/crashes', (req, res) => {
  try {
    const crash = req.body;
    
    console.log("🚨 NEW CRASH REPORT:");
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