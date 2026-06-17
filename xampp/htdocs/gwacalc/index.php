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
    $action = $_GET['action'];

    if ($action === 'toggle' && isset($_GET['id'])) {
        $id = (int)$_GET['id'];
        $mysqli->query("UPDATE subjects SET included = NOT included WHERE id = $id");
        echo json_encode(['success' => true]);
        exit;
    }

    if ($action === 'update_status' && isset($_GET['id']) && isset($_GET['status'])) {
        $id = (int)$_GET['id'];
        $status = $_GET['status'];
        $stmt = $mysqli->prepare("UPDATE subjects SET status = ? WHERE id = ?");
        $stmt->bind_param("si", $status, $id);
        $stmt->execute();
        $stmt->close();
        echo json_encode(['success' => true]);
        exit;
    }

    if ($action === 'update_optimal' && isset($_GET['id']) && isset($_GET['optimal'])) {
        $id = (int)$_GET['id'];
        $optimal = floatval($_GET['optimal']);
        $stmt = $mysqli->prepare("UPDATE subjects SET optimal_grade = ? WHERE id = ?");
        $stmt->bind_param("di", $optimal, $id);
        $stmt->execute();
        $stmt->close();
        echo json_encode(['success' => true]);
        exit;
    }

    if ($action === 'delete' && isset($_GET['id'])) {
        $id = (int)$_GET['id'];
        $mysqli->query("DELETE FROM subjects WHERE id = $id");
        echo json_encode(['success' => true]);
        exit;
    }

    if ($action === 'rename_subject' && isset($_GET['id']) && isset($_GET['new_name'])) {
        $id = (int)$_GET['id'];
        $new_name = trim((string)$_GET['new_name']);
        if ($new_name === '') {
            echo json_encode(['success' => false, 'error' => 'Name cannot be empty']);
            exit;
        }
        $stmt = $mysqli->prepare("UPDATE subjects SET name = ? WHERE id = ?");
        $stmt->bind_param("si", $new_name, $id);
        $stmt->execute();
        $stmt->close();
        echo json_encode(['success' => true]);
        exit;
    }

    // Bulk tag rename: update all subjects matching old tag
    if ($action === 'rename_tag' && isset($_GET['old_tag']) && isset($_GET['new_tag'])) {
        $old_tag = (string)$_GET['old_tag'];
        $new_tag = trim((string)$_GET['new_tag']);

        if ($new_tag === '') {
            echo json_encode(['success' => false, 'error' => 'New tag cannot be empty']);
            exit;
        }

        $stmt = $mysqli->prepare("UPDATE subjects SET tag = ? WHERE tag = ?");
        $stmt->bind_param("ss", $new_tag, $old_tag);
        $stmt->execute();
        $stmt->close();
        echo json_encode(['success' => true]);
        exit;
    }

    // Set include/exclude value for all subjects matching a tag
    if ($action === 'set_include_tag' && isset($_GET['tag']) && isset($_GET['value'])) {
        $tag = $_GET['tag'];
        $value = (int)$_GET['value'];
        $stmt = $mysqli->prepare("UPDATE subjects SET included = ? WHERE tag = ?");
        $stmt->bind_param("is", $value, $tag);
        $stmt->execute();
        $stmt->close();
        echo json_encode(['success' => true]);
        exit;
    }

    // NEW: Update subject included status directly (by id)
    if ($action === 'set_include_subject' && isset($_GET['id']) && isset($_GET['value'])) {
        $id = (int)$_GET['id'];
        $value = (int)$_GET['value'];
        $stmt = $mysqli->prepare("UPDATE subjects SET included = ? WHERE id = ?");
        $stmt->bind_param("ii", $value, $id);
        $stmt->execute();
        $stmt->close();
        echo json_encode(['success' => true]);
        exit;
    }

    // NEW: Update subject tag by id
    if ($action === 'set_tag_subject' && isset($_GET['id']) && isset($_GET['tag'])) {
        $id = (int)$_GET['id'];
        $tag = (string)$_GET['tag'];
        $stmt = $mysqli->prepare("UPDATE subjects SET tag = ? WHERE id = ?");
        $stmt->bind_param("si", $tag, $id);
        $stmt->execute();
        $stmt->close();
        echo json_encode(['success' => true]);
        exit;
    }

    // NEW: Bulk save — replace ALL subjects with data from JSON POST body
    if ($action === 'bulk_save') {
        $input = json_decode(file_get_contents('php://input'), true);
        if (!$input || !isset($input['subjects']) || !is_array($input['subjects'])) {
            echo json_encode(['success' => false, 'error' => 'Invalid data format']);
            exit;
        }
        $mysqli->begin_transaction();
        try {
            $mysqli->query("DELETE FROM subjects");
            $stmt = $mysqli->prepare("INSERT INTO subjects (name, units, gwa, tag, included, status) VALUES (?, ?, ?, ?, ?, ?)");
            foreach ($input['subjects'] as $s) {
                $name = $s['name'] ?? 'Untitled';
                $units = (int)($s['units'] ?? 3);
                $gwa = floatval($s['gwa'] ?? 1.0);
                $tag = $s['tag'] ?? '';
                $included = isset($s['included']) ? (int)$s['included'] : 1;
                $status = $s['status'] ?? 'fixed';
                $stmt->bind_param("sidssi", $name, $units, $gwa, $tag, $status, $included);
                $stmt->execute();
            }
            $stmt->close();
            $mysqli->commit();
            echo json_encode(['success' => true]);
        } catch (Exception $e) {
            $mysqli->rollback();
            echo json_encode(['success' => false, 'error' => $e->getMessage()]);
        }
        exit;
    }

    // NEW: Bulk load — fetch all subjects as JSON for client-side slot loading
    if ($action === 'bulk_load') {
        $result = $mysqli->query("SELECT * FROM subjects ORDER BY id ASC");
        $subjects = [];
        while ($row = $result->fetch_assoc()) {
            $subjects[] = $row;
        }
        echo json_encode(['success' => true, 'subjects' => $subjects]);
        exit;
    }

    // NEW: Clear all subjects
    if ($action === 'clear_all') {
        $mysqli->query("DELETE FROM subjects");
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
        :root{
            --bg: #0b1220;
            --panel: #0f1b2e;
            --panel-2:#0c172a;
            --text: #e7eefc;
            --muted:#a9b6d3;
            --border: rgba(255,255,255,.10);
            --green:#20c997;
            --green-2:#14a77a;
            --green-soft: rgba(32,201,151,.14);
            --danger:#ff5c6c;
            --danger-2:#e64554;
            --warn:#ffcc66;
            --blue:#2ea8ff;
        }
        body { font-family: Arial; padding: 20px; max-width: 1200px; margin: 0 auto; background: var(--bg); color: var(--text); }
        .top-section { background: var(--panel); padding: 16px 18px; border-radius: 10px; margin-bottom: 16px; border: 1px solid var(--border); }
        .top-section h1 { margin-top: 0; }
        .info-row { display: flex; gap: 20px; flex-wrap: wrap; align-items: center; margin: 10px 0; }
        .info-item { display: flex; gap: 10px; align-items: center; }
        .info-item label { font-weight: bold; color: var(--muted); }
        input, button, select { padding: 8px 10px; margin: 5px; border: 1px solid var(--border); border-radius: 8px; background: var(--panel-2); color: var(--text); }
        input::placeholder{ color: rgba(231,238,252,.55); }
        button { background: linear-gradient(180deg, var(--green), var(--green-2)); color: #073b2a; cursor: pointer; border: none; }
        button:hover { filter: brightness(.98); }
        button.danger { background: linear-gradient(180deg, var(--danger), var(--danger-2)); color: #3b0b12; }
        button.danger:hover { filter: brightness(.98); }
        .form-section { background: var(--panel); padding: 15px 16px; border-radius: 10px; margin-bottom: 16px; border: 1px solid var(--border); }
        .form-row { display: flex; gap: 10px; flex-wrap: wrap; margin: 10px 0; }
        .form-row input, .form-row select { flex: 1; min-width: 140px; }
        table { border-collapse: collapse; width: 100%; margin-top: 14px; overflow:hidden; border-radius:10px; border:1px solid var(--border); }
        th, td { border-bottom: 1px solid var(--border); border-right: 1px solid var(--border); padding: 10px; text-align: center; }
        th { background: rgba(32,201,151,.12); color: var(--text); border-top: 1px solid var(--border); }
        tr.excluded { background-color: rgba(255,92,108,.10); }
        tr.included { background-color: rgba(32,201,151,.10); }
        tr.speculation { background-color: rgba(255,204,102,.12); }
        .tag-badge { display: inline-block; background: var(--green-soft); padding: 3px 8px; border-radius: 999px; font-size: 0.85em; border:1px solid rgba(32,201,151,.22); }
        .small-input { width: 90px !important; }
        .optimal-value { font-weight: bold; color: var(--green); }
        .filter-buttons { display: flex; gap: 8px; flex-wrap: wrap; margin: 10px 0; align-items: center; }
        .filter-buttons button { margin: 0; }
        .group-section { margin-bottom: 18px; padding: 14px 15px; background: rgba(255,255,255,.03); border-radius: 10px; border: 1px solid var(--border); }
        .group-section h3 { margin-top: 0; }
        .group-gwa { font-weight: bold; color: var(--blue); margin-left: 10px; }
        .page-title{ margin: 10px 0 14px; }
        .subtle{ color: var(--muted); }
        .menu-row{ display:flex; gap:10px; flex-wrap:wrap; align-items:center; }
        .pill-link{ text-decoration:none; color: var(--text); padding:8px 12px; border-radius: 999px; background: rgba(32,201,151,.22); border:1px solid rgba(32,201,151,.35); font-weight:700; }
        .pill-link.active{ background: rgba(32,201,151,.28); }
        .pill-link.btn-like{ display:inline-block; cursor:pointer; border:none; font-size:inherit; font-family:inherit; }
        .danger-btn{ width: 100%; }
        .row-actions{ display:flex; gap:8px; justify-content:center; flex-wrap:wrap; }

        .top-bar{
            display:flex; align-items:center; gap:10px;
        }
        .top-bar-spacer{ flex:1; }
        .burger{
            width:40px; height:40px; border-radius:10px;
            border:1px solid rgba(32,201,151,.40);
            background: rgba(32,201,151,.25);
            color: var(--text);
            font-size:20px; line-height:40px;
            display:inline-flex;
            align-items:center;
            justify-content:center;
            padding:0;
            flex:0 0 auto;
        }

        .quick-menu{
            display:none;
            position: absolute;
            margin-top:10px;
            background: var(--panel);
            border: 1px solid var(--border);
            border-radius: 12px;
            padding: 10px;
            gap:10px;
            flex-direction: column;
            min-width: 220px;
            z-index: 50;
        }
        .quick-menu .pill-link{ width: 100%; text-align:center; }

        /* Slot modal */
        .modal-overlay {
            display:none;
            position:fixed; top:0; left:0; right:0; bottom:0;
            background: rgba(0,0,0,0.6);
            z-index:1000;
            align-items:center;
            justify-content:center;
        }
        .modal-overlay.show {
            display:flex;
        }
        .modal-box {
            background:var(--panel);
            border:1px solid var(--border);
            border-radius:16px;
            padding:24px;
            min-width:320px;
            max-width:420px;
        }
        .modal-box h3 { margin-top:0; }
        .modal-buttons { display:flex; flex-direction:column; gap:8px; margin-top:14px; }
        .modal-buttons button { width:100%; padding:10px; }
        .modal-buttons .slot-btn { background: var(--panel-2); border:1px solid var(--border); color:var(--text); }
        .modal-buttons .slot-btn:hover { border-color:var(--green); }
        .modal-close { margin-top:12px; background:transparent; color:var(--muted); border:none; width:100%; }
    </style>
</head>
<body>

    <div class="top-section">
        <div class="top-bar" style="position:relative;">
            <button type="button" class="burger" onclick="toggleMenu()" aria-label="Menu" title="Menu">☰</button>
            <div class="page-title" style="margin-left:10px;">
                <h1 style="margin:0; font-size: 1.25em;">GWA Calculator</h1>
                <div class="subtle" style="margin-top:4px;">Sleek green UI</div>
            </div>
            <div class="top-bar-spacer"></div>
            <button type="button" class="pill-link btn-like" style="cursor:pointer;" onclick="newCalculation()">New</button>
            <select id="calc_slot" style="min-width:160px;" onchange="onSlotChange()">
                <option value="1">Slot #1</option>
                <option value="2">Slot #2</option>
                <option value="3">Slot #3</option>
            </select>
            <button type="button" class="pill-link active btn-like" style="cursor:pointer;" onclick="savePrompt()">Save</button>
        </div>

        <div id="quick_menu" class="quick-menu">
            <a class="pill-link" href="#add_subject_section" onclick="closeMenu(); smoothScroll('add_subject_section')">Add Subject</a>
            <a class="pill-link" href="#edit_section" onclick="closeMenu(); smoothScroll('edit_section')">Edit</a>
            <a class="pill-link" href="#subjects_section" onclick="closeMenu(); smoothScroll('subjects_section')">Subjects</a>
            <a class="pill-link" href="#group_filter_section" onclick="closeMenu(); smoothScroll('group_filter_section')">Group/Filter</a>
        </div>

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
    <div class="form-section" id="add_subject_section">
        <h2 style="margin:0 0 10px;">Add New Subject</h2>

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
        <?php if (!empty($error)) echo "<p style='color: var(--danger); margin: 10px 0;'>$error</p>"; ?>

    </div>

    <!-- Grouping and Filtering Options -->
    <div class="form-section" id="group_filter_section">
        <h2 style="margin:0 0 10px;">Grouping & Filtering</h2>

        
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
                        <button type="button" onclick="setIncludeByTag('<?= addslashes($tag) ?>', 1)" style="margin-left:6px;padding:3px 8px;">Include All</button>
                        <button type="button" onclick="setIncludeByTag('<?= addslashes($tag) ?>', 0)" style="margin-left:2px;padding:3px 8px;">Exclude All</button>

                    </label>
                    <?php endforeach; ?>
                    <button type="submit" style="padding:5px 8px; margin-left:8px;">Apply</button>
                </div>
            </form>
        </div>
        <?php endif; ?>
    </div>

    <h2 style="margin: 18px 0 10px;" id="edit_section">Edit</h2>
    <div class="form-section" style="margin-top:0;">
        <div class="menu-row">
            <div style="flex:1; min-width:260px;">
                <h3 style="margin:0 0 8px;">Rename Subject</h3>
                <div class="form-row" style="margin:0;">
                    <select id="edit_subject_id" style="min-width:220px; flex:1;">
                        <option value="">Select subject...</option>
                        <?php foreach ($subjects as $s) { ?>
                            <option value="<?= (int)$s['id'] ?>"><?= htmlspecialchars($s['name']) ?></option>
                        <?php } ?>
                    </select>
                    <input id="edit_subject_name" type="text" placeholder="New subject name" style="flex:1;" />
                </div>
                <div style="margin-top:10px;">
                    <button type="button" onclick="renameSubject()">Rename Subject</button>
                </div>
                <div id="rename_subject_msg" class="subtle" style="margin-top:8px;"></div>
            </div>

            <div style="flex:1; min-width:260px;">
                <h3 style="margin:0 0 8px;">Quick Rename Tag (Bulk)</h3>
                <div class="form-row" style="margin:0;">
                    <select id="rename_tag_old" style="min-width:220px; flex:1;">
                        <option value="">Select old tag...</option>
                        <?php foreach ($tags as $t) { ?>
                            <option value="<?= htmlspecialchars($t, ENT_QUOTES) ?>"><?= htmlspecialchars($t) ?></option>
                        <?php } ?>
                    </select>
                    <input id="rename_tag_new" type="text" placeholder="New tag" style="flex:1;" />
                </div>
                <div style="margin-top:10px;">
                    <button type="button" onclick="renameTag()">Rename Tag</button>
                </div>
                <div id="rename_tag_msg" class="subtle" style="margin-top:8px;"></div>
            </div>
        </div>
    </div>

    <h2 style="margin: 18px 0 10px;" id="subjects_section">Subjects</h2>
    

    
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
        
        // Calculate GWA for this group (only included subjects)
        $group_total_units = 0;
        $group_weighted_sum = 0;
        foreach ($group_items as $sub) {
            if ($sub['included']) {
                $group_total_units += $sub['units'];
                $group_weighted_sum += $sub['units'] * $sub['gwa'];
            }
        }
        $group_gwa = $group_total_units > 0 ? number_format(round($group_weighted_sum / $group_total_units, 3), 3) : 'N/A';
    ?>
    
        <?php if ($group_by !== 'none'): ?>
    <div class="group-section">
        <h3><?= htmlspecialchars($group_name) ?> (<?= count($group_items) ?> subject<?= count($group_items) !== 1 ? 's' : '' ?>)
            <span class="group-gwa">GWA: <?= $group_gwa ?></span>
        </h3>
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
            <tr class="<?= $row_class ?>" data-subject-id="<?= (int)$sub['id'] ?>">

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
                    <button onclick="toggleInclude(<?= $sub['id'] ?>)" style="padding: 6px 10px; width: 92px;">
                        <?= ((int)$sub['included']) ? 'Exclude' : 'Include' ?>
                    </button>

                </td>
                <td>
                    <form method="POST" style="display:inline;">
                        <input type="hidden" name="id" value="<?= $sub['id'] ?>">
                        <input type="text" name="new_tag" value="<?= htmlspecialchars($sub['tag'] ?? '') ?>" placeholder="Tag" class="small-input">
                        <button type="submit" name="update_tag" style="padding: 4px 8px; font-size: 0.85em;">Set</button>
                    </form>
                </td>

                <td>
                    <div class="row-actions">
                        <button class="danger" onclick="deleteSubject(<?= $sub['id'] ?>)" style="padding: 6px 10px; font-size: 0.9em;">Delete</button>
                    </div>
                </td>

            </tr>
        <?php endforeach; ?>
    </table>

    
    <?php if ($group_by !== 'none'): ?>
    </div>
    <?php endif; ?>
    
    <?php endforeach; ?>

    <!-- Slot Save Modal -->
    <div id="slotModal" class="modal-overlay">
        <div class="modal-box">
            <h3>Save to Slot</h3>
            <p class="subtle">Choose a slot to save the current calculation.</p>
            <div class="modal-buttons" id="slotModalButtons">
                <button class="slot-btn" onclick="saveToSlot(1)">Slot #1</button>
                <button class="slot-btn" onclick="saveToSlot(2)">Slot #2</button>
                <button class="slot-btn" onclick="saveToSlot(3)">Slot #3</button>
            </div>
            <button class="modal-close" onclick="closeSlotModal()">Cancel</button>
        </div>
    </div>

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

    function renameSubject() {
        const id = document.getElementById('edit_subject_id').value;
        const newName = document.getElementById('edit_subject_name').value.trim();
        const msg = document.getElementById('rename_subject_msg');

        if (!id) return (msg.textContent = 'Select a subject.');
        if (!newName) return (msg.textContent = 'Enter a new subject name.');

        fetch(`?action=rename_subject&id=${encodeURIComponent(id)}&new_name=${encodeURIComponent(newName)}`)
            .then(res => res.json())
            .then(r => {
                if (!r.success) throw new Error(r.error || 'Failed');
                location.reload();
            })
            .catch(err => {
                console.error(err);
                msg.textContent = err.message;
            });
    }

    function toggleMenu(){
        const m = document.getElementById('quick_menu');
        if(!m) return;
        m.style.display = (m.style.display === 'flex') ? 'none' : 'flex';
    }

    function closeMenu(){
        const m = document.getElementById('quick_menu');
        if(!m) return;
        m.style.display = 'none';
    }

    function smoothScroll(id){
        const el = document.getElementById(id);
        if(el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }

    // ---- Slot save/load modal ----
    function openSlotModal(callback){
        const modal = document.getElementById('slotModal');
        modal.classList.add('show');
        modal._callback = callback || null;
    }

    function closeSlotModal(){
        const modal = document.getElementById('slotModal');
        modal.classList.remove('show');
        modal._callback = null;
    }

    // ---- Core save/load functions ----
    async function fetchSubjectsFromServer(){
        const res = await fetch('?action=bulk_load');
        const data = await res.json();
        if(!data.success) throw new Error('Failed to load subjects');
        return data.subjects;
    }

    async function saveSubjectsToServer(subjects){
        const res = await fetch('?action=bulk_save', {
            method: 'POST',
            headers: {'Content-Type':'application/json'},
            body: JSON.stringify({subjects: subjects})
        });
        const data = await res.json();
        if(!data.success) throw new Error(data.error || 'Save failed');
        return true;
    }

    async function clearAllSubjects(){
        const res = await fetch('?action=clear_all');
        const data = await res.json();
        if(!data.success) throw new Error('Clear failed');
        return true;
    }

    // Save current server state to a localStorage slot
    async function saveToSlot(slot){
        closeSlotModal();
        try {
            const subjects = await fetchSubjectsFromServer();
            const desiredGwa = document.getElementById('desired_gwa') ? document.getElementById('desired_gwa').value : '';
            const payload = {
                subjects: subjects,
                desired_gwa: desiredGwa
            };
            localStorage.setItem('gwa_calc_slot_'+slot, JSON.stringify(payload));
            document.getElementById('calc_slot').value = slot;
            showToast('Saved to Slot #' + slot);
        } catch(e){
            alert('Save failed: ' + e.message);
        }
    }

    // Prompt to save before new/switch
    function savePrompt(){
        openSlotModal();
    }

    // Load from a slot
    async function loadFromSlot(slot){
        const raw = localStorage.getItem('gwa_calc_slot_'+slot);
        if(!raw){
            // Empty slot — just clear everything
            await clearAllSubjects();
            if(document.getElementById('desired_gwa')) document.getElementById('desired_gwa').value = '';
            location.reload();
            return;
        }
        const payload = JSON.parse(raw);
        // Restore subjects
        await saveSubjectsToServer(payload.subjects || []);
        location.reload();
    }

    // "New" — save current to slot first, then clear
    async function newCalculation(){
        openSlotModal();
        // Override slot click behavior temporarily to also clear after save
        const origSlots = [1,2,3];
        const origHandler = saveToSlot;
        window.saveToSlot = async function(slot){
            closeSlotModal();
            try {
                // Save current state
                const subjects = await fetchSubjectsFromServer();
                const desiredGwa = document.getElementById('desired_gwa') ? document.getElementById('desired_gwa').value : '';
                const payload = {subjects, desired_gwa: desiredGwa};
                localStorage.setItem('gwa_calc_slot_'+slot, JSON.stringify(payload));
                document.getElementById('calc_slot').value = slot;
                // Now clear server
                await clearAllSubjects();
                if(document.getElementById('desired_gwa')) document.getElementById('desired_gwa').value = '';
                location.reload();
            } catch(e){
                alert('New calculation failed: ' + e.message);
            }
            window.saveToSlot = origHandler;
        };
        // If modal is closed without saving, restore handler
        const closeBtn = document.querySelector('.modal-close');
        const oldClose = closeBtn.onclick;
        closeBtn.onclick = function(){
            closeSlotModal();
            window.saveToSlot = origHandler;
            closeBtn.onclick = oldClose;
        };
    }

    // Slot dropdown change — auto-save current, load new slot
    async function onSlotChange(){
        const slot = document.getElementById('calc_slot').value;
        if(!confirm('Save current calculation to slot #' + slot + ' and load?')){
            return;
        }
        try {
            // Save current state first
            const subjects = await fetchSubjectsFromServer();
            const desiredGwa = document.getElementById('desired_gwa') ? document.getElementById('desired_gwa').value : '';
            const payload = {subjects, desired_gwa: desiredGwa};
            localStorage.setItem('gwa_calc_slot_'+slot, JSON.stringify(payload));
            // Load from slot
            await loadFromSlot(slot);
        } catch(e){
            alert('Slot switch failed: ' + e.message);
        }
    }

    // Show a small toast notification
    function showToast(msg){
        const div = document.createElement('div');
        div.textContent = msg;
        div.style.cssText = 'position:fixed; bottom:30px; left:50%; transform:translateX(-50%); background:var(--green); color:#073b2a; padding:12px 24px; border-radius:10px; font-weight:bold; z-index:2000; box-shadow:0 4px 20px rgba(0,0,0,0.5); animation:fadeIn 0.3s;';
        document.body.appendChild(div);
        setTimeout(()=>{ div.style.opacity='0'; div.style.transition='opacity 0.5s'; setTimeout(()=>div.remove(),600); }, 2000);
    }

    function renameTag() {

        const oldTag = document.getElementById('rename_tag_old').value;
        const newTag = document.getElementById('rename_tag_new').value.trim();
        const msg = document.getElementById('rename_tag_msg');

        if (!oldTag) return (msg.textContent = 'Select an old tag.');
        if (!newTag) return (msg.textContent = 'Enter a new tag.');

        fetch(`?action=rename_tag&old_tag=${encodeURIComponent(oldTag)}&new_tag=${encodeURIComponent(newTag)}`)
            .then(res => res.json())
            .then(r => {
                if (!r.success) throw new Error(r.error || 'Failed');
                location.reload();
            })
            .catch(err => {
                console.error(err);
                msg.textContent = err.message;
            });
    }
    </script>


</body>
</html>