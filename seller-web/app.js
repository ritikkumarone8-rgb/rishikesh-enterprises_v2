// Rishikesh Enterprises — Seller Dashboard
// Vanilla JS, no build step. Talks directly to the new Supabase backend
// (backend/sql/001_schema.sql) using the anon key + Row Level Security —
// every write here is only as powerful as the `is_seller()` RLS policies
// allow, so a tampered client can never do more than a real seller login
// already can. See docs/BACKEND_SETUP.md for how a seller login is created.

const { createClient } = supabase; // supabase-js UMD global is `supabase`
const sb = createClient(window.APP_CONFIG.SUPABASE_URL, window.APP_CONFIG.SUPABASE_ANON_KEY);

// ---------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------
function escapeHtml(str) {
  if (str === null || str === undefined) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function money(n) {
  const v = Number(n || 0);
  return '₹' + v.toLocaleString('en-IN', { maximumFractionDigits: 0 });
}

function toast(message, type) {
  const container = document.getElementById('toast-container');
  const el = document.createElement('div');
  el.className = 'toast' + (type ? ' ' + type : '');
  el.textContent = message;
  container.appendChild(el);
  setTimeout(() => el.remove(), 4000);
}

function friendlyError(err) {
  const msg = (err && err.message) ? err.message : String(err);
  if (/violates foreign key constraint/i.test(msg)) {
    return "Can't delete this — it's referenced by existing orders. Try deactivating it instead.";
  }
  if (/JWT|not authenticated|401/i.test(msg)) {
    return 'Your session expired. Please log in again.';
  }
  return msg;
}

// ---------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------
let currentSeller = null; // { id, email, name }

async function init() {
  const { data: { session } } = await sb.auth.getSession();
  if (session) {
    await tryEnterApp(session);
  } else {
    showLogin();
  }
}

function showLogin(message) {
  document.getElementById('login-screen').style.display = 'flex';
  document.getElementById('app').classList.remove('active');
  document.getElementById('app').style.display = 'none';
  if (message) {
    const err = document.getElementById('login-error');
    err.textContent = message;
    err.style.display = 'block';
  }
}

async function tryEnterApp(session) {
  // Defense in depth: even though only sellers are ever given email/password
  // logins (customers use phone OTP only), we still verify server-side that
  // this account is a seller before showing any admin UI or issuing writes.
  const { data: isSeller, error } = await sb.rpc('is_seller');
  if (error || !isSeller) {
    await sb.auth.signOut();
    showLogin('This account is not authorized for the seller dashboard.');
    return;
  }
  currentSeller = { id: session.user.id, email: session.user.email };
  document.getElementById('who-email').textContent = session.user.email || '';
  document.getElementById('login-screen').style.display = 'none';
  document.getElementById('app').style.display = 'flex';
  document.getElementById('app').classList.add('active');
  await bootstrapData();
  switchView('dashboard');
}

document.getElementById('login-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const email = document.getElementById('login-email').value.trim();
  const password = document.getElementById('login-password').value;
  const btn = document.getElementById('login-submit');
  const err = document.getElementById('login-error');
  err.style.display = 'none';
  btn.disabled = true;
  btn.textContent = 'Signing in…';
  try {
    const { data, error } = await sb.auth.signInWithPassword({ email, password });
    if (error) throw error;
    await tryEnterApp(data.session);
  } catch (e2) {
    err.textContent = 'Incorrect email or password.';
    err.style.display = 'block';
  } finally {
    btn.disabled = false;
    btn.textContent = 'Sign in';
  }
});

document.getElementById('logout-btn').addEventListener('click', async () => {
  await sb.auth.signOut();
  currentSeller = null;
  window.location.reload();
});

// ---------------------------------------------------------------------
// Navigation
// ---------------------------------------------------------------------
const viewLoaders = {
  dashboard: loadDashboard,
  products: loadProducts,
  orders: loadOrders,
  deals: loadDeals,
  customers: loadCustomers,
};

function switchView(name) {
  document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
  document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
  document.getElementById('view-' + name).classList.add('active');
  document.querySelector('.nav-btn[data-view="' + name + '"]').classList.add('active');
  if (viewLoaders[name]) viewLoaders[name]();
}

