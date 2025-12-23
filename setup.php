<?php
// Setup script to initialize or upgrade the database
$mysqli = new mysqli("localhost", "root", "root", "gwa_db");

if ($mysqli->connect_error) {
    die("Connection failed: " . $mysqli->connect_error);
}

// Create database if it doesn't exist
$mysqli->query("CREATE DATABASE IF NOT EXISTS gwa_db");
$mysqli->select_db("gwa_db");

// Check if table exists and has all columns
$result = $mysqli->query("SHOW COLUMNS FROM subjects");

if (!$result) {
    // Table doesn't exist, create it
    $sql = "CREATE TABLE subjects (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        units INT NOT NULL,
        gwa FLOAT NOT NULL,
        tag VARCHAR(255),
        included BOOLEAN DEFAULT 1,
        status VARCHAR(50) DEFAULT 'fixed',
        optimal_grade FLOAT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )";
    
    if ($mysqli->query($sql)) {
        echo "✅ Table created successfully!";
    } else {
        echo "❌ Error creating table: " . $mysqli->error;
    }
} else {
    // Table exists, check for new columns
    $columns = [];
    while ($row = $result->fetch_assoc()) {
        $columns[] = $row['Field'];
    }
    
    $updates = [];
    if (!in_array('status', $columns)) {
        $updates[] = "ALTER TABLE subjects ADD COLUMN status VARCHAR(50) DEFAULT 'fixed'";
    }
    if (!in_array('optimal_grade', $columns)) {
        $updates[] = "ALTER TABLE subjects ADD COLUMN optimal_grade FLOAT";
    }
    
    if (!empty($updates)) {
        foreach ($updates as $sql) {
            if ($mysqli->query($sql)) {
                echo "✅ Column added successfully!<br>";
            } else {
                echo "❌ Error: " . $mysqli->error . "<br>";
            }
        }
    } else {
        echo "✅ Database is up to date!";
    }
}

$mysqli->close();
?>
