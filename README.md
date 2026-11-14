# Tribuna — Prague amateur football

An unofficial fan site for Prague's amateur football leagues. It shows tables, results, fixtures and top scorers for every group, and lets team coaches add goal videos and player details.

The site is a single page (`tribuna.html`) published as a Claude artifact. League data comes from the leagues' own websites. Videos, players, votes and passwords are kept in the artifact's database.

## Leagues

| Key | League | Source |
|---|---|---|
| `hl` | Hanspaulská liga (8 divisions, 60 groups) | psmf.cz |
| `vet` | Veteránská liga | psmf.cz |
| `svet` | Superveteránská liga | psmf.cz |
| `uvet` | Ultraveteránská liga | psmf.cz |
| `fut` | Futsal | psmf.cz |
| `pib` | PIBFAL (11-a-side) | pibfal.com |
| `pkfl` | PKFL (Pražská Klubová Fotbalová liga) | pkfl.cz |

## Files

- `tribuna.html` — the whole site: HTML, CSS and JavaScript in one file.
- `scrape-psmf.ps1` — the importer. It downloads every league and writes `data/<league>.json` plus `data/index.json`.
- `data/` — the imported league data that the page loads.

## Updating the league data

Run this in Windows PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File scrape-psmf.ps1            # all leagues (~15 min)
powershell -ExecutionPolicy Bypass -File scrape-psmf.ps1 -Only pkfl  # one league
```

After that, publish the page again together with the `data/` files.

## Features

- **Home page:** all leagues, Goal of the Week (one goal per team per week, voting per league), league leaders, top scorers as player cards, upcoming matches and latest results.
- **League, group and team pages:** tables, results, fixtures, scorers and the team's squad.
- **Goals & highlights:** every goal video. Videos always play muted.
- **Statistics:** points per game, attack, defence, form, biggest wins, and the leagues in numbers.
- **Coaches' login:** the first login uses `12345`, then the coach picks the team and sets their own password. Coaches can edit players (photo, number, position, age, height, weight, ratings) and upload goals (video, scorer, opponent, final score).
- **Admin (owner only):** approves submissions and manages team passwords.
- **Languages:** Czech and English.
