<?php
// change root username and password to your own (for this, we use my set up)
// open on localhost/(foldername)/index.php
$mysqli = new mysqli("localhost", "root", "root", "gwa_db");

if ($mysqli->connect_error) {
    die("Connection failed: " . $mysqli->connect_error);
}

// Add Subject
if ($_SERVER["REQUEST_METHOD"] === "POST" && isset($_POST["add_subject"])) {
    $name = $_POST["name"];
    $units = (int) $_POST["units"];
    $gwa = floatval($_POST["gwa"]);
    $tag = $_POST["tag"] ?? null; // Optional tag

    if ($gwa < 1 || $gwa > 5 || fmod($gwa * 100, 25) !== 0.0) {
        $error = "Invalid";
    } else {
        $stmt = $mysqli->prepare("INSERT INTO subjects (name, units, gwa, tag) VALUES (?, ?, ?, ?)");
    $stmt->bind_param("sids", $name, $units, $gwa, $tag);
        $stmt->execute();
        $stmt->close();
    }
}

// Toggle include/exclude
if (isset($_GET['toggle'])) {
    $id = (int)$_GET['toggle'];
    $mysqli->query("UPDATE subjects SET included = NOT included WHERE id = $id");
    header("Location: index.php");
    exit;
}

// Bulk enable/disable
if (isset($_GET['bulk_tag']) && isset($_GET['action'])) {
    $tag = $_GET['bulk_tag'];
    $include = $_GET['action'] === 'enable' ? 1 : 0;
    $stmt = $mysqli->prepare("UPDATE subjects SET included = ? WHERE tag = ?");
    $stmt->bind_param("is", $include, $tag);
    $stmt->execute();
    $stmt->close();
    header("Location: index.php");
    exit;
}


// Update GWA
if ($_SERVER["REQUEST_METHOD"] === "POST" && isset($_POST["update_gwa"])) {
    $id = (int)$_POST["id"];
    $new_gwa = floatval($_POST["new_gwa"]);

    if ($new_gwa >= 1 && $new_gwa <= 5 && fmod($new_gwa * 100, 25) === 0.0) {
        $stmt = $mysqli->prepare("UPDATE subjects SET gwa = ? WHERE id = ?");
        $stmt->bind_param("di", $new_gwa, $id);
        $stmt->execute();
        $stmt->close();
    } else {
        $error = "Invalid";
    }
}

if ($_SERVER["REQUEST_METHOD"] === "POST" && isset($_POST["update_tag"])) {
    $id = (int)$_POST["id"];
    $new_tag = $_POST["new_tag"];
    $stmt = $mysqli->prepare("UPDATE subjects SET tag = ? WHERE id = ?");
    $stmt->bind_param("si", $new_tag, $id);
    $stmt->execute();
    $stmt->close();
}


// Handle delete
if (isset($_GET['delete'])) {
    $id = (int)$_GET['delete'];
    $mysqli->query("DELETE FROM subjects WHERE id = $id");
    header("Location: index.php");
    exit;
}

// Fetch all subjects
$result = $mysqli->query("SELECT * FROM subjects ORDER BY id DESC");
$subjects = [];
while ($row = $result->fetch_assoc()) {
    $subjects[] = $row;
}

// Calculate GWA
$total_units = 0;
$weighted_sum = 0;
foreach ($subjects as $sub) {
    if ($sub['included']) {
        $total_units += $sub['units'];
        $weighted_sum += $sub['units'] * $sub['gwa'];
    }
}
$gwa_result = $total_units > 0 ? round($weighted_sum / $total_units, 3) : "N/A"; // if units exist, calculate GWA
?>

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>GWA Calculator</title>
    <style>
        body { font-family: Arial; padding: 20px; }
        input, button { padding: 5px; margin: 5px; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th, td { border: 1px solid #ccc; padding: 10px; text-align: center; }
        .excluded { background-color: #f8d7da; }
        .included { background-color: #d4edda; }
    </style>
</head>
<body>
    <h1>GWA Calculator</h1>

    <form method="POST">
        <input type="text" name="name" placeholder="Subject Name" required>
        <input type="number" name="units" placeholder="Units" required min="1", max="6", value="3">
        <input type="number" name="gwa" placeholder="GWA (e.g. 1.75)" step="0.25" min="1" max="5" value="1.0" required>
        <input type="text" name="tag" placeholder="Tag (e.g. Major)" style="min-width: 100px;">

        <button type="submit" name="add_subject">Add Subject</button>
    </form>

    <h2>Bulk Toggle by Tag</h2>
    <?php
    $tags_result = $mysqli->query("SELECT DISTINCT tag FROM subjects WHERE tag <> '' ORDER BY tag ASC"); //<> means tag is not empty
    while ($row = $tags_result->fetch_assoc()):
        $tag = htmlspecialchars($row['tag']);   
    ?>
        <div style="margin-bottom: 10px;">
            <strong><?= $tag ?></strong>
            <a href="?bulk_tag=<?= urlencode($row['tag']) ?>&action=enable">Enable All</a> |
            <a href="?bulk_tag=<?= urlencode($row['tag']) ?>&action=disable">Disable All</a>
        </div>
    <?php endwhile; ?>


    <?php if (!empty($error)) echo "<p style='color: red;'>$error</p>"; ?>

    <h2>Subjects</h2>
    <table>
        <tr>
            <th>Subject</th>
            <th>Units</th>
            <th>GWA</th>
            <th>Included</th>
            <th>Actions</th>
            <th>Tag</th>
            <th>Edit Tag</th>
            <th style="color: red;">Delete?</th>
        </tr>
        <?php foreach ($subjects as $sub): ?>
            <tr class="<?= $sub['included'] ? 'included' : 'excluded' ?>">
                <td><?= htmlspecialchars($sub['name']) ?></td>
                <td><?= $sub['units'] ?></td>
                <td>
                    <form method="POST" style="display:inline;">
                        <input type="hidden" name="id" value="<?= $sub['id'] ?>">
                        <input type="number" step="0.25" min="1" max="5" name="new_gwa" value="<?= number_format($sub['gwa'], 2) ?>" required>
                        <button type="submit" name="update_gwa">Save</button>
                    </form>
                </td>
                <td><?= $sub['included'] ? "Yes" : "No" ?></td>
                <td><a href="?toggle=<?= $sub['id'] ?>">Toggle</a></td>
                <td><?= !empty($sub['tag']) ? htmlspecialchars($sub['tag']) : 'N/A' ?></td>
                <td>
                    <form method="POST" style="display:inline;">
                        <input type="hidden" name="id" value="<?= $sub['id'] ?>">
                        <input type="text" name="new_tag" value="<?= htmlspecialchars($sub['tag']) ?>" placeholder="N/A">
                    <button type="submit" name="update_tag">Set</button>
                    </form>
                </td>
                <td>
                <a href="?delete=<?= $sub['id'] ?>" onclick="return confirm('Are you sure you want to delete this subject?');">Delete</a>
               </td>

            </tr>
        <?php endforeach; ?>
    </table>

    <h2>Computed GWA: <?= is_numeric($gwa_result) ? number_format($gwa_result, 3) : $gwa_result ?></h2>

</body>
</html>