document.querySelectorAll('.nav-btn').forEach(btn => {
  btn.addEventListener('click', () => switchView(btn.dataset.view));
});

// ---------------------------------------------------------------------
// Shared reference data (categories / brands), loaded once
// ---------------------------------------------------------------------
let categoriesCache = [];
let brandsCache = [];

async function bootstrapData() {
  const [{ data: cats }, { data: brands }] = await Promise.all([
    sb.from('categories').select('*').order('sort_order'),
    sb.from('brands').select('*').order('sort_order'),
  ]);
  categoriesCache = cats || [];
  brandsCache = brands || [];

  const catFilter = document.getElementById('product-category-filter');
  catFilter.innerHTML = '<option value="">All categories</option>' +
    categoriesCache.map(c => `<option value="${c.id}">${escapeHtml(c.name)}</option>`).join('');
}

function categoryName(id) {
  const c = categoriesCache.find(c => c.id === id);
  return c ? c.name : '—';
}

// ---------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------
async function loadDashboard() {
  try {
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);
    const monthAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);

    const [
      totalProducts,
      outOfStock,
      lowStock,
      pendingOrders,
      todayOrders,
      customersCount,
      recentOrders,
    ] = await Promise.all([
      sb.from('products').select('id', { count: 'exact', head: true }),
      sb.from('products').select('id', { count: 'exact', head: true }).lte('stock', 0),
      sb.from('products').select('id', { count: 'exact', head: true }).gt('stock', 0).lte('stock', 5),
      sb.from('orders').select('id', { count: 'exact', head: true }).eq('status', 'new'),
      sb.from('orders').select('grand_total, created_at').gte('created_at', todayStart.toISOString()),
      sb.from('customers').select('id', { count: 'exact', head: true }),
      sb.from('orders').select('*, customers(phone), order_items(*)').order('created_at', { ascending: false }).limit(10),
    ]);

    const monthOrders = await sb.from('orders').select('grand_total').gte('created_at', monthAgo.toISOString());

    document.getElementById('kpi-products').textContent = totalProducts.count ?? '—';
    document.getElementById('kpi-oos').textContent = outOfStock.count ?? '—';
    document.getElementById('kpi-low').textContent = lowStock.count ?? '—';
    document.getElementById('kpi-pending').textContent = pendingOrders.count ?? '—';
    document.getElementById('kpi-customers').textContent = customersCount.count ?? '—';

    const todayRows = todayOrders.data || [];
    document.getElementById('kpi-today-orders').textContent = todayRows.length;
    document.getElementById('kpi-today-revenue').textContent = money(todayRows.reduce((s, o) => s + Number(o.grand_total), 0));

    const monthRows = monthOrders.data || [];
    document.getElementById('kpi-month-revenue').textContent = money(monthRows.reduce((s, o) => s + Number(o.grand_total), 0));

    const body = document.getElementById('recent-orders-body');
    const orders = recentOrders.data || [];
    if (orders.length === 0) {
      body.innerHTML = '<tr><td colspan="6" class="empty-state">No orders yet.</td></tr>';
    } else {
      body.innerHTML = orders.map(o => `
        <tr>
          <td><strong>#${escapeHtml(o.order_code)}</strong></td>
          <td>${escapeHtml(o.customers?.phone || '—')}</td>
          <td>${money(o.grand_total)}</td>
          <td>${paymentBadge(o.payment_status)}</td>
          <td>${statusBadge(o.status)}</td>
          <td>${new Date(o.created_at).toLocaleString('en-IN')}</td>
        </tr>
      `).join('');
    }
  } catch (e) {
    toast(friendlyError(e), 'error');
  }
}

function statusBadge(status) {
  const map = {
    new: ['badge-warn', 'New'],
    confirmed: ['badge-ok', 'Confirmed'],
    in_transit: ['badge-ok', 'In transit'],
    fulfilled: ['badge-ok', 'Fulfilled'],
    cancelled: ['badge-danger', 'Cancelled'],
  };
  const [cls, label] = map[status] || ['badge-muted', status];
  return `<span class="badge ${cls}">${label}</span>`;
}

function paymentBadge(status) {
  const map = {
    pending: ['badge-warn', 'Pending'],
    paid: ['badge-ok', 'Paid'],
    failed: ['badge-danger', 'Failed'],
    cancelled: ['badge-muted', 'Cancelled'],
  };
  const [cls, label] = map[status] || ['badge-muted', status];
  return `<span class="badge ${cls}">${label}</span>`;
}

// ---------------------------------------------------------------------
// Products
// ---------------------------------------------------------------------
let productsFilterDebounce = null;

async function loadProducts() {
  const body = document.getElementById('products-body');
  body.innerHTML = '<tr><td colspan="8" class="empty-state">Loading…</td></tr>';

  const search = document.getElementById('product-search').value.trim();
  const categoryId = document.getElementById('product-category-filter').value;
  const status = document.getElementById('product-status-filter').value;

  let query = sb.from('products').select('*, product_images(*)').order('created_at', { ascending: false });
  if (search) query = query.ilike('name', `%${search}%`);
  if (categoryId) query = query.eq('category_id', categoryId);
  if (status === 'active') query = query.eq('is_active', true);
  if (status === 'inactive') query = query.eq('is_active', false);
  if (status === 'oos') query = query.lte('stock', 0);

  const { data, error } = await query.limit(200);
  if (error) {
    body.innerHTML = `<tr><td colspan="8" class="empty-state">${escapeHtml(friendlyError(error))}</td></tr>`;
    return;
  }
  if (!data || data.length === 0) {
    body.innerHTML = '<tr><td colspan="8" class="empty-state">No products match. Try "+ Add product".</td></tr>';
    return;
  }

  body.innerHTML = data.map(p => {
    const cover = (p.product_images || []).slice().sort((a, b) => a.sort_order - b.sort_order)[0];
    const stockClass = p.stock <= 0 ? 'style="color:var(--danger);font-weight:700"' : (p.stock <= 5 ? 'style="color:var(--warn);font-weight:700"' : '');
    return `
      <tr data-id="${p.id}">
        <td>${cover ? `<img class="thumb" src="${escapeHtml(cover.url)}">` : `<div class="thumb"></div>`}</td>
        <td><strong>${escapeHtml(p.name)}</strong><br><span class="hint-text">${escapeHtml(p.sku || '')}</span></td>
        <td>${escapeHtml(categoryName(p.category_id))}</td>
        <td>${money(p.price)}${p.mrp && p.mrp > p.price ? `<br><span class="hint-text" style="text-decoration:line-through">${money(p.mrp)}</span>` : ''}</td>
        <td>
          <input type="number" min="0" class="stock-input" value="${p.stock}" data-product-id="${p.id}">
          <button class="btn btn-outline btn-sm save-stock-btn" data-product-id="${p.id}">Save</button>
        </td>
        <td>${p.is_active ? '<span class="badge badge-ok">Active</span>' : '<span class="badge badge-muted">Inactive</span>'}</td>
        <td>${p.rating_count > 0 ? `★ ${p.avg_rating} (${p.rating_count})` : '—'}</td>
        <td>
          <button class="btn btn-outline btn-sm edit-product-btn" data-product-id="${p.id}">Edit</button>
        </td>
      </tr>
    `;
  }).join('');

  body.querySelectorAll('.save-stock-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
      const id = btn.dataset.productId;
      const input = body.querySelector(`.stock-input[data-product-id="${id}"]`);
      const newStock = parseInt(input.value, 10);
      if (isNaN(newStock) || newStock < 0) { toast('Enter a valid stock quantity', 'error'); return; }
      btn.disabled = true;
      const { error } = await sb.from('products').update({ stock: newStock }).eq('id', id);
      btn.disabled = false;
      if (error) { toast(friendlyError(error), 'error'); return; }
      toast('Stock updated', 'success');
      loadProducts();
    });
  });

  body.querySelectorAll('.edit-product-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const product = data.find(p => p.id === btn.dataset.productId);
      openProductModal(product);
    });
  });
}

document.getElementById('product-search').addEventListener('input', () => {
  clearTimeout(productsFilterDebounce);
  productsFilterDebounce = setTimeout(loadProducts, 350);
});
document.getElementById('product-category-filter').addEventListener('change', loadProducts);
document.getElementById('product-status-filter').addEventListener('change', loadProducts);
document.getElementById('add-product-btn').addEventListener('click', () => openProductModal(null));

