# Pulls all current PSMF leagues (podzim 2026) from psmf.cz into data/<league>.json + data/index.json
# Run:  powershell -ExecutionPolicy Bypass -File scrape-psmf.ps1            (all leagues, ~10-15 min)
#       powershell -ExecutionPolicy Bypass -File scrape-psmf.ps1 -Only fut   (one league)
param(
  [string]$Year = "2026", [string]$Part = "podzim",
  [string[]]$Only = @(),
  [string]$OutDir = (Join-Path $PSScriptRoot "data")
)
$ErrorActionPreference = "Stop"
$base = "https://www.psmf.cz"
$script:xhrHeaders = @{ "X-Requested-With" = "XMLHttpRequest" }
$leagues = @(
  @{ key = "hl";   path = "hanspaulska-liga";      name = "Hanspaulská liga" },
  @{ key = "vet";  path = "veteranska-liga";       name = "Veteránská liga" },
  @{ key = "svet"; path = "superveteranska-liga";  name = "Superveteránská liga" },
  @{ key = "uvet"; path = "ultraveteranska-liga";  name = "Ultraveteránská liga" },
  @{ key = "fut";  path = "futsal";                name = "Futsal" }
)

function Get-Html([string]$url, [switch]$Ajax) {
  Start-Sleep -Milliseconds 200   # be polite to the server
  $h = @{}; if ($Ajax) { $h = $script:xhrHeaders }
  for ($i = 0; $i -lt 3; $i++) {
    try { $c = (Invoke-WebRequest -UseBasicParsing -Headers $h $url).Content; break }
    catch { if ($i -eq 2) { throw }; Start-Sleep -Seconds 2 }
  }
  if ($c.TrimStart().StartsWith('{"html"')) { $c = ($c | ConvertFrom-Json).html }
  return $c
}
function Clean([string]$s) {
  $s = [regex]::Replace($s, '<[^>]+>', ' ')
  $s = [System.Net.WebUtility]::HtmlDecode($s)
  return ([regex]::Replace($s, '\s+', ' ')).Trim()
}
function Rows([string]$html) {
  $rows = @()
  foreach ($tr in [regex]::Matches($html, '(?s)<tr[^>]*>(.*?)</tr>')) {
    $tds = [regex]::Matches($tr.Groups[1].Value, '(?s)<td[^>]*>(.*?)</td>')
    if ($tds.Count -gt 0) { $rows += ,@($tds | ForEach-Object { $_.Groups[1].Value }) }
  }
  return $rows
}
function Teams([string]$cell) {
  return @([regex]::Matches($cell, '<a href="[^"]*/tymy/([^/"]+)/" title="([^"]*)"') | ForEach-Object {
    @{ slug = $_.Groups[1].Value; name = [System.Net.WebUtility]::HtmlDecode($_.Groups[2].Value) } })
}
function Games([string]$html, [string]$round) {
  $list = @()
  foreach ($r in (Rows $html)) {
    if ($r.Count -lt 4) { continue }
    $t = @(Teams $r[3]); if ($t.Count -lt 2) { continue }
    $g = [ordered]@{ date = (Clean $r[0]); time = (Clean $r[1]); pitch = (Clean $r[2])
      home = $t[0].name; homeSlug = $t[0].slug; away = $t[1].name; awaySlug = $t[1].slug; round = $round }
    if ($r.Count -ge 5) {
      $last = Clean $r[$r.Count - 1]
      if ($r.Count -ge 6 -or $last -match '\d+:\d+') { $g.score = $last }
      if ($r.Count -ge 6) { $g.round = (Clean $r[4]).TrimEnd('.') }
      elseif ($last -notmatch ':') { $g.round = $last.TrimEnd('.') }
    }
    $list += $g
  }
  return $list
}
function GroupId([string]$gs) {
  if ($gs -match '^(\d+)-([a-z])$') { return $Matches[1] + $Matches[2].ToUpper() }
  $parts = $gs.Split('-'); $letter = $parts[-1].ToUpper()
  $prefix = ($parts[0..($parts.Count - 2)] | ForEach-Object { $_.Substring(0, 1).ToUpper() }) -join ''
  return "$prefix$letter"
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
$index = @()
foreach ($lg in $leagues) {
  $season = "$Year-$($lg.path)-$Part"
  $file = "$($lg.key).json"
  if ($Only.Count -and $Only -notcontains $lg.key) {
    $old = Join-Path $OutDir $file
    if (Test-Path $old) { $index += [ordered]@{ key = $lg.key; name = $lg.name; season = $season; file = "data/$file"; source = "$base/souteze/$season/" } }
    continue
  }
  Write-Host "== $($lg.name) ($season)"
  $main = Get-Html "$base/souteze/$season/"
  $groupSlugs = [regex]::Matches($main, "/souteze/$season/([a-z0-9-]+-[a-z])/") | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
  $groups = @()
  foreach ($gs in $groupSlugs) {
    Write-Host "  group $gs"
    $page = Get-Html "$base/souteze/$season/$gs/"
    $title = Clean ([regex]::Match($page, '(?s)<h1 class="component__title">(.*?)</h1>').Groups[1].Value)
    $m = [regex]::Match($page, 'competition=(\d+)&(?:amp;)?year=(\d+)&(?:amp;)?season=(\d+)&(?:amp;)?league=(\d+)&(?:amp;)?group_id=(\d+)')
    if (-not $m.Success) { Write-Host "    (no data ids, skipped)"; continue }
    $q = "competition=$($m.Groups[1].Value)&year=$($m.Groups[2].Value)&season=$($m.Groups[3].Value)&league=$($m.Groups[4].Value)&group_id=$($m.Groups[5].Value)"
    $u = "$base/souteze/$season/$gs/?$q"
    $table = @()
    foreach ($r in (Rows (Get-Html "$u&cmd=tables&type=actual" -Ajax))) {
      if ($r.Count -lt 8) { continue }
      $t = @(Teams $r[1]); if ($t.Count -lt 1) { continue }
      $sc = (Clean $r[6]) -split ':'
      $table += [ordered]@{ pos = [int]((Clean $r[0]).TrimEnd('.')); team = $t[0].name; slug = $t[0].slug
        p = [int](Clean $r[2]); w = [int](Clean $r[3]); d = [int](Clean $r[4]); l = [int](Clean $r[5])
        gf = [int]$sc[0]; ga = [int]$sc[1]; pts = [int](Clean $r[7]) }
    }
    $rounds = [regex]::Matches($page, 'cmd=games&(?:amp;)?type=old[^"]*&(?:amp;)?round=(\d+)') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique
    $results = @()
    foreach ($rd in $rounds) { $results += Games (Get-Html "$u&cmd=games&type=old&round=$rd" -Ajax) "$rd" }
    $results = @($results | Where-Object { $_.score })
    $fixtures = @(Games (Get-Html "$u&cmd=games&type=new" -Ajax) "")
    $scorers = @()
    foreach ($r in (Rows (Get-Html "$u&cmd=stats&type=group&subtype=shooters" -Ajax))) {
      if ($r.Count -lt 4) { continue }
      $t = @(Teams $r[2])
      if ($t.Count -gt 0) { $tn = $t[0].name; $ts = $t[0].slug } else { $tn = Clean $r[2]; $ts = "" }
      $scorers += [ordered]@{ name = (Clean $r[1]); team = $tn; slug = $ts; goals = [int](Clean $r[$r.Count - 1]) }
    }
    $groups += [ordered]@{ id = (GroupId $gs); slug = $gs; name = $title
      source = "$base/souteze/$season/$gs/"; table = $table; results = $results; fixtures = $fixtures; scorers = $scorers }
  }
  $data = [ordered]@{ key = $lg.key; name = $lg.name; season = $season; updated = (Get-Date -Format "yyyy-MM-dd HH:mm"); groups = $groups }
  $json = $data | ConvertTo-Json -Depth 8 -Compress
  [IO.File]::WriteAllText((Join-Path $OutDir $file), $json, (New-Object Text.UTF8Encoding $false))
  Write-Host "  saved $file ($($json.Length) chars, $($groups.Count) groups)"
  $index += [ordered]@{ key = $lg.key; name = $lg.name; season = $season; file = "data/$file"; source = "$base/souteze/$season/" }
}
# ---- PIBFAL (pibfal.com, WordPress + SportsPress REST API): one 11-a-side championship ----
function Get-Pib([string]$path) {
  Start-Sleep -Milliseconds 200
  return Invoke-RestMethod -Headers @{ "User-Agent" = "Mozilla/5.0 (fan-site importer)" } "https://pibfal.com/wp-json/sportspress/v2/$path"
}
if (-not $Only.Count -or $Only -contains "pib") {
  Write-Host "== PIBFAL"
  $all = Get-Pib "tables?per_page=20&orderby=date&order=desc"; $tbl = $all | ForEach-Object { $_ } | Where-Object { $_.slug -like "championship-*" -and @($_.leagues) -contains 8 } | Select-Object -First 1
  $tbl = Get-Pib "tables/$($tbl.id)"
  $seasonId = @($tbl.seasons)[0]
  $teamNames = @{}; $teamSlugs = @{}
  function PibTeam($id) {
    $id = "$id"
    if (-not $teamSlugs.ContainsKey($id)) { $tm = Get-Pib "teams/$id"; $teamSlugs[$id] = $tm.slug; $teamNames[$id] = [System.Net.WebUtility]::HtmlDecode($tm.title.rendered) }
    return @{ slug = $teamSlugs[$id]; name = $teamNames[$id] }
  }
  $table = @()
  foreach ($p in $tbl.data.PSObject.Properties) {
    if ($p.Name -eq "0") { continue }
    $v = $p.Value; $tm = PibTeam $p.Name
    $table += [ordered]@{ pos = [int]$v.pos; team = $tm.name; slug = $tm.slug; p = [int]$v.p; w = [int]$v.w; d = [int]$v.d; l = [int]$v.l; gf = [int]$v.f; ga = [int]$v.a; pts = [int]$v.pts }
  }
  $table = @($table | Sort-Object { $_.pos })
  $venues = @{}
  $results = @(); $fixtures = @()
  $evs = Get-Pib "events?seasons=$seasonId&leagues=8&per_page=100"; foreach ($e in ($evs | ForEach-Object { $_ })) {
    $ids = @($e.teams); if ($ids.Count -lt 2) { continue }
    $hT = PibTeam $ids[0]; $aT = PibTeam $ids[1]
    $vid = "$(@($e.venues)[0])"
    if ($vid -and -not $venues.ContainsKey($vid)) { try { $venues[$vid] = (Get-Pib "venues/$vid").name } catch { $venues[$vid] = "" } }
    $dt = [datetime]::Parse($e.date)
    $g = [ordered]@{ date = $dt.ToString("d.M.yy"); time = $dt.ToString("H:mm"); pitch = $(if ($vid) { [System.Net.WebUtility]::HtmlDecode($venues[$vid]) } else { "" })
      home = $hT.name; homeSlug = $hT.slug; away = $aT.name; awaySlug = $aT.slug; round = "" }
    $hg = "$($e.results."$($ids[0])".goals)"; $ag = "$($e.results."$($ids[1])".goals)"
    if ($hg -ne "" -and $ag -ne "") { $g.score = "$($hg):$($ag)"; $results += $g } elseif ($dt -gt (Get-Date).AddHours(-3)) { $fixtures += $g }
  }
  $scorers = @()
  $allL = Get-Pib "lists?per_page=20&orderby=date&order=desc"; $lst = $allL | ForEach-Object { $_ } | Where-Object { $_.slug -like "top-scorers-*" -and @($_.seasons) -contains $seasonId } | Select-Object -First 1
  if ($lst) {
    $lst = Get-Pib "lists/$($lst.id)"
    foreach ($p in $lst.data.PSObject.Properties) {
      if ($p.Name -eq "0" -or -not $p.Value.goals) { continue }
      $tm = if ($p.Value.team) { PibTeam $p.Value.team } else { @{ name = ""; slug = "" } }
      $scorers += [ordered]@{ name = [System.Net.WebUtility]::HtmlDecode($p.Value.name); team = $tm.name; slug = $tm.slug; goals = [int]$p.Value.goals }
    }
    $scorers = @($scorers | Sort-Object { -$_.goals } | Select-Object -First 20)
  }
  $grp = [ordered]@{ id = "CH"; slug = "championship"; name = "PIBFAL Championship " + [System.Net.WebUtility]::HtmlDecode(($tbl.title.rendered -replace '^.*?(\d{4}.*)$', '$1'))
    source = "https://pibfal.com/table/$($tbl.slug)/"; table = $table; results = $results; fixtures = @($fixtures | Sort-Object { [datetime]::ParseExact($_.date + " " + $_.time, "d.M.yy H:mm", $null) }); scorers = $scorers }
  $data = [ordered]@{ key = "pib"; name = "PIBFAL"; season = "pibfal"; updated = (Get-Date -Format "yyyy-MM-dd HH:mm"); groups = @($grp) }
  $json = $data | ConvertTo-Json -Depth 8 -Compress
  [IO.File]::WriteAllText((Join-Path $OutDir "pib.json"), $json, (New-Object Text.UTF8Encoding $false))
  Write-Host "  saved pib.json ($($results.Count) results, $($fixtures.Count) fixtures)"
}
if (Test-Path (Join-Path $OutDir "pib.json")) { $index += [ordered]@{ key = "pib"; name = "PIBFAL"; season = "pibfal"; file = "data/pib.json"; source = "https://pibfal.com/" } }

# ---- PKFL (pkfl.cz, Pražská Klubová Fotbalová liga): current season, every league group ----
function Get-Pk([string]$path) {
  Start-Sleep -Milliseconds 200
  return (Invoke-WebRequest -UseBasicParsing -Headers @{ "User-Agent" = "Mozilla/5.0 (fan-site importer)" } "https://pkfl.cz$path").Content
}
# a team cell: <a href="/tym/sNNN"><span>short</span><span>full name</span></a>  → full name (second span)
function PkTeams([string]$cell) {
  return @([regex]::Matches($cell, '(?s)<a href="/tym/(s\d+)">\s*<span[^>]*>(.*?)</span>\s*<span[^>]*>(.*?)</span>') | ForEach-Object {
    @{ slug = $_.Groups[1].Value; name = (Clean $_.Groups[3].Value); short = (Clean $_.Groups[2].Value) } })
}
if (-not $Only.Count -or $Only -contains "pkfl") {
  Write-Host "== PKFL"
  $pkHome = Get-Pk "/liga"
  $sm = [regex]::Match($pkHome, 'href="/liga/(s\d+)/s2vse/s31"[^>]*>\s*(\d{4})/(\d{4})')
  $seasonId = $sm.Groups[1].Value; $y1 = [int]$sm.Groups[2].Value
  $leagueLinks = [regex]::Matches($pkHome, "href=""/liga/$seasonId/s2vse/(s\d+)""[^>]*>\s*([^<]*?liga)\s*<") | ForEach-Object { @{ id = $_.Groups[1].Value; label = (Clean $_.Groups[2].Value) } }
  $seen = @{}; $groups = @()
  foreach ($lgl in $leagueLinks) {
    if ($seen[$lgl.id]) { continue }; $seen[$lgl.id] = 1
    $label = $lgl.label                                     # "1. liga", "3.A liga" …
    $mm = [regex]::Match($label, '^(\d+)\.?\s*([A-Z])?')
    $slug = $mm.Groups[1].Value + $(if ($mm.Groups[2].Value) { "-" + $mm.Groups[2].Value.ToLower() } else { "" })
    $gid = $mm.Groups[1].Value + $mm.Groups[2].Value
    Write-Host "  $label ($slug)"
    $base2 = "/liga/$seasonId/s2vse/$($lgl.id)"
    # standings
    $table = @(); $names = @{}
    foreach ($r in (Rows ([regex]::Match((Get-Pk $base2), '(?s)<table.*?</table>').Value))) {
      if ($r.Count -lt 7) { continue }
      $tm = @(PkTeams $r[1]); if (-not $tm.Count) { continue }
      $wdl = (Clean $r[3]) -split '/'; $sc = (Clean $r[4]) -split ':'
      $names[$tm[0].slug] = $tm[0].name
      $table += [ordered]@{ pos = [int](Clean $r[0]); team = $tm[0].name; slug = $tm[0].slug; p = [int](Clean $r[2])
        w = [int]$wdl[0]; d = [int]$wdl[1]; l = [int]$wdl[2]; gf = [int]$sc[0]; ga = [int]$sc[1]; pts = [int](Clean $r[6]) }
    }
    # results + fixtures (all rounds of the season on one page)
    $results = @(); $fixtures = @()
    $rp = Get-Pk "$base2`?t=rozpis"
    foreach ($tb in [regex]::Matches($rp, '(?s)<table.*?</table>')) {
      foreach ($r in (Rows $tb.Value)) {
        if ($r.Count -lt 6) { continue }
        $dm = [regex]::Match((Clean $r[0]), '(\d+)\.\s*(\d+)\.\s*/\s*(\d+):(\d+)'); if (-not $dm.Success) { continue }
        $hT = @(PkTeams $r[1]); $aT = @(PkTeams $r[2]); if (-not $hT.Count -or -not $aT.Count) { continue }
        $mon = [int]$dm.Groups[2].Value; $yr = if ($mon -ge 7) { $y1 } else { $y1 + 1 }
        $g = [ordered]@{ date = "$([int]$dm.Groups[1].Value).$mon.$($yr % 100)"; time = "$([int]$dm.Groups[3].Value):$($dm.Groups[4].Value)"; pitch = (Clean $r[3])
          home = $hT[0].name; homeSlug = $hT[0].slug; away = $aT[0].name; awaySlug = $aT[0].slug; round = "" }
        $s = (Clean $r[5]) -replace '\s', ''
        if ($s -match '^\d+:\d+$') { $g.score = $s; $results += $g } else { $fixtures += $g }
      }
    }
    # scorers
    $scorers = @()
    $ip = Get-Pk "$base2`?t=individual"
    foreach ($r in (Rows ([regex]::Match($ip, '(?s)<table.*?</table>').Value))) {
      if ($r.Count -lt 8) { continue }
      if ((Clean $r[0]) -notmatch '^\d+$' -or (Clean $r[0]) -eq '9999') { continue }
      $pn = [regex]::Match($r[4], '(?s)<span[^>]*>(.*?)</span>').Groups[1].Value
      $tsl = [regex]::Match($r[6], '/tym/(s\d+)').Groups[1].Value
      $gl = [int](Clean $r[7]); if ($gl -le 0) { continue }
      $scorers += [ordered]@{ name = (Clean $pn); team = $(if ($names[$tsl]) { $names[$tsl] } else { Clean $r[6] }); slug = $tsl; goals = $gl }
    }
    $scorers = @($scorers | Sort-Object { -$_.goals } | Select-Object -First 20)
    $groups += [ordered]@{ id = $gid; slug = $slug; name = "PKFL $label"; source = "https://pkfl.cz$base2"; table = $table
      results = $results; fixtures = @($fixtures | Sort-Object { [datetime]::ParseExact($_.date + " " + $_.time, "d.M.yy H:mm", $null) }); scorers = $scorers }
  }
  $data = [ordered]@{ key = "pkfl"; name = "PKFL"; season = "pkfl-$seasonId"; updated = (Get-Date -Format "yyyy-MM-dd HH:mm"); groups = $groups }
  $json = $data | ConvertTo-Json -Depth 8 -Compress
  [IO.File]::WriteAllText((Join-Path $OutDir "pkfl.json"), $json, (New-Object Text.UTF8Encoding $false))
  Write-Host "  saved pkfl.json ($($groups.Count) groups)"
}
if (Test-Path (Join-Path $OutDir "pkfl.json")) { $index += [ordered]@{ key = "pkfl"; name = "PKFL"; season = "pkfl"; file = "data/pkfl.json"; source = "https://pkfl.cz/" } }

$idx = [ordered]@{ updated = (Get-Date -Format "yyyy-MM-dd HH:mm"); leagues = $index }
[IO.File]::WriteAllText((Join-Path $OutDir "index.json"), ($idx | ConvertTo-Json -Depth 4 -Compress), (New-Object Text.UTF8Encoding $false))
Write-Host "Done: $($index.Count) leagues"
