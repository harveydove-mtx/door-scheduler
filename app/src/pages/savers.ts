// Save helpers shared by the MAT codes and Products pages.
import type { SaveOutcome } from '../components/EditableCell';
import { errorMessage, matCodeOwner, setMatCode, setPrice, type PricedTable } from '../data/api';

export const normaliseMatCode = (v: string) => v.trim().toUpperCase();
export const MONEY = /^\d{1,9}(\.\d{1,2})?$/;
export const validatePrice = (v: string) => (MONEY.test(v) ? null : 'Enter a price like 12 or 12.50');
export const formatMoney = (n: number) => n.toFixed(2);

interface Target { table: PricedTable; id: string; version: number }

/**
 * Save a MAT code. Checks first whether another item already uses it, so the message can
 * say where; the database also enforces uniqueness in case two people race.
 * onSaved gets the row's new version; onConflict should reload the list.
 */
export async function saveMatCode(t: Target, code: string, onSaved: (version: number, code: string | null) => void,
                                  onConflict: () => void): Promise<SaveOutcome> {
  try {
    if (code) {
      const owner = await matCodeOwner(code);
      if (owner && owner.row_id !== t.id) return { status: 'error', message: `${code} is already used on: ${owner.item ?? owner.table_name}` };
    }
    const res = await setMatCode(t.table, t.id, t.version, code || null);
    if (!res.ok) { onConflict(); return { status: 'conflict' }; }
    onSaved(res.row.version, res.row.mat_code);
    return { status: 'saved' };
  } catch (e) {
    return { status: 'error', message: errorMessage(e) };
  }
}

export async function savePrice(t: Target, price: string, onSaved: (version: number, price: number) => void,
                                onConflict: () => void): Promise<SaveOutcome> {
  try {
    const res = await setPrice(t.table, t.id, t.version, price);
    if (!res.ok) { onConflict(); return { status: 'conflict' }; }
    onSaved(res.row.version, Number(res.row.price));
    return { status: 'saved' };
  } catch (e) {
    return { status: 'error', message: errorMessage(e) };
  }
}
