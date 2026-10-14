"""Murdle Tracker - run: pip install flask && python app.py  ->  http://localhost:5000"""
import os, sqlite3, uuid, json
from datetime import date, timedelta
from flask import Flask, request, redirect, render_template_string, send_from_directory

BASE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(BASE, "murdle.db")
UP = os.path.join(BASE, "uploads")
os.makedirs(UP, exist_ok=True)
app = Flask(__name__)


def db():
    c = sqlite3.connect(DB)
    c.row_factory = sqlite3.Row
    c.execute("""CREATE TABLE IF NOT EXISTS solves(
        id INTEGER PRIMARY KEY, day TEXT, kind TEXT, who TEXT, how TEXT,
        place TEXT, why TEXT, secs INTEGER, notes TEXT, img TEXT)""")
    try:
        c.execute("ALTER TABLE solves ADD COLUMN dns INTEGER DEFAULT 0")
    except sqlite3.OperationalError:
        pass  # column already exists
    return c


def get_secs(f):
    return int(f.get("min") or 0) * 60 + int(f.get("sec") or 0)


def fmt(s):
    if s is None:
        return "-"
    h, r = divmod(int(s), 3600)
    m, sec = divmod(r, 60)
    return f"{h}:{m:02d}:{sec:02d}" if h else f"{m}:{sec:02d}"


def streak(days):
    days = set(days)
    d = date.today()
    if d.isoformat() not in days:
        d -= timedelta(days=1)
    n = 0
    while d.isoformat() in days:
        n += 1
        d -= timedelta(days=1)
    return n


def save_img(file, old=None):
    if file and file.filename:
        new = uuid.uuid4().hex + (os.path.splitext(file.filename)[1].lower() or ".png")
        file.save(os.path.join(UP, new))
        if old and os.path.exists(os.path.join(UP, old)):
            os.remove(os.path.join(UP, old))
        return new
    return old


@app.route("/")
def index():
    c = db()
    rows = c.execute("SELECT * FROM solves ORDER BY day DESC, id DESC").fetchall()
    e = None
    if request.args.get("edit"):
        r = c.execute("SELECT * FROM solves WHERE id=?", (request.args["edit"],)).fetchone()
        if r:
            e = dict(r)
            e["min"], e["sec"] = divmod(e["secs"], 60)
    solved = [r for r in rows if not r["dns"]]
    dns = len(rows) - len(solved)
    stats = {}
    for k in ("main", "mini"):
        t = [r["secs"] for r in solved if r["kind"] == k]
        stats[k] = dict(n=len(t), avg=fmt(sum(t) / len(t)) if t else "-",
                        best=fmt(min(t)) if t else "-")
    asc = sorted(rows, key=lambda r: (r["day"], r["id"]))
    chart = {k: [{"x": r["day"], "y": round(r["secs"] / 60, 2)} for r in asc if r["kind"] == k and not r["dns"]]
             for k in ("main", "mini")}
    return render_template_string(PAGE, rows=rows, stats=stats, fmt=fmt,
                                  streak=streak([r["day"] for r in rows]), dns=dns,
                                  chart=json.dumps(chart), today=date.today().isoformat(),
                                  e=e, v=e or {})


@app.route("/add", methods=["POST"])
def add():
    f = request.form
    img = save_img(request.files.get("img"))
    c = db()
    c.execute("INSERT INTO solves(day,kind,who,how,place,why,secs,notes,img,dns) VALUES(?,?,?,?,?,?,?,?,?,?)",
              (f["day"], f["kind"], f.get("who", ""), f.get("how", ""), f.get("place", ""), f.get("why", ""),
               get_secs(f), f.get("notes", ""), img, 1 if f.get("dns") else 0))
    c.commit()
    return redirect("/")


@app.route("/update/<int:i>", methods=["POST"])
def update(i):
    f = request.form
    c = db()
    old = c.execute("SELECT img FROM solves WHERE id=?", (i,)).fetchone()
    img = save_img(request.files.get("img"), old["img"] if old else None)
    c.execute("UPDATE solves SET day=?,kind=?,who=?,how=?,place=?,why=?,secs=?,notes=?,img=?,dns=? WHERE id=?",
              (f["day"], f["kind"], f.get("who", ""), f.get("how", ""), f.get("place", ""), f.get("why", ""),
               get_secs(f), f.get("notes", ""), img, 1 if f.get("dns") else 0, i))
    c.commit()
    return redirect("/")


@app.route("/delete/<int:i>", methods=["POST"])
def delete(i):
    c = db()
    c.execute("DELETE FROM solves WHERE id=?", (i,))
    c.commit()
    return redirect("/")


@app.route("/uploads/<path:f>")
def uploads(f):
    return send_from_directory(UP, f)


