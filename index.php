<?php
// change root username and password to your own (for this, we use my set up)
// open on localhost/(foldername)/index.php
$mysqli = new mysqli("localhost", "root", "root", "gwa_db");

if ($mysqli->connect_error) {
    die("Connection failed: " . $mysqli->connect_error);
}

header('Content-Type: application/json');

// Handle AJAX requests
if (isset($_GET['action'])) {
    if ($_GET['action'] === 'toggle' && isset($_GET['id'])) {
        $id = (int)$_GET['id'];
        $mysqli->query("UPDATE subjects SET included = NOT included WHERE id = $id");
        echo json_encode(['success' => true]);
        exit;
    }
    
    if ($_GET['action'] === 'update_status' && isset($_GET['id']) && isset($_GET['status'])) {
        $id = (int)$_GET['id'];
        $status = $_GET['status'];
        $stmt = $mysqli->prepare("UPDATE subjects SET status = ? WHERE id = ?");
        $stmt->bind_param("si", $status, $id);
        $stmt->execute();
        $stmt->close();
        echo json_encode(['success' => true]);
        exit;
    }
    
    if ($_GET['action'] === 'update_optimal' && isset($_GET['id']) && isset($_GET['optimal'])) {
        $id = (int)$_GET['id'];
        $optimal = floatval($_GET['optimal']);
        $stmt = $mysqli->prepare("UPDATE subjects SET optimal_grade = ? WHERE id = ?");
        $stmt->bind_param("di", $optimal, $id);
        $stmt->execute();
        $stmt->close();
        echo json_encode(['success' => true]);
        exit;
    }
    
    if ($_GET['action'] === 'delete' && isset($_GET['id'])) {
        $id = (int)$_GET['id'];
        $mysqli->query("DELETE FROM subjects WHERE id = $id");
        echo json_encode(['success' => true]);
        exit;
    }

    // Set include/exclude value for all subjects matching a tag
    if ($_GET['action'] === 'set_include_tag' && isset($_GET['tag']) && isset($_GET['value'])) {
        $tag = $_GET['tag'];
        $value = (int)$_GET['value'];
        $stmt = $mysqli->prepare("UPDATE subjects SET included = ? WHERE tag = ?");
        $stmt->bind_param("is", $value, $tag);
        $stmt->execute();
        $stmt->close();
        echo json_encode(['success' => true]);
        exit;
    }
}

header('Content-Type: text/html');

// Add Subject
if ($_SERVER["REQUEST_METHOD"] === "POST" && isset($_POST["add_subject"])) {
    $name = $_POST["name"];
    $units = (int) $_POST["units"];
    $gwa = floatval($_POST["gwa"]);
    $tag = $_POST["tag"] ?? null;
    $status = $_POST["status"] ?? "fixed";

    if ($gwa < 1 || $gwa > 5 || fmod($gwa * 100, 25) !== 0.0) {
        $error = "Invalid GWA format";
    } else {
        $stmt = $mysqli->prepare("INSERT INTO subjects (name, units, gwa, tag, status) VALUES (?, ?, ?, ?, ?)");
        $stmt->bind_param("sidss", $name, $units, $gwa, $tag, $status);
        $stmt->execute();
        $stmt->close();
    }
}