// ---- Product add/edit modal ----
function openProductModal(product) {
  const root = document.getElementById('modal-root');
  const isEdit = !!product;
  const images = isEdit ? (product.product_images || []).slice().sort((a, b) => a.sort_order - b.sort_order) : [];

  root.innerHTML = `
    <div class="modal-backdrop" id="product-modal-backdrop">
      <div class="modal">
        <h3>${isEdit ? 'Edit product' : 'Add product'}</h3>
        <form id="product-form">
          <div class="field"><label>Product name *</label><input id="pf-name" required value="${escapeHtml(product?.name || '')}"></div>
          <div class="row-2">
            <div class="field"><label>SKU</label><input id="pf-sku" value="${escapeHtml(product?.sku || '')}"></div>
            <div class="field"><label>Brand</label>
              <select id="pf-brand"><option value="">— None —</option>
                ${brandsCache.map(b => `<option value="${b.id}" ${product?.brand_id === b.id ? 'selected' : ''}>${escapeHtml(b.name)}</option>`).join('')}
              </select>
            </div>
          </div>
          <div class="row-2">
            <div class="field"><label>Category</label>
              <select id="pf-category"><option value="">— None —</option>
                ${categoriesCache.map(c => `<option value="${c.id}" ${product?.category_id === c.id ? 'selected' : ''}>${escapeHtml(c.name)}</option>`).join('')}
              </select>
            </div>
            <div class="field"><label>Stock *</label><input id="pf-stock" type="number" min="0" required value="${product?.stock ?? 0}"></div>
          </div>
          <div class="row-2">
            <div class="field"><label>Selling price (₹) *</label><input id="pf-price" type="number" min="0.01" step="0.01" required value="${product?.price ?? ''}"></div>
            <div class="field"><label>MRP (₹)</label><input id="pf-mrp" type="number" min="0" step="0.01" value="${product?.mrp ?? ''}"></div>
          </div>
          <div class="field"><label>Description</label><textarea id="pf-description" rows="3">${escapeHtml(product?.description || '')}</textarea></div>
          <div class="row-2">
            <label class="hint-text"><input type="checkbox" id="pf-active" ${!isEdit || product?.is_active ? 'checked' : ''}> Active (visible to customers)</label>
            <label class="hint-text"><input type="checkbox" id="pf-popular" ${product?.is_popular ? 'checked' : ''}> Show in "Popular products"</label>
          </div>

          <div class="field" style="margin-top:16px">
            <label>Product photos (customers can scroll through all of these)</label>
            ${isEdit ? `
              <div class="image-uploader" id="image-drop-zone">
                Drag &amp; drop photos here, or click to choose files (JPG/PNG, up to 8MB each)
                <input type="file" id="image-file-input" accept="image/*" multiple style="display:none">
              </div>
              <div class="image-grid" id="image-grid">
                ${images.map((img, i) => imageTileHtml(img, i === 0)).join('')}
              </div>
            ` : `<p class="hint-text">Save the product details first, then you'll be able to add photos.</p>`}
          </div>

          <p id="product-form-error" class="error-text" style="display:none"></p>
          <div class="actions">
            <button type="button" class="btn btn-outline" id="product-modal-cancel">Cancel</button>
            <button type="submit" class="btn btn-primary" id="product-modal-save">${isEdit ? 'Save changes' : 'Save & add photos'}</button>
          </div>
        </form>
      </div>
    </div>
  `;

  document.getElementById('product-modal-cancel').addEventListener('click', closeProductModal);
  document.getElementById('product-modal-backdrop').addEventListener('click', (e) => {
    if (e.target.id === 'product-modal-backdrop') closeProductModal();
  });

  if (isEdit) {
    wireImageUploader(product.id);
  }

  document.getElementById('product-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    await saveProductDetails(product);
  });
}

function closeProductModal() {
  document.getElementById('modal-root').innerHTML = '';
  loadProducts();
}

function imageTileHtml(img, isCover) {
  return `
    <div class="image-tile" data-image-id="${img.id}">
      <img src="${escapeHtml(img.url)}">
      ${isCover ? '<span class="cover-badge">COVER</span>' : ''}
      <div class="tile-actions">
        <button type="button" class="move-up-btn" title="Move earlier">↑</button>
        <button type="button" class="move-down-btn" title="Move later">↓</button>
        <button type="button" class="danger delete-image-btn" title="Delete">✕</button>
      </div>
    </div>
  `;
}

async function saveProductDetails(existingProduct) {
  const errorEl = document.getElementById('product-form-error');
  errorEl.style.display = 'none';
  const saveBtn = document.getElementById('product-modal-save');

  const name = document.getElementById('pf-name').value.trim();
  const sku = document.getElementById('pf-sku').value.trim();
  const brandId = document.getElementById('pf-brand').value || null;
  const categoryId = document.getElementById('pf-category').value || null;
  const stock = parseInt(document.getElementById('pf-stock').value, 10);
  const price = parseFloat(document.getElementById('pf-price').value);
  const mrpRaw = document.getElementById('pf-mrp').value;
  const mrp = mrpRaw === '' ? null : parseFloat(mrpRaw);
  const description = document.getElementById('pf-description').value.trim();
  const isActive = document.getElementById('pf-active').checked;
  const isPopular = document.getElementById('pf-popular').checked;

  if (!name || isNaN(price) || price <= 0 || isNaN(stock) || stock < 0) {
    errorEl.textContent = 'Please fill in a valid name, price and stock.';
    errorEl.style.display = 'block';
    return;
  }
  if (mrp !== null && mrp < price) {
    errorEl.textContent = 'MRP cannot be lower than the selling price.';
    errorEl.style.display = 'block';
    return;
  }

  const payload = {
    name, sku: sku || null, brand_id: brandId, category_id: categoryId,
    stock, price, mrp, description: description || null,
    is_active: isActive, is_popular: isPopular,
  };

  saveBtn.disabled = true;
  saveBtn.textContent = 'Saving…';
  try {
    if (existingProduct) {
      const { error } = await sb.from('products').update(payload).eq('id', existingProduct.id);
      if (error) throw error;
      toast('Product updated', 'success');
      closeProductModal();
    } else {
      const { data, error } = await sb.from('products').insert(payload).select().single();
      if (error) throw error;
      toast('Product created — now add some photos', 'success');
      // Re-open the modal in edit mode so photos can be added right away.
      openProductModal(data);
    }
  } catch (e) {
    errorEl.textContent = friendlyError(e);
    errorEl.style.display = 'block';
  } finally {
    saveBtn.disabled = false;
    saveBtn.textContent = existingProduct ? 'Save changes' : 'Save & add photos';
  }
}

// ---- Multi-image uploader ----
function wireImageUploader(productId) {
  const dropZone = document.getElementById('image-drop-zone');
  const fileInput = document.getElementById('image-file-input');
  if (!dropZone) return;

  dropZone.addEventListener('click', () => fileInput.click());
  dropZone.addEventListener('dragover', (e) => { e.preventDefault(); dropZone.classList.add('dragover'); });
  dropZone.addEventListener('dragleave', () => dropZone.classList.remove('dragover'));
  dropZone.addEventListener('drop', (e) => {
    e.preventDefault();
    dropZone.classList.remove('dragover');
    handleImageFiles(productId, e.dataTransfer.files);
  });
  fileInput.addEventListener('change', () => {
    handleImageFiles(productId, fileInput.files);
    fileInput.value = '';
  });

  wireImageGridActions(productId);
}

function wireImageGridActions(productId) {
  const grid = document.getElementById('image-grid');
  if (!grid) return;
  grid.querySelectorAll('.delete-image-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
      const tile = btn.closest('.image-tile');
      const imageId = tile.dataset.imageId;
      if (!confirm('Delete this photo?')) return;
      const { data: row } = await sb.from('product_images').select('url').eq('id', imageId).single();
      await sb.from('product_images').delete().eq('id', imageId);
      if (row?.url) {
        const path = storagePathFromPublicUrl(row.url);
        if (path) await sb.storage.from('product-images').remove([path]);
      }
      refreshImageGrid(productId);
    });
  });
  grid.querySelectorAll('.move-up-btn').forEach(btn => btn.addEventListener('click', () => reorderImage(productId, btn, -1)));
  grid.querySelectorAll('.move-down-btn').forEach(btn => btn.addEventListener('click', () => reorderImage(productId, btn, 1)));
}

async function reorderImage(productId, btn, direction) {
  const tile = btn.closest('.image-tile');
  const grid = document.getElementById('image-grid');
  const tiles = Array.from(grid.children);
  const index = tiles.indexOf(tile);
  const swapWith = tiles[index + direction];
  if (!swapWith) return;

  const { data: images } = await sb.from('product_images').select('*').eq('product_id', productId).order('sort_order');
  const a = images[index];
  const b = images[index + direction];
  if (!a || !b) return;
  await Promise.all([
    sb.from('product_images').update({ sort_order: b.sort_order }).eq('id', a.id),
    sb.from('product_images').update({ sort_order: a.sort_order }).eq('id', b.id),
  ]);
  refreshImageGrid(productId);
}

async function refreshImageGrid(productId) {
  const { data: images } = await sb.from('product_images').select('*').eq('product_id', productId).order('sort_order');
  const grid = document.getElementById('image-grid');
  if (!grid) return;
  grid.innerHTML = (images || []).map((img, i) => imageTileHtml(img, i === 0)).join('');
  wireImageGridActions(productId);
}

const MAX_IMAGE_BYTES = 8 * 1024 * 1024;

async function handleImageFiles(productId, fileList) {
  const files = Array.from(fileList || []);
  if (files.length === 0) return;

  const grid = document.getElementById('image-grid');
  const { data: existing } = await sb.from('product_images').select('sort_order').eq('product_id', productId).order('sort_order', { ascending: false }).limit(1);
  let nextSort = existing && existing.length > 0 ? existing[0].sort_order + 1 : 0;

  for (const file of files) {
    if (!file.type.startsWith('image/')) {
      toast(`${file.name} isn't an image — skipped.`, 'error');
      continue;
    }
    if (file.size > MAX_IMAGE_BYTES) {
      toast(`${file.name} is larger than 8MB — skipped.`, 'error');
      continue;
    }

    const placeholder = document.createElement('div');
    placeholder.className = 'image-tile uploading';
    placeholder.innerHTML = `<div class="spinner">⏳</div>`;
    grid.appendChild(placeholder);

    try {
      const ext = (file.name.split('.').pop() || 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '') || 'jpg';
      const path = `${productId}/${crypto.randomUUID()}.${ext}`;
      const { error: uploadError } = await sb.storage.from('product-images').upload(path, file, { cacheControl: '3600', upsert: false });
      if (uploadError) throw uploadError;
      const { data: publicUrlData } = sb.storage.from('product-images').getPublicUrl(path);
      const { error: insertError } = await sb.from('product_images').insert({
        product_id: productId, url: publicUrlData.publicUrl, sort_order: nextSort++,
      });
      if (insertError) throw insertError;
    } catch (e) {
      toast(`Could not upload ${file.name}: ${friendlyError(e)}`, 'error');
    } finally {
      placeholder.remove();
    }
  }
  refreshImageGrid(productId);
}