PAGE = """<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Murdle Tracker</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1"></script>
<style>
:root{--bg:#fbfbf9;--card:#fff;--tx:#222;--mu:#737373;--ac:#e0476b;--ac2:#1dacd6}
*{box-sizing:border-box}body{margin-left:auto;margin-right:auto;font-family:Courier,"Courier New",monospace;font-size:25px;line-height:1.5;background:#fbfbf9;color:var(--tx);padding:12px 0;max-width:80%;position:relative;overflow:visible}
h1{margin:0 0 10px;font-size:1.4rem}.card{background:var(--card);border:1px solid #ebebe5;border-radius:15px;padding:12px 14px;margin-bottom:12px;position:relative}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(120px,1fr));gap:8px}
.stat b{display:block;font-size:1.15rem;line-height:1.2}.stat span{color:var(--mu);font-size:.8rem}
form.f{display:grid;grid-template-columns:repeat(2,1fr);gap:8px}
input,select{background:#fff;color:var(--tx);border:1px solid #d9d9d3;border-radius:15px;padding:6px 10px;font:inherit;width:100%}
button{background:var(--ac);color:#fff;border:0;border-radius:15px;padding:8px 16px;font:inherit;cursor:pointer}
.full{grid-column:1/-1}#pv{max-height:50px;border-radius:8px;display:none;margin:6px auto 0}
.time{display:flex;align-items:center;gap:6px}.time input{text-align:center}.time span{color:var(--mu);font-size:.85rem}
.paste{border:2px dashed #cfcfc8;border-radius:15px;padding:8px;text-align:center;color:var(--mu);cursor:pointer;outline:none}
.paste:focus,.paste.ok{border-color:var(--ac2)}
table{width:100%;border-collapse:collapse;font-size:.9rem}td,th{padding:8px;text-align:left;border-bottom:1px solid #ebebe5}
th{color:var(--mu);font-weight:500}.tag{padding:.2em .5em;border-radius:15px;font-size:.75rem;line-height:1;display:inline-block}
.main{background:var(--ac)}.mini{background:var(--ac2);color:#000}
.tbl{overflow-x:auto}.top .card{margin-bottom:0}.top{margin-bottom:12px;display:grid;grid-template-columns:1.1fr 1fr;gap:12px;align-items:stretch}.chartcard{display:flex;flex-direction:column;margin-bottom:0}.chartwrap{flex:1;position:relative;min-height:300px}.chartwrap canvas{position:absolute;inset:0}@media(max-width:900px){.top{grid-template-columns:1fr}}a{color:var(--ac2);cursor:pointer}
.x{background:none;color:var(--ac);padding:0}.dns{background:var(--mu);color:#fff}
.dnsbtn{display:inline-flex;align-items:center;border:1px solid #d9d9d3;border-radius:15px;padding:.2em .7em;font-size:.75rem;cursor:pointer;color:var(--mu);user-select:none}.dnsbtn.on{background:var(--mu);color:#fff;border-color:var(--mu)}.dnsbtn input{display:none}
dialog{background:var(--card);color:var(--tx);border:0;border-radius:15px;max-width:92vw}dialog img{max-width:100%}
</style></head><body>
<h1>🔍 Murdle Tracker</h1>
<div class="card stats">
 <div class="stat"><b>🔥 {{streak}}</b><span>day streak</span></div>
 <div class="stat"><b>{{dns}}</b><span>DNS</span></div>
 {% for k in ['main','mini'] %}
 <div class="stat"><b>{{stats[k].n}}</b><span>{{k}} solved</span></div>
 <div class="stat"><b>{{stats[k].avg}}</b><span>{{k}} avg</span></div>
 <div class="stat"><b>{{stats[k].best}}</b><span>{{k}} best</span></div>
 {% endfor %}
</div>
<div class="top"><div class="card chartcard"><div class="chartwrap"><canvas id="ch"></canvas></div></div>
<div class="card" id="formcard"><div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px"><h3 style="margin:0;font-size:1rem">{{'Edit solve' if e else 'Log a solve'}}</h3>
 <label class="dnsbtn" id="dnslbl"><input type="checkbox" name="dns" id="dns" value="1" form="mainform" {{'checked' if v.dns}}>Did not solve (DNS)</label></div>
<form class="f" id="mainform" method="post" action="{{'/update/%d'%e.id if e else '/add'}}" enctype="multipart/form-data">
 <input type="date" name="day" value="{{v.day or today}}" required>
 <select name="kind"><option value="main">Main Murdle</option><option value="mini" {{'selected' if v.kind=='mini'}}>Mini Murdle</option></select>
 <div class="time"><input type="number" name="min" id="min" min="0" max="999" value="{{v.min or 0}}" required><span>min</span>
  <input type="number" name="sec" id="sec" min="-1" max="60" value="{{v.sec or 0}}" required><span>sec</span></div>
 <input name="who" placeholder="Who" value="{{v.who}}" required>
 <input name="how" placeholder="How (weapon)" value="{{v.how}}" required>
 <input name="place" placeholder="Where" value="{{v.place}}" required>
 <input name="why" placeholder="Why (motive, if any)" value="{{v.why}}">
 <input name="notes" class="full" placeholder="Notes (optional)" value="{{v.notes}}">
 <div class="full paste" id="pz" tabindex="0"><span id="pt">📋 {{'Paste a new screenshot to replace the old one' if e and e.img else 'Press Ctrl+V to paste your grid screenshot'}}</span><img id="pv"></div>
 <input type="file" name="img" id="imgin" accept="image/*" style="display:none">
 <button class="full">{{'Save changes' if e else 'Log solve'}}</button>
 {% if e %}<a href="/" class="full" style="text-align:center">Cancel</a>{% endif %}</form></div></div>
<div class="card tbl"><table><tr><th>Date</th><th></th><th>Who</th><th>How</th><th>Where</th><th>Why</th><th>Time</th><th>Grid</th><th></th></tr>
{% for r in rows %}<tr><td>{{r.day}}</td><td><span class="tag {{r.kind}}">{{r.kind}}</span></td>
<td>{{r.who or "-"}}</td><td>{{r.how or "-"}}</td><td>{{r.place or "-"}}</td><td>{{r.why or "-"}}</td><td>{% if r.dns %}<span class="tag dns">DNS</span>{% else %}{{fmt(r.secs)}}{% endif %}</td>
<td>{% if r.img %}<a onclick="show('/uploads/{{r.img}}')">view</a>{% endif %}</td>
<td style="white-space:nowrap"><a href="/?edit={{r.id}}">Edit</a> ·
<form method="post" action="/delete/{{r.id}}" onsubmit="return confirm('Delete this entry?')" style="display:inline"><button class="x">Delete</button></form></td></tr>{% endfor %}
</table></div>
<dialog id="dlg" onclick="this.close()"><img id="big"></dialog>
<script>
// paste handler first, so it works even if the chart library fails to load
document.addEventListener('paste', ev => {
  for (const it of (ev.clipboardData || {}).items || []) {
    if (it.type.startsWith('image/')) {
      const file = it.getAsFile(), dt = new DataTransfer();
      dt.items.add(new File([file], 'grid.png', {type: file.type}));
      document.getElementById('imgin').files = dt.files;
      const pv = document.getElementById('pv');
      pv.src = URL.createObjectURL(file); pv.style.display = 'block';
      document.getElementById('pt').textContent = '✅ Screenshot attached (paste again to replace)';
      document.getElementById('pz').classList.add('ok');
      ev.preventDefault(); break;
    }
  }
});
// seconds roll over into minutes when you click the arrows
const minI = document.getElementById('min'), secI = document.getElementById('sec');
secI.addEventListener('input', () => {
  let s = parseInt(secI.value || 0), m = parseInt(minI.value || 0);
  if (s >= 60) { m++; s = 0; } else if (s < 0) { if (m > 0) { m--; s = 59; } else s = 0; }
  secI.value = s; minI.value = m;
});
const dnsI = document.getElementById('dns'), dnsL = document.getElementById('dnslbl');
function syncDns() {
  dnsL.classList.toggle('on', dnsI.checked);
  ['who', 'how', 'place'].forEach(n => document.querySelector('[name=' + n + ']').required = !dnsI.checked);
}
dnsI.addEventListener('change', syncDns); syncDns();
function show(u) { document.getElementById('big').src = u; document.getElementById('dlg').showModal(); }
{% if e %}document.getElementById('formcard').scrollIntoView();{% endif %}
try {
  const d = {{chart|safe}};
  const labels = [...new Set([...d.main, ...d.mini].map(p => p.x))].sort();
  const ser = a => labels.map(l => { const p = a.find(q => q.x === l); return p ? p.y : null; });
  new Chart(document.getElementById('ch'), {type: 'line', data: {labels, datasets: [
    {label: 'Main', data: ser(d.main), borderColor: '#e0476b', backgroundColor: '#e0476b', tension: .25, spanGaps: true},
    {label: 'Mini', data: ser(d.mini), borderColor: '#1dacd6', backgroundColor: '#1dacd6', tension: .25, spanGaps: true}]},
    options: {maintainAspectRatio: false, scales: {x: {ticks: {color: '#737373'}}, y: {beginAtZero: true, title: {display: true, text: 'minutes', color: '#737373'}, ticks: {color: '#737373'}}},
    plugins: {legend: {labels: {color: '#222'}}}}});
} catch (err) { console.warn('Chart failed', err); }
</script></body></html>"""

if __name__ == "__main__":
    app.run(debug=True)