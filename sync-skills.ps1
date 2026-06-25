# sync-skills.ps1 — called by Claude Code PostToolUse hook after editing SKILL.md files.
# Reads the tool event from stdin, exits silently if the edited file is not a house-hunt skill.
# When a skill IS edited, copies all 9 skill files to the repo and commits+pushes if changed.

param()

$skills = @(
    "redfin-lookup",
    "property-comps",
    "property-schools",
    "property-crime",
    "property-commute",
    "property-homefit",
    "property-score",
    "buyer-profile",
    "property-baseline"
)

$repo = "C:\Users\mgome\Documents\projects\house-hunt"
$src  = "C:\Users\mgome\.claude\skills"

# Read stdin JSON from the hook event
try {
    $raw = [Console]::In.ReadToEnd()
    $event = $raw | ConvertFrom-Json
    $filePath = $event.tool_input.file_path
} catch {
    exit 0
}

# Only proceed if the edited file is a SKILL.md inside one of our tracked skill dirs
$isSkillFile = $filePath -match [regex]::Escape($src) -and $filePath -match 'SKILL\.md$'
if (-not $isSkillFile) {
    exit 0
}

# Copy all skill files to the repo
foreach ($s in $skills) {
    $srcFile  = Join-Path $src  "$s\SKILL.md"
    $destFile = Join-Path $repo "skills\$s\SKILL.md"
    if (Test-Path $srcFile) {
        Copy-Item $srcFile $destFile -Force
    }
}

# Commit and push only if something changed
Set-Location $repo
$changed = git status --porcelain skills/
if ($changed) {
    git add skills/
    git commit -m "Sync skill updates from ~/.claude/skills"
    git push
}
