import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { EditableCell, type SaveOutcome } from '../components/EditableCell';
import {
  addProduct, errorMessage, listCategories, matCodeOwner, searchProducts, updateProduct,
  type Category, type Product,
} from '../data/api';
import { MONEY, formatMoney, normaliseMatCode, saveMatCode, savePrice, validatePrice } from './savers';
import { useDebounced } from './useDebounced';

const UNITS = ['each', 'pair', 'set', 'metre', 'm2'];

/** The hardware catalogue (spec §3): search, add and edit products. */
export function Products() {
  const [categories, setCategories] = useState<Category[]>([]);
  const [categoryId, setCategoryId] = useState('');
  const [search, setSearch] = useState('');
  const [includeInactive, setIncludeInactive] = useState(false);
  const debounced = useDebounced(search, 250);
  const [rows, setRows] = useState<Product[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);

  useEffect(() => { listCategories().then(setCategories).catch(e => setError(errorMessage(e))); }, []);

  const load = useCallback(async () => {
    try {
      setError(null);
      setRows(await searchProducts({ search: debounced.trim(), categoryId: categoryId || null, includeInactive, limit: 500 }));
    } catch (e) {
      setError(errorMessage(e));
    }
  }, [debounced, categoryId, includeInactive]);
  useEffect(() => { void load(); }, [load]);

  const patch = (p: Product, change: Partial<Product>) =>
    setRows(rs => rs?.map(x => (x.id === p.id ? { ...x, ...change } : x)) ?? rs);

  /** Save one detail field; every product edit is versioned like the rest. */
  async function saveDetail(p: Product, change: Partial<Pick<Product, 'description' | 'supplier_code' | 'finish' | 'unit' | 'active'>>): Promise<SaveOutcome> {
    const next = { ...p, ...change };
    if (!next.description.trim()) return { status: 'error', message: 'A description is required' };
    try {
      const res = await updateProduct({
        id: p.id, version: p.version, description: next.description, supplierCode: next.supplier_code,
        finish: next.finish, unit: next.unit, active: next.active,
      });
      if (!res.ok) { void load(); return { status: 'conflict' }; }
      patch(p, { ...change, version: res.row.version });
      return { status: 'saved' };
    } catch (e) {
      return { status: 'error', message: errorMessage(e) };
    }
  }

  return (
    <section>
      <div className="page-head">
        <h1>Products</h1>
        <p className="muted">The hardware catalogue. New products are marked <em>unverified</em> until checked.</p>
      </div>

      <div className="toolbar">
        <label>Category
          <select value={categoryId} onChange={e => setCategoryId(e.target.value)}>
            <option value="">All categories</option>
            {categories.map(c => <option key={c.id} value={c.id}>{c.label}</option>)}
          </select>
        </label>
        <label className="grow">Search
          <input type="search" value={search} placeholder="MAT code, supplier code or description"
                 onChange={e => setSearch(e.target.value)} />
        </label>
        <label className="check">
          <input type="checkbox" checked={includeInactive} onChange={e => setIncludeInactive(e.target.checked)} />
          Include inactive
        </label>
        <button className="primary" onClick={() => setAdding(a => !a)} aria-expanded={adding}>
          {adding ? 'Close' : '+ Add product'}
        </button>
      </div>

      {adding && (
        <AddProductForm categories={categories} defaultCategoryId={categoryId}
                        onAdded={() => { setAdding(false); void load(); }} />
      )}

      {error && <div className="banner banner--error" role="alert">{error} <button onClick={() => void load()}>Try again</button></div>}
      {rows && <p className="count" aria-live="polite">{rows.length} product{rows.length === 1 ? '' : 's'}</p>}
      {!rows && !error && <p className="muted">Loading…</p>}
      {rows && rows.length === 0 && <p className="empty">No products match. Try a different search, or add one.</p>}
      {rows && rows.length > 0 && (
        <div className="table-wrap">
          <table className="grid">
            <thead>
              <tr>
                <th>Category</th><th>MAT code</th><th>Supplier code</th><th>Description</th><th>Finish</th>
                <th>Unit</th><th className="num">Cost £</th><th>Status</th>
              </tr>
            </thead>
            <tbody>
              {rows.map(p => {
                const target = { table: 'products' as const, id: p.id, version: p.version };
                return (
                  <tr key={p.id} className={p.active ? '' : 'row--inactive'}>
                    <td className="nowrap">{p.category_label}</td>
                    <td>
                      <EditableCell label={`MAT code for ${p.description}`} value={p.mat_code ?? ''} placeholder="Add MAT code"
                        width="9rem" normalise={normaliseMatCode}
                        onSave={v => saveMatCode(target, v, (version, mat_code) => patch(p, { version, mat_code }), () => void load())} />
                    </td>
                    <td>
                      <EditableCell label={`Supplier code for ${p.description}`} value={p.supplier_code ?? ''} width="9rem"
                        onSave={v => saveDetail(p, { supplier_code: v || null })} />
                    </td>
                    <td>
                      <EditableCell label={`Description of ${p.description}`} value={p.description} width="16rem"
                        validate={v => (v ? null : 'A description is required')}
                        onSave={v => saveDetail(p, { description: v })} />
                    </td>
                    <td>
                      <EditableCell label={`Finish of ${p.description}`} value={p.finish ?? ''} width="6rem"
                        onSave={v => saveDetail(p, { finish: v || null })} />
                    </td>
                    <td>
                      <select aria-label={`Unit for ${p.description}`} value={p.unit}
                              onChange={e => void saveDetail(p, { unit: e.target.value })}>
                        {UNITS.map(u => <option key={u}>{u}</option>)}
                      </select>
                    </td>
                    <td className="num">
                      <EditableCell label={`Cost of ${p.description}`} value={formatMoney(p.cost)} inputMode="decimal" width="6.5rem"
                        validate={validatePrice} normalise={v => v.trim().replace(/^£/, '')}
                        onSave={v => savePrice(target, v, (version, cost) => patch(p, { version, cost }), () => void load())} />
                    </td>
                    <td className="nowrap">
                      <label className="check">
                        <input type="checkbox" checked={p.active} onChange={e => void saveDetail(p, { active: e.target.checked })} />
                        Active
                      </label>
                      {!p.verified && <span className="tag tag--warn" title="Added in the app; awaiting a check">Unverified</span>}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

function AddProductForm({ categories, defaultCategoryId, onAdded }: {
  categories: Category[]; defaultCategoryId: string; onAdded: () => void;
}) {
  const [f, setF] = useState({ categoryId: defaultCategoryId, description: '', supplierCode: '', matCode: '', finish: '', unit: 'each', cost: '' });
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value });

  async function submit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    const cost = f.cost.trim().replace(/^£/, '');
    if (!f.categoryId) return setError('Choose a category');
    if (!f.description.trim()) return setError('Enter a description');
    if (!MONEY.test(cost)) return setError('Enter the cost like 12 or 12.50');
    setBusy(true);
    try {
      const code = normaliseMatCode(f.matCode);
      if (code) {
        const owner = await matCodeOwner(code);
        if (owner) { setError(`${code} is already used on: ${owner.item ?? owner.table_name}`); return; }
      }
      await addProduct({
        categoryId: f.categoryId, description: f.description, supplierCode: f.supplierCode || null,
        matCode: code || null, finish: f.finish || null, unit: f.unit, cost,
      });
      onAdded();
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className="card add-form" onSubmit={e => void submit(e)}>
      <h2>Add a product</h2>
      <div className="form-grid">
        <label>Category *
          <select value={f.categoryId} onChange={set('categoryId')} required>
            <option value="">Choose…</option>
            {categories.map(c => <option key={c.id} value={c.id}>{c.label}</option>)}
          </select>
        </label>
        <label className="span2">Description *<input value={f.description} onChange={set('description')} required /></label>
        <label>Supplier code<input value={f.supplierCode} onChange={set('supplierCode')} /></label>
        <label>MAT code<input value={f.matCode} onChange={set('matCode')} /></label>
        <label>Finish<input value={f.finish} onChange={set('finish')} placeholder="e.g. SSS" /></label>
        <label>Unit
          <select value={f.unit} onChange={set('unit')}>{UNITS.map(u => <option key={u}>{u}</option>)}</select>
        </label>
        <label>Cost £ *<input value={f.cost} onChange={set('cost')} inputMode="decimal" placeholder="0.00" required /></label>
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
      <button className="primary" type="submit" disabled={busy}>{busy ? 'Adding…' : 'Add product'}</button>
    </form>
  );
}