function storagePathFromPublicUrl(url) {
  // Public URLs look like: https://<ref>.supabase.co/storage/v1/object/public/product-images/<path>
  const marker = '/object/public/product-images/';
  const idx = url.indexOf(marker);
  if (idx === -1) return null;
  return url.slice(idx + marker.length);
}

// ---------------------------------------------------------------------
// Orders
// ---------------------------------------------------------------------
async function loadOrders() {
  const list = document.getElementById('orders-list');
  list.innerHTML = '<div class="empty-state">Loading…</div>';

  const status = document.getElementById('order-status-filter').value;
  let query = sb.from('orders').select('*, customers(phone, name), order_items(*)').order('created_at', { ascending: false });
  if (status) query = query.eq('status', status);

  const { data, error } = await query.limit(100);
  if (error) {
    list.innerHTML = `<div class="empty-state">${escapeHtml(friendlyError(error))}</div>`;
    return;
  }
  if (!data || data.length === 0) {
    list.innerHTML = '<div class="empty-state">No orders found.</div>';
    return;
  }

  list.innerHTML = data.map(o => orderCardHtml(o)).join('');

  list.querySelectorAll('.order-status-select').forEach(sel => {
    sel.addEventListener('change', async () => {
      const orderId = sel.dataset.orderId;
      const newStatus = sel.value;
      sel.disabled = true;
      const { error } = await sb.from('orders').update({ status: newStatus }).eq('id', orderId);
      sel.disabled = false;
      if (error) { toast(friendlyError(error), 'error'); return; }
      toast('Order status updated', 'success');
      loadDashboard();
    });
  });

  list.querySelectorAll('.order-header').forEach(header => {
    header.addEventListener('click', () => {
      header.closest('.order-card').querySelector('.order-body').classList.toggle('hidden');
    });
  });
}

document.getElementById('order-status-filter').addEventListener('change', loadOrders);

function orderCardHtml(o) {
  const addr = o.address_snapshot;
  const addrLine = o.delivery_mode === 'pickup'
    ? 'Store pickup'
    : (addr ? [addr.line1, addr.line2, addr.landmark, addr.city, addr.state, addr.pincode].filter(Boolean).join(', ') : '—');

  return `
    <div class="order-card" style="background:var(--card);border:1px solid var(--line);border-radius:12px;margin-bottom:12px;overflow:hidden">
      <div class="order-header" style="padding:14px 16px;display:flex;justify-content:space-between;align-items:center;cursor:pointer">
        <div>
          <strong>#${escapeHtml(o.order_code)}</strong>
          <span class="hint-text"> · ${escapeHtml(o.customers?.phone || '—')} · ${new Date(o.created_at).toLocaleString('en-IN')}</span>
        </div>
        <div style="display:flex;gap:8px;align-items:center">
          ${paymentBadge(o.payment_status)}
          <select class="order-status-select" data-order-id="${o.id}">
            ${['new', 'confirmed', 'in_transit', 'fulfilled', 'cancelled'].map(s =>
              `<option value="${s}" ${o.status === s ? 'selected' : ''}>${s.replace('_', ' ')}</option>`).join('')}
          </select>
        </div>
      </div>
      <div class="order-body hidden" style="padding:0 16px 16px;border-top:1px solid var(--line)">
        <p class="hint-text" style="margin:10px 0 4px"><strong>${o.delivery_mode === 'pickup' ? 'Pickup' : 'Deliver to'}:</strong> ${escapeHtml(addrLine)}</p>
        <table style="margin-top:8px">
          <thead><tr><th>Item</th><th>Qty</th><th>Price</th><th>Total</th></tr></thead>
          <tbody>
            ${(o.order_items || []).map(it => `
              <tr><td>${escapeHtml(it.product_name)}</td><td>${it.qty}</td><td>${money(it.unit_price)}</td><td>${money(it.final_amount)}</td></tr>
            `).join('')}
          </tbody>
        </table>
        <p style="text-align:right;margin-top:8px">
          Subtotal: ${money(o.subtotal)}
          ${o.discount_total > 0 ? ` · Discount: -${money(o.discount_total)}` : ''}
          ${o.cod_fee > 0 ? ` · COD fee: ${money(o.cod_fee)}` : ''}
          · <strong>Total: ${money(o.grand_total)}</strong>
        </p>
      </div>
    </div>
  `;
}

// ---------------------------------------------------------------------
// Deals
// ---------------------------------------------------------------------
async function loadDeals() {
  const body = document.getElementById('deals-body');
  body.innerHTML = '<tr><td colspan="5" class="empty-state">Loading…</td></tr>';
  const { data, error } = await sb.from('deals').select('*').order('created_at', { ascending: false });
  if (error) { body.innerHTML = `<tr><td colspan="5" class="empty-state">${escapeHtml(friendlyError(error))}</td></tr>`; return; }
  if (!data || data.length === 0) { body.innerHTML = '<tr><td colspan="5" class="empty-state">No deals yet.</td></tr>'; return; }

  body.innerHTML = data.map(d => `
    <tr data-id="${d.id}">
      <td><strong>${escapeHtml(d.title)}</strong>${d.description ? `<br><span class="hint-text">${escapeHtml(d.description)}</span>` : ''}</td>
      <td>${escapeHtml(categoryName(d.category_id))}</td>
      <td>${d.is_active ? '<span class="badge badge-ok">Active</span>' : '<span class="badge badge-muted">Inactive</span>'}</td>
      <td>${d.start_date || '—'} → ${d.end_date || '—'}</td>
      <td><button class="btn btn-outline btn-sm delete-deal-btn" data-id="${d.id}">Delete</button></td>
    </tr>
  `).join('');

  body.querySelectorAll('.delete-deal-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
      if (!confirm('Delete this deal?')) return;
      const { error } = await sb.from('deals').delete().eq('id', btn.dataset.id);
      if (error) { toast(friendlyError(error), 'error'); return; }
      toast('Deal deleted', 'success');
      loadDeals();
    });
  });
}

document.getElementById('add-deal-btn').addEventListener('click', () => {
  const root = document.getElementById('modal-root');
  root.innerHTML = `
    <div class="modal-backdrop" id="deal-modal-backdrop">
      <div class="modal">
        <h3>Add deal</h3>
        <form id="deal-form">
          <div class="field"><label>Title *</label><input id="df-title" required></div>
          <div class="field"><label>Description</label><textarea id="df-description" rows="2"></textarea></div>
          <div class="field"><label>Category (optional — tapping the banner opens this category)</label>
            <select id="df-category"><option value="">— None —</option>
              ${categoriesCache.map(c => `<option value="${c.id}">${escapeHtml(c.name)}</option>`).join('')}
            </select>
          </div>
          <div class="field"><label>Banner image URL (optional)</label><input id="df-img" placeholder="https://…"></div>
          <div class="row-2">
            <div class="field"><label>Start date</label><input id="df-start" type="date"></div>
            <div class="field"><label>End date</label><input id="df-end" type="date"></div>
          </div>
          <p id="deal-form-error" class="error-text" style="display:none"></p>
          <div class="actions">
            <button type="button" class="btn btn-outline" id="deal-modal-cancel">Cancel</button>
            <button type="submit" class="btn btn-primary">Save deal</button>
          </div>
        </form>
      </div>
    </div>
  `;
  document.getElementById('deal-modal-cancel').addEventListener('click', () => { root.innerHTML = ''; });
  document.getElementById('deal-modal-backdrop').addEventListener('click', (e) => { if (e.target.id === 'deal-modal-backdrop') root.innerHTML = ''; });
  document.getElementById('deal-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const title = document.getElementById('df-title').value.trim();
    if (!title) return;
    const payload = {
      title,
      description: document.getElementById('df-description').value.trim() || null,
      category_id: document.getElementById('df-category').value || null,
      img: document.getElementById('df-img').value.trim() || null,
      start_date: document.getElementById('df-start').value || null,
      end_date: document.getElementById('df-end').value || null,
      is_active: true,
    };
    const { error } = await sb.from('deals').insert(payload);
    const errEl = document.getElementById('deal-form-error');
    if (error) { errEl.textContent = friendlyError(error); errEl.style.display = 'block'; return; }
    toast('Deal created', 'success');
    root.innerHTML = '';
    loadDeals();
  });
});

// ---------------------------------------------------------------------
// Customers (read-only)
// ---------------------------------------------------------------------
async function loadCustomers() {
  const body = document.getElementById('customers-body');
  body.innerHTML = '<tr><td colspan="3" class="empty-state">Loading…</td></tr>';
  const { data, error } = await sb.from('customers').select('*').order('created_at', { ascending: false }).limit(300);
  if (error) { body.innerHTML = `<tr><td colspan="3" class="empty-state">${escapeHtml(friendlyError(error))}</td></tr>`; return; }
  if (!data || data.length === 0) { body.innerHTML = '<tr><td colspan="3" class="empty-state">No customers yet.</td></tr>'; return; }
  body.innerHTML = data.map(c => `
    <tr>
      <td>${escapeHtml(c.phone || '—')}</td>
      <td>${escapeHtml(c.name || '—')}</td>
      <td>${new Date(c.created_at).toLocaleDateString('en-IN')}</td>
    </tr>
  `).join('');
}

// ---------------------------------------------------------------------
init();
