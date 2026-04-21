// Vercel serverless function that fetches inventory from Monday.com
// Master Inventory Viewer board (id 18390978121) and returns items
// keyed by ASIN (extracted from the ASIN link column).
//
// GET /api/monday-inventory?board=18390978121
// Response: { items: [ { name, mpl_id, asin, angoraWh, locations: { hq, dongguan, california, barkleys, yalong, fd, production }, overall }, ... ] }

const MONDAY_ENDPOINT = 'https://api.monday.com/v2';
const DEFAULT_BOARD_ID = '18390978121'; // Master Inventory Viewer

// Column ID map for the Master Inventory Viewer
const COLS = {
  mpl_id: 'text_mkya6fh9',
  asin: 'link_mkyevnrk',
  overall: 'formula_mkya9fhk',
  production: 'numeric_mkya9dz2',
  hq: 'numeric_mkyajs49',
  dongguan: 'numeric_mkyahbb',
  california: 'numeric_mkya6pec',
  barkleys: 'numeric_mkyayz09',
  ca_barkleys: 'numeric_mkyaer9h',
  yalong: 'numeric_mkya1wca',
  fd: 'numeric_mkyahw4',
};

function extractAsin(val) {
  if (!val) return null;
  // Monday link column 'text' is typically "<url> - <label>"; value is a JSON object
  const m = String(val).match(/\/dp\/([A-Z0-9]{8,12})/i);
  return m ? m[1].toUpperCase() : null;
}

function toNum(v) {
  const n = parseFloat(String(v || '').replace(/[^0-9.\-]/g, ''));
  return Number.isFinite(n) ? n : 0;
}

async function queryMonday(apiKey, query, variables) {
  const r = await fetch(MONDAY_ENDPOINT, {
    method: 'POST',
    headers: { Authorization: apiKey, 'Content-Type': 'application/json', 'API-Version': '2024-10' },
    body: JSON.stringify({ query, variables }),
  });
  if (!r.ok) throw new Error(`Monday HTTP ${r.status}`);
  const data = await r.json();
  if (data.errors) throw new Error('Monday GraphQL error: ' + JSON.stringify(data.errors));
  return data.data;
}

async function fetchAllItems(apiKey, boardId) {
  const items = [];
  let cursor = null;
  const first = await queryMonday(apiKey, `
    query($boardId: [ID!], $limit: Int!) {
      boards(ids: $boardId) {
        items_page(limit: $limit) {
          cursor
          items { id name column_values { id text value } }
        }
      }
    }
  `, { boardId: [boardId], limit: 100 });
  if (first.boards && first.boards[0] && first.boards[0].items_page) {
    items.push(...first.boards[0].items_page.items);
    cursor = first.boards[0].items_page.cursor;
  }
  while (cursor) {
    const next = await queryMonday(apiKey, `
      query($cursor: String!, $limit: Int!) {
        next_items_page(cursor: $cursor, limit: $limit) {
          cursor
          items { id name column_values { id text value } }
        }
      }
    `, { cursor, limit: 100 });
    if (next.next_items_page) {
      items.push(...next.next_items_page.items);
      cursor = next.next_items_page.cursor;
    } else { cursor = null; }
  }
  return items;
}

module.exports = async (req, res) => {
  // CORS — this is called from the Garden front-end which runs on the same origin,
  // so CORS is not strictly required, but we'll add permissive headers anyway.
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  if (req.method === 'OPTIONS') return res.status(204).end();

  const apiKey = process.env.MONDAY_API_KEY;
  if (!apiKey) {
    return res.status(500).json({ error: 'MONDAY_API_KEY env var not set on Vercel project' });
  }
  const boardId = (req.query && req.query.board) || DEFAULT_BOARD_ID;
  try {
    const rawItems = await fetchAllItems(apiKey, boardId);
    const items = rawItems.map((it) => {
      const cv = {};
      (it.column_values || []).forEach(c => { cv[c.id] = c.text; });
      const asin = extractAsin(cv[COLS.asin]);
      const loc = {
        hq: toNum(cv[COLS.hq]),
        dongguan: toNum(cv[COLS.dongguan]),
        california: toNum(cv[COLS.california]),
        barkleys: toNum(cv[COLS.barkleys]),
        yalong: toNum(cv[COLS.yalong]),
        fd: toNum(cv[COLS.fd]),
        production: toNum(cv[COLS.production]),
      };
      const angoraWh = loc.hq + loc.dongguan + loc.california + loc.barkleys + loc.yalong + loc.fd;
      return {
        id: it.id,
        name: it.name,
        mpl_id: cv[COLS.mpl_id] || null,
        asin,
        angoraWh,
        overall: toNum(cv[COLS.overall]) || angoraWh + loc.production,
        locations: loc,
      };
    });
    return res.status(200).json({
      board_id: boardId,
      count: items.length,
      items,
    });
  } catch (e) {
    console.error('monday-inventory error', e);
    return res.status(500).json({ error: e.message });
  }
};
