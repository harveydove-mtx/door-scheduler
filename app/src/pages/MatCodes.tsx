import { useCallback, useEffect, useState } from 'react';
import { EditableCell } from '../components/EditableCell';
import { errorMessage, matCodeTable, type ItemKind, type MatCodeRow } from '../data/api';
import { useDebounced } from './useDebounced';
import { formatMoney, normaliseMatCode, saveMatCode, savePrice, validatePrice } from './savers';

const KINDS: { value: ItemKind | ''; label: string }[] = [
  { value: '', label: 'Everything' },
  { value: 'product', label: 'Products (hardware)' },
  { value: 'door', label: 'Door rates' },
  { value: 'vision_panel', label: 'Vision panels' },
  { value: 'frame', label: 'Frames' },
  { value: 'lining', label: 'Linings' },
  { value: 'architrave', label: 'Architraves' },
  { value: 'over_panel', label: 'Over panels' },
];
const KIND_LABEL: Record<ItemKind, string> = {
  product: 'Product', door: 'Door', vision_panel: 'Vision panel', frame: 'Frame',
  lining: 'Lining', architrave: 'Architrave', over_panel: 'Over panel',
};

/** Every priced item in one list, for Matrix to fill in MAT codes (spec CAT-11) and prices. */
export function MatCodes() {
  const [kind, setKind] = useState<ItemKind | ''>('');
  const [onlyMissing, setOnlyMissing] = useState(false);
  const [search, setSearch] = useState('');
  const debounced = useDebounced(search, 250);
  const [rows, setRows] = useState<MatCodeRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setError(null);
      setRows(await matCodeTable({ kind: kind || null, onlyMissing, search: debounced, includeInactive: false }));
    } catch (e) {
      setError(errorMessage(e));
    }
  }, [kind, onlyMissing, debounced]);
  useEffect(() => { void load(); }, [load]);

  const patch = (r: MatCodeRow, change: Partial<MatCodeRow>) =>
    setRows(rs => rs?.map(x => (x.table_name === r.table_name && x.row_id === r.row_id ? { ...x, ...change } : x)) ?? rs);

  const missing = rows?.filter(r => !r.mat_code).length ?? 0;

  return (
    <section>
      <div className="page-head">
        <h1>MAT codes &amp; rates</h1>
        <p className="muted">Every priced item: hardware products and the door, vision panel, frame, lining, architrave and
          over panel rates. Type a MAT code or price and press Enter. Items without a MAT code are listed first.</p>
      </div>

      <div className="toolbar">
        <label>Show
          <select value={kind} onChange={e => setKind(e.target.value as ItemKind | '')}>
            {KINDS.map(k => <option key={k.value} value={k.value}>{k.label}</option>)}
          </select>
        </label>
        <label className="grow">Search
          <input type="search" value={search} placeholder="e.g. sasl fd30 veneer, or a MAT code"
                 onChange={e => setSearch(e.target.value)} />
        </label>
        <label className="check">
          <input type="checkbox" checked={onlyMissing} onChange={e => setOnlyMissing(e.target.checked)} />
          Missing MAT code only
        </label>
      </div>

      {error && <div className="banner banner--error" role="alert">{error} <button onClick={() => void load()}>Try again</button></div>}
      {rows && (
        <p className="count" aria-live="polite">
          {rows.length} item{rows.length === 1 ? '' : 's'}{onlyMissing ? '' : `, ${missing} without a MAT code`}
        </p>
      )}

      {!rows && !error && <p className="muted">Loading…</p>}
      {rows && rows.length === 0 && <p className="empty">Nothing matches. Try a different search or filter.</p>}
      {rows && rows.length > 0 && (
        <div className="table-wrap">
          <table className="grid">
            <thead>
              <tr><th>Type</th><th>Item</th><th>MAT code</th><th className="num">Cost / price £</th></tr>
            </thead>
            <tbody>
              {rows.map(r => {
                const target = { table: r.table_name, id: r.row_id, version: r.version };
                return (
                  <tr key={`${r.table_name}:${r.row_id}`} className={r.mat_code ? '' : 'row--missing'}>
                    <td><span className={`tag tag--${r.kind}`}>{KIND_LABEL[r.kind]}</span></td>
                    <td className="item">{r.item}</td>
                    <td>
                      <EditableCell
                        label={`MAT code for ${r.item}`} value={r.mat_code ?? ''} placeholder="Add MAT code" width="11rem"
                        normalise={normaliseMatCode}
                        onSave={v => saveMatCode(target, v, (version, mat_code) => patch(r, { version, mat_code }), () => void load())}
                      />
                    </td>
                    <td className="num">
                      <EditableCell
                        label={`Price for ${r.item}`} value={formatMoney(r.cost)} inputMode="decimal" width="7rem"
                        validate={validatePrice}
                        normalise={v => v.trim().replace(/^£/, '')}
                        onSave={v => savePrice(target, v, (version, cost) => patch(r, { version, cost }), () => void load())}
                      />
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
