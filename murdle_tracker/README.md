# Murdle Tracker

A small Flask + SQLite app to log your daily Murdle (main and mini), see your stats, and keep a screenshot of each solved grid.

## Run it

```
pip install -r requirements.txt
python app.py
```

Open http://localhost:5000. Flask runs in debug mode, so when you edit `app.py` and save, it reloads itself. Just refresh the browser.

## Using it

- **Log a solve:** pick the date and Main/Mini, set the time with the min/sec arrows (seconds roll over into minutes), then fill in who, how (weapon), where, and optionally why (not every main murdle has a motive).
- **Grid screenshot:** screenshot your solved grid, then press Ctrl+V (Cmd+V on Mac) anywhere on the page. The dashed box shows a thumbnail and a check mark when it is attached.
- **Edit / Delete:** every row in the table has both links. When editing, pasting a new screenshot replaces the old one; if you paste nothing, the old one stays.
- **Stats:** day streak, plus count, average and best time for main and mini. The chart shows minutes per day, one line per type.

## Where your data lives

| What | Where |
| --- | --- |
| Entries | `murdle.db` (SQLite) next to `app.py` |
| Screenshots | `uploads/` folder next to `app.py` |

To back up, copy those two. To start fresh, delete them.

## Resizing and restyling

All styling is in the `<style>` block inside the `PAGE` string in `app.py`. Quick way to experiment: in the browser, right-click the element, choose Inspect, and change values live in the Styles panel. When it looks right, copy the value into `app.py`.

| To change | Edit this |
| --- | --- |
| Overall text size (everything scales) | `body { font-size: 15px }` |
| Line spacing | `body { line-height: 1.5 }` |
| Page width | `body { max-width: 80% }` |
| Minimum chart height | `.chartwrap { min-height: 300px }` (the chart otherwise stretches to match the form) |
| Chart/form width split | `.top { grid-template-columns: 1.1fr 1fr }` |
| Width below which they stack | `@media(max-width:900px)` |
| Card spacing | `.card { padding: 12px 14px; margin-bottom: 12px }` |
| Input height | `input, select { padding: 6px 10px }` |
| Button size | `button { padding: 8px 16px }` |
| Paste box height | `.paste { padding: 8px }` |
| Pasted thumbnail size | `#pv { max-height: 50px }` |
| Title size | `h1 { font-size: 1.4rem }` |
| Stat number size | `.stat b { font-size: 1.15rem }` |
| Stat tile width | `.stats ... minmax(95px,1fr)` |

Colors are near the top of the same block: `--bg`, `--card`, `--tx` (text), `--mu` (muted grey), `--ac` (red), `--ac2` (blue). The font is set on `body` (`font-family`).

Tip: to check how it fits your screen, press F12 and use Ctrl + / Ctrl - to zoom the page, or set the chart height smaller first. The chart is the easiest thing to shrink.

## Putting it online

This is a Python server app, so it needs a host that runs Python, not just static hosting.

- **PythonAnywhere / Render / Fly.io:** run `app.py` as a Flask app. Keep `murdle.db` and `uploads/` on persistent storage or you lose data on redeploy.
- There is no login. Add a password before making it public, or anyone with the link can add and delete entries.
- Before deploying, turn off debug mode by changing `app.run(debug=True)` to `app.run()` and serve with gunicorn.
