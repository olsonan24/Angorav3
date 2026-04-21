// Vercel serverless function that fetches inventory + COGS from Monday.com
// - Master Inventory Viewer (18390978121): warehouse inventory per product
// - Monthly Listing Reports (18393711748): Cost Per Unit + Shipping Per Unit per item
//
// GET /api/monday-inventory[?board=18390978121]
// Response: {
//   board_id, count,
//   items: [{
//     name, mpl_id, asin, angoraWh, locations: {...}, overall,
//     cost_per_unit, shipping_per_unit, cogs_per_unit, listing_date
//   }]
// }

const MONDAY_ENDPOINT = 'https://api.monday.com/v2';
const INVENTORY_BOARD_ID = '18390978121';   // Master Inventory Viewer
const LISTING_BOARD_ID = '18393711748';     // Monthly Listing Reports

// Column ids - Master Inventory Viewer
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

// Column ids - Monthly Listing Reports
const LISTING_COLS = {
  item_id: 'text_mkwxqsm6',        // Item ID (links to source board item)
  store: 'text_mkz7991e',          // Store Name
  cost_per_unit: 'numeric_mkz72281',
  shipping_per_unit: 'numeric_mkz7tskp',
  amz_link: 'link_mkz7ebvh',       // Amazon Listing Link (has ASIN)
  launch_date: 'date_mkz7kt4h',
  updated: 'pulse_updated_mkz7wcwx',
};

function extractAsin(val) {
  if (!val) return null;
  const m = String(val).match(/\/dp\/([A-Z0-9]{8,12})/i);
  return m ? m[1].toUpperCase() : null;
}

function toNum(v) {
  if (v === null || v === undefined || v === '') return null;
  const n = parseFloat(String(v).replace(/[^0-9.\-]/g, ''));
  return Number.isFinite(n) ? n : null;
}

function normalizeName(s) {
  return String(s || '').trim().toLowerCase().replace(/\s+/g, ' ').replace(/[^\w\s]/g, '');
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
  let cursor = null;
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

// Build a map: normalizedName -> { cost_per_unit, shipping_per_unit, asin, updated_at }
// Also keyed by ASIN for secondary lookup. When multiple rows match, keep most recent.
function buildListingLookup(listingItems) {
  const byName = new Map();
  const byAsin = new Map();
  for (const it of listingItems) {
    const cv = {};
    (it.column_values || []).forEach(c => { cv[c.id] = c.text; });
    const cost = toNum(cv[LISTING_COLS.cost_per_unit]);
    const ship = toNum(cv[LISTING_COLS.shipping_per_unit]);
    if (cost === null && ship === null) continue; // skip rows with no cost data
    const asin = extractAsin(cv[LISTING_COLS.amz_link]);
    const updated = cv[LISTING_COLS.updated] || cv[LISTING_COLS.launch_date] || '';
    const entry = {
      name: it.name,
      cost_per_unit: cost,
      shipping_per_unit: ship,
      asin,
      updated_at: updated,
    };
    const nameKey = normalizeName(it.name);
    // Prefer the most recently updated row if duplicates
    const existing = byName.get(nameKey);
    if (!existing || (updated && updated > (existing.updated_at || ''))) {
      byName.set(nameKey, entry);
    }
    if (asin) {
      const existingA = byAsin.get(asin);
      if (!existingA || (updated && updated > (existingA.updated_at || ''))) {
        byAsin.set(asin, entry);
      }
    }
  }
  return { byName, byAsin };
}

module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  if (req.method === 'OPTIONS') return res.status(204).end();

  const apiKey = process.env.MONDAY_API_KEY;
  if (!apiKey) {
    return res.status(500).json({ error: 'MONDAY_API_KEY env var not set on Vercel project' });
  }
  const boardId = (req.query && req.query.board) || INVENTORY_BOARD_ID;
  try {
    // Fetch both boards in parallel
    const [rawItems, listingItems] = await Promise.all([
      fetchAllItems(apiKey, boardId),
      fetchAllItems(apiKey, LISTING_BOARD_ID).catch(e => {
        console.warn('Monthly Listing Reports fetch failed:', e.message);
        return [];
      }),
    ]);
    const lookup = buildListingLookup(listingItems);

    const items = rawItems.map((it) => {
      const cv = {};
      (it.column_values || []).forEach(c => { cv[c.id] = c.text; });
      const asin = extractAsin(cv[COLS.asin]);
      const loc = {
        hq: toNum(cv[COLS.hq]) || 0,
        dongguan: toNum(cv[COLS.dongguan]) || 0,
        california: toNum(cv[COLS.california]) || 0,
        barkleys: toNum(cv[COLS.barkleys]) || 0,
        yalong: toNum(cv[COLS.yalong]) || 0,
        fd: toNum(cv[COLS.fd]) || 0,
        production: toNum(cv[COLS.production]) || 0,
      };
      const angoraWh = loc.hq + loc.dongguan + loc.california + loc.barkleys + loc.yalong + loc.fd;

      // Match to listing report for COGS
      let costData = null;
      if (asin && lookup.byAsin.has(asin)) {
        costData = lookup.byAsin.get(asin);
      } else {
        const nameKey = normalizeName(it.name);
        if (lookup.byName.has(nameKey)) costData = lookup.byName.get(nameKey);
      }
      // COGS = cost + shipping. If shipping is blank/null, it's already baked into cost (per Alex)
      const cost_per_unit = costData ? costData.cost_per_unit : null;
      const shipping_per_unit = costData ? costData.shipping_per_unit : null;
      const cogs_per_unit = cost_per_unit !== null
        ? cost_per_unit + (shipping_per_unit || 0)
        : null;

      return {
        id: it.id,
        name: it.name,
        mpl_id: cv[COLS.mpl_id] || null,
        asin,
        angoraWh,
        overall: toNum(cv[COLS.overall]) || angoraWh + loc.production,
        locations: loc,
        // COGS fields from Monthly Listing Reports
        cost_per_unit,
        shipping_per_unit,
        cogs_per_unit,
        cogs_source: costData ? 'monday_monthly_listing_reports' : null,
      };
    });

    const withCogs = items.filter(i => i.cogs_per_unit !== null).length;
    return res.status(200).json({
      board_id: boardId,
      count: items.length,
      with_cogs: withCogs,
      listing_rows: listingItems.length,
      items,
    });
  } catch (e) {
    console.error('monday-inventory error', e);
    return res.status(500).json({ error: e.message });
  }
};
