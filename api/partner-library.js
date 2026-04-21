// Vercel serverless function that fetches the Partner Library 2.0 board from Monday
// and returns a normalized list of partners ready to sync into angora_accounts.
//
// GET /api/partner-library
// Response: { count, partners: [{ monday_id, name, brand_name, account_name,
//   client_email, client_cc_email, phone, garden_account_link, csm, osm, psm,
//   client_since, garden_status, inventory_status }] }

const MONDAY_ENDPOINT = 'https://api.monday.com/v2';
const PARTNER_BOARD_ID = '18408186263';

const COLS = {
  status: 'status',                         // Garden Account status
  inv_status: 'color_mm292w2m',             // Inventory Tracking
  csm: 'multiple_person_mktbwk4h',
  osm: 'people',
  psm: 'multiple_person_mm298f5h',
  client_name: 'text_mkttpex8',
  client_email: 'email6',
  client_cc_email: 'email_mkvfwb7z',
  phone: 'phone_mkxe2jpy',
  account_name: 'text_mm29q4x3',
  brand_name: 'text_mkv57dxn',
  garden_link: 'link9',
  client_since: 'date_mm1y92xr',
};

async function queryMonday(apiKey, query, variables = {}) {
  const res = await fetch(MONDAY_ENDPOINT, {
    method: 'POST',
    headers: { 'Authorization': apiKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query, variables }),
  });
  if (!res.ok) throw new Error(`Monday HTTP ${res.status}: ${await res.text()}`);
  const j = await res.json();
  if (j.errors) throw new Error(JSON.stringify(j.errors));
  return j.data;
}

function pickText(values, colId) {
  const c = values.find(v => v.id === colId);
  return c && c.text ? String(c.text).trim() : null;
}

function pickEmail(values, colId) {
  const c = values.find(v => v.id === colId);
  if (!c) return null;
  try {
    const v = c.value ? JSON.parse(c.value) : null;
    if (v && v.email) return v.email;
  } catch(e) {}
  return c.text ? c.text.trim() : null;
}

function pickLink(values, colId) {
  const c = values.find(v => v.id === colId);
  if (!c) return null;
  try {
    const v = c.value ? JSON.parse(c.value) : null;
    if (v && v.url) return v.url;
  } catch(e) {}
  return c.text ? c.text.trim() : null;
}

function pickDate(values, colId) {
  const c = values.find(v => v.id === colId);
  if (!c) return null;
  try {
    const v = c.value ? JSON.parse(c.value) : null;
    if (v && v.date) return v.date;
  } catch(e) {}
  return null;
}

function pickStatus(values, colId) {
  const c = values.find(v => v.id === colId);
  return c && c.text ? String(c.text).trim() : null;
}

module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  if (req.method === 'OPTIONS') { res.status(200).end(); return; }
  const apiKey = process.env.MONDAY_API_KEY;
  if (!apiKey) { res.status(500).json({ error: 'MONDAY_API_KEY not set' }); return; }

  try {
    // Paginated fetch (up to ~500 partners)
    let allItems = [];
    let cursor = null;
    const query = `
      query($boardId:[ID!], $cursor:String) {
        boards(ids:$boardId) {
          items_page(limit:100, cursor:$cursor) {
            cursor
            items { id name column_values { id text value } }
          }
        }
      }`;
    const firstQuery = `
      query($boardId:[ID!]) {
        boards(ids:$boardId) {
          items_page(limit:100) {
            cursor
            items { id name column_values { id text value } }
          }
        }
      }`;
    let data = await queryMonday(apiKey, firstQuery, { boardId: [PARTNER_BOARD_ID] });
    let page = data.boards[0].items_page;
    allItems = allItems.concat(page.items);
    cursor = page.cursor;
    while (cursor) {
      data = await queryMonday(apiKey, query, { boardId: [PARTNER_BOARD_ID], cursor });
      page = data.boards[0].items_page;
      allItems = allItems.concat(page.items);
      cursor = page.cursor;
    }

    const partners = allItems.map(it => {
      const v = it.column_values;
      return {
        monday_id: it.id,
        name: it.name,
        brand_name: pickText(v, COLS.brand_name) || it.name,
        account_name: pickText(v, COLS.account_name),
        client_name: pickText(v, COLS.client_name),
        client_email: pickEmail(v, COLS.client_email),
        client_cc_email: pickEmail(v, COLS.client_cc_email),
        phone: pickText(v, COLS.phone),
        garden_account_link: pickLink(v, COLS.garden_link),
        client_since: pickDate(v, COLS.client_since),
        garden_status: pickStatus(v, COLS.status),
        inventory_status: pickStatus(v, COLS.inv_status),
        csm: pickText(v, COLS.csm),
        osm: pickText(v, COLS.osm),
        psm: pickText(v, COLS.psm),
      };
    });

    res.status(200).json({ count: partners.length, partners });
  } catch (e) {
    res.status(500).json({ error: String(e.message || e) });
  }
};