// Update GWA (AJAX)
if ($_SERVER["REQUEST_METHOD"] === "POST" && isset($_POST["update_gwa"])) {
    $id = (int)$_POST["id"];
    $new_gwa = floatval($_POST["new_gwa"]);

    if ($new_gwa >= 1 && $new_gwa <= 5 && fmod($new_gwa * 100, 25) === 0.0) {
        $stmt = $mysqli->prepare("UPDATE subjects SET gwa = ? WHERE id = ?");
        $stmt->bind_param("di", $new_gwa, $id);
        $stmt->execute();
        $stmt->close();
    } else {
        $error = "Invalid GWA format";
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

// Fetch all subjects
$result = $mysqli->query("SELECT * FROM subjects ORDER BY id DESC");
$subjects = [];
while ($row = $result->fetch_assoc()) {
    $subjects[] = $row;
}

// Get unique tags and group by tag
$tags_result = $mysqli->query("SELECT DISTINCT tag FROM subjects WHERE tag <> '' AND tag IS NOT NULL ORDER BY tag ASC");
$tags = [];
while ($row = $tags_result->fetch_assoc()) {
    $tags[] = $row['tag'];
}

// Grouping option
$group_by = $_GET['group'] ?? 'none';
$filter_tags = isset($_GET['filter_tags']) ? (array)$_GET['filter_tags'] : [];
if (isset($_GET['clear'])) {
    $filter_tags = [];
}
$filter_active = !empty($filter_tags);

// Calculate GWA
$total_units = 0;
$weighted_sum = 0;
$speculation_needed = [];

foreach ($subjects as $sub) {
    if ($sub['included']) {
        // Apply tag filter (support multiple tags)
        if ($filter_active && !in_array($sub['tag'], $filter_tags)) {
            continue;
        }
        
        $total_units += $sub['units'];
        $weighted_sum += $sub['units'] * $sub['gwa'];
    }
}
$current_gwa = $total_units > 0 ? round($weighted_sum / $total_units, 3) : "N/A";

// Calculate optimal grades for speculation items
$desired_gwa = isset($_POST["desired_gwa"]) ? floatval($_POST["desired_gwa"]) : null;
if ($desired_gwa && $desired_gwa >= 1 && $desired_gwa <= 5) {
    foreach ($subjects as $key => &$sub) {
        if ($sub['status'] === 'speculation' && $sub['included']) {
            // required_gpa = (desired_gpa * total_units - (weighted_sum - current_subject_contribution)) / subject_units
            $other_weighted = $weighted_sum - ($sub['units'] * $sub['gwa']);
            $optimal = ($desired_gwa * $total_units - $other_weighted) / $sub['units'];
            $optimal = round(max(1, min(5, $optimal)), 2);
            $sub['optimal_needed'] = $optimal;
        }
    }
    unset($sub);
}
?>

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>GWA Calculator</title>
    <style>
        * { box-sizing: border-box; }
        body { font-family: Arial; padding: 20px; max-width: 1200px; margin: 0 auto; }
        .top-section { background: #f9f9f9; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .top-section h1 { margin-top: 0; }
        .info-row { display: flex; gap: 20px; flex-wrap: wrap; align-items: center; margin: 10px 0; }
        .info-item { display: flex; gap: 10px; align-items: center; }
        .info-item label { font-weight: bold; }
        input, button, select { padding: 8px; margin: 5px; border: 1px solid #ddd; border-radius: 3px; }
        button { background: #007bff; color: white; cursor: pointer; border: none; }
        button:hover { background: #0056b3; }
        button.danger { background: #dc3545; }
        button.danger:hover { background: #c82333; }
        .form-section { background: #f9f9f9; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .form-row { display: flex; gap: 10px; flex-wrap: wrap; margin: 10px 0; }
        .form-row input, .form-row select { flex: 1; min-width: 100px; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th, td { border: 1px solid #ccc; padding: 10px; text-align: center; }
        th { background: #007bff; color: white; }
        tr.excluded { background-color: #f8d7da; }
        tr.included { background-color: #d4edda; }
        tr.speculation { background-color: #fff3cd; }
        .tag-badge { display: inline-block; background: #e9ecef; padding: 3px 8px; border-radius: 3px; font-size: 0.85em; }
        .controls-cell { display: flex; gap: 5px; justify-content: center; flex-wrap: wrap; }
        .small-input { width: 80px !important; }
        .optimal-value { font-weight: bold; color: #007bff; }
        .filter-buttons { display: flex; gap: 5px; flex-wrap: wrap; margin: 10px 0; }
        .filter-buttons button { padding: 5px 10px; font-size: 0.9em; }
        .filter-buttons button.active { background: #28a745; }
        .group-section { margin-bottom: 30px; padding: 15px; background: #f0f0f0; border-radius: 5px; }
        .group-section h3 { margin-top: 0; }
    </style>
</head>
<body>
    <div class="top-section">
        <h1>📊 GWA Calculator</h1>
        
        <div class="info-row">
            <div class="info-item">
                <label>Current GWA:</label>
                <span style="font-size: 1.3em; font-weight: bold; color: #007bff;">
                    <?= is_numeric($current_gwa) ? number_format($current_gwa, 3) : $current_gwa ?>
                </span>
            </div>
            <div class="info-item">
                <label>Total Units:</label>
                <span style="font-size: 1.1em; font-weight: bold;"><?= $total_units ?></span>
            </div>
        </div>

        <form method="POST" style="display: inline;">
            <div class="info-row">
                <div class="info-item">
                    <label for="desired_gwa">Desired GWA:</label>
                    <input type="number" id="desired_gwa" name="desired_gwa" step="0.01" min="1" max="5" 
                           value="<?= htmlspecialchars($desired_gwa ?? '') ?>" class="small-input" placeholder="e.g., 2.0">
                </div>
                <button type="submit" name="set_desired">Set Target</button>
            </div>
        </form>
    </div>

    <!-- Add Subject Form -->
    <div class="form-section">
        <h2>➕ Add New Subject</h2>
        <form method="POST">
            <div class="form-row">
                <input type="text" name="name" placeholder="Subject Name" required>
                <input type="number" name="units" placeholder="Units" required min="1" max="6" value="3" class="small-input">
                <input type="number" name="gwa" placeholder="GWA (e.g. 1.75)" step="0.25" min="1" max="5" value="1.0" required class="small-input">
                <input type="text" name="tag" placeholder="Tag (e.g., Major, Minor)">
                <select name="status">
                    <option value="fixed">Fixed</option>
                    <option value="speculation">Speculation</option>
                </select>
                <button type="submit" name="add_subject">Add Subject</button>
            </div>
        </form>
        <?php if (!empty($error)) echo "<p style='color: red; margin: 10px 0;'>❌ $error</p>"; ?>
    </div>

    <!-- Grouping and Filtering Options -->
    <div class="form-section">
        <h2>🏷️ Grouping & Filtering</h2>
        
        <div style="margin-bottom: 15px;">
            <label>Group by:</label>
            <div class="filter-buttons">
                <a href="?group=none&clear=1" class="<?= $group_by === 'none' ? 'active' : '' ?>" 
                   style="text-decoration: none; background: #007bff; color: white; padding: 8px 12px; border-radius: 3px; cursor: pointer;">
                    None
                </a>
                <a href="?group=tag&clear=1" class="<?= $group_by === 'tag' ? 'active' : '' ?>" 
                   style="text-decoration: none; background: #007bff; color: white; padding: 8px 12px; border-radius: 3px; cursor: pointer;">
                    By Tag
                </a>
                <a href="?group=status&clear=1" class="<?= $group_by === 'status' ? 'active' : '' ?>" 
                   style="text-decoration: none; background: #007bff; color: white; padding: 8px 12px; border-radius: 3px; cursor: pointer;">
                    By Status (Fixed/Speculation)
                </a>
            </div>
        </div>

        <?php if (!empty($tags)): ?>
        <div>
            <form method="GET" style="display:inline-block;">
                <input type="hidden" name="group" value="<?= htmlspecialchars($group_by) ?>">
                <label>Filter by Tags (multiple):</label>
                <div class="filter-buttons">
                    <button type="submit" name="clear" value="1" style="padding:5px 10px; margin-right:8px;">Clear</button>
                    <?php foreach ($tags as $tag): ?>
                    <label style="display:inline-flex; align-items:center; gap:6px; margin-right:6px;">
                        <input type="checkbox" name="filter_tags[]" value="<?= htmlspecialchars($tag) ?>" <?= in_array($tag, $filter_tags) ? 'checked' : '' ?>>
                        <span class="tag-badge"><?= htmlspecialchars($tag) ?></span>
                        <button type="button" onclick="setIncludeByTag('<?= addslashes($tag) ?>', 1)" style="margin-left:6px;padding:3px 6px;">Include All</button>
                        <button type="button" onclick="setIncludeByTag('<?= addslashes($tag) ?>', 0)" style="margin-left:2px;padding:3px 6px;">Exclude All</button>
                    </label>
                    <?php endforeach; ?>
                    <button type="submit" style="padding:5px 8px; margin-left:8px;">Apply</button>
                </div>
            </form>
        </div>
        <?php endif; ?>
    </div>

    <h2>📋 Subjects</h2>
    
    <?php
    // Group subjects for display
    $grouped_subjects = [];
    
    if ($group_by === 'tag') {
        foreach ($subjects as $sub) {
            if ($filter_active && !in_array($sub['tag'], $filter_tags)) continue;
            $key = $sub['tag'] ?: 'No Tag';
            $grouped_subjects[$key][] = $sub;
        }
    } elseif ($group_by === 'status') {
        foreach ($subjects as $sub) {
            if ($filter_active && !in_array($sub['tag'], $filter_tags)) continue;
            $key = ucfirst($sub['status'] ?? 'fixed');
            $grouped_subjects[$key][] = $sub;
        }
    } else {
        $grouped_subjects['All Subjects'] = array_values(array_filter($subjects, function($sub) use ($filter_active, $filter_tags) {
            return !$filter_active || in_array($sub['tag'], $filter_tags);
        }));
    }
    
    foreach ($grouped_subjects as $group_name => $group_items):
        if (empty($group_items)) continue;
    ?>
    
    <?php if ($group_by !== 'none'): ?>
    <div class="group-section">
        <h3><?= htmlspecialchars($group_name) ?> (<?= count($group_items) ?> subject<?= count($group_items) !== 1 ? 's' : '' ?>)</h3>
    <?php endif; ?>
    
    <table>
        <tr>
            <th>Subject</th>
            <th>Units</th>
            <th>Grade</th>
            <th>Status</th>
            <?php if ($desired_gwa): ?>
            <th>Optimal Grade</th>
            <?php endif; ?>
            <th>Included</th>
            <th>Tag</th>
            <th>Actions</th>
        </tr>
        <?php foreach ($group_items as $sub):
            $row_class = $sub['included'] ? 'included' : 'excluded';
            if ($sub['status'] === 'speculation' && $sub['included']) $row_class = 'speculation';
        ?>
            <tr class="<?= $row_class ?>">
                <td style="text-align: left;"><?= htmlspecialchars($sub['name']) ?></td>
                <td><?= $sub['units'] ?></td>
                <td>
                    <form method="POST" style="display:inline;" onsubmit="handleUpdate(event, 'gwa')">
                        <input type="hidden" name="id" value="<?= $sub['id'] ?>">
                        <input type="number" step="0.25" min="1" max="5" name="new_gwa" value="<?= number_format($sub['gwa'], 2) ?>" required class="small-input">
                        <button type="submit" name="update_gwa" style="padding: 4px 8px; font-size: 0.85em;">Save</button>
                    </form>
                </td>
                <td>
                    <select onchange="updateStatus(<?= $sub['id'] ?>, this.value)" style="padding: 4px; font-size: 0.85em;">
                        <option value="fixed" <?= $sub['status'] === 'fixed' ? 'selected' : '' ?>>Fixed</option>
                        <option value="speculation" <?= $sub['status'] === 'speculation' ? 'selected' : '' ?>>Speculation</option>
                    </select>
                </td>
                <?php if ($desired_gwa && $sub['status'] === 'speculation' && $sub['included']): ?>
                <td>
                    <span class="optimal-value"><?= htmlspecialchars($sub['optimal_needed'] ?? 'N/A') ?></span>
                </td>
                <?php elseif ($desired_gwa): ?>
                <td>—</td>
                <?php endif; ?>
                <td>
                    <button onclick="toggleInclude(<?= $sub['id'] ?>)" style="padding: 5px 10px; width: 80px;">
                        <?= ((int)$sub['included']) ? 'Exclude' : 'Include' ?>
                    </button>
                </td>
                <td>
                    <form method="POST" style="display:inline;">
                        <input type="hidden" name="id" value="<?= $sub['id'] ?>">
                        <input type="text" name="new_tag" value="<?= htmlspecialchars($sub['tag'] ?? '') ?>" placeholder="Add tag" class="small-input">
                        <button type="submit" name="update_tag" style="padding: 4px 8px; font-size: 0.85em;">Set</button>
                    </form>
                </td>
                <td>
                    <button class="danger" onclick="deleteSubject(<?= $sub['id'] ?>)" style="padding: 5px 10px; font-size: 0.85em;">Delete</button>
                </td>
            </tr>
        <?php endforeach; ?>
    </table>
    
    <?php if ($group_by !== 'none'): ?>
    </div>
    <?php endif; ?>
    
    <?php endforeach; ?>

    <script>
    function toggleInclude(id) {
        fetch(`?action=toggle&id=${id}`)
            .then(res => res.json())
            .then(() => location.reload())
            .catch(err => console.error('Error:', err));
    }

    function updateStatus(id, status) {
        fetch(`?action=update_status&id=${id}&status=${status}`)
            .then(res => res.json())
            .then(() => location.reload())
            .catch(err => console.error('Error:', err));
    }

    function deleteSubject(id) {
        if (confirm('Are you sure you want to delete this subject?')) {
            fetch(`?action=delete&id=${id}`)
                .then(res => res.json())
                .then(() => location.reload())
                .catch(err => console.error('Error:', err));
        }
    }

    function handleUpdate(event, type) {
        event.preventDefault();
        const form = event.target;
        const formData = new FormData(form);
        const id = formData.get('id');
        
        if (type === 'gwa') {
            const newGwa = formData.get('new_gwa');
            formData.append('update_gwa', '1');
            fetch('?', {
                method: 'POST',
                body: formData
            }).then(() => location.reload())
            .catch(err => console.error('Error:', err));
        }
    }

    function setIncludeByTag(tag, value) {
        fetch(`?action=set_include_tag&tag=${encodeURIComponent(tag)}&value=${value}`)
            .then(res => res.json())
            .then(() => location.reload())
            .catch(err => console.error('Error:', err));
    }
    </script>

</body>
</html>
