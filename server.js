const express = require('express');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = 3000;
const DATA_DIR = path.join(__dirname, 'data');

app.use(express.json({ limit: '10mb' }));
app.use(express.text({ limit: '10mb' }));
app.use(express.static(path.join(__dirname, 'public')));

/* ── GET /api/config ── */
app.get('/api/config', (req, res) => {
  const file = path.join(DATA_DIR, 'config.json');
  if (!fs.existsSync(file)) return res.status(404).json({ error: 'config.json introuvable' });
  res.sendFile(file);
});

/* ── POST /api/config ── */
app.post('/api/config', (req, res) => {
  try {
    const data = typeof req.body === 'string' ? req.body : JSON.stringify(req.body, null, 2);
    JSON.parse(data); // validation
    fs.writeFileSync(path.join(DATA_DIR, 'config.json'), data, 'utf8');
    res.json({ ok: true });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

/* ── GET /api/projets ── */
app.get('/api/projets', (req, res) => {
  const file = path.join(DATA_DIR, 'projets.csv');
  if (!fs.existsSync(file)) return res.status(404).json({ error: 'projets.csv introuvable' });
  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.sendFile(file);
});

/* ── POST /api/projets ── */
app.post('/api/projets', (req, res) => {
  try {
    const data = typeof req.body === 'string' ? req.body : String(req.body);
    fs.writeFileSync(path.join(DATA_DIR, 'projets.csv'), data, 'utf8');
    res.json({ ok: true });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

app.listen(PORT, () => {
  console.log(`Roadmap server running on http://localhost:${PORT}`);
});
