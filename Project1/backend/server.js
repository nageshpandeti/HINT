const express = require("express");
const mysql = require("mysql2");

const app = express();
const port = 5000;

// Connect to DB using env vars
const db = mysql.createConnection({
  host: process.env.DB_HOST || "db",
  user: process.env.DB_USER || "root",
  password: process.env.DB_PASSWORD || "example",
  database: process.env.DB_NAME || "testdb"
});

app.get("/", (req, res) => {
  db.query("SELECT NOW() AS time", (err, results) => {
    if (err) return res.send("DB error: " + err);
    res.send("Hello from Backend! DB Time: " + results[0].time);
  });
});

app.listen(port, () => {
  console.log(`Backend running on port ${port}`);
});
