// Typed wrappers around the Data Connect operations in dataconnect/connector/operations.gql
// (generated from db/queries). Each operation returns rows exactly as the SQL selects them.
import { QueryFetchPolicy, executeMutation, executeQuery, mutationRef, queryRef } from 'firebase/data-connect';
import { dataConnect } from './firebase';

// Always read from the server: the SDK's default (PREFER_CACHE) would show stale rows after
// someone else saves, which is exactly when a fresh read matters (conflict reloads).
async function q<T>(name: string, vars: Record<string, unknown> = {}): Promise<T> {
  const res = await executeQuery(queryRef<T, Record<string, unknown>>(dataConnect, name, vars),
                                 { fetchPolicy: QueryFetchPolicy.SERVER_ONLY });
  return res.data;
}
async function m<T>(name: string, vars: Record<string, unknown> = {}): Promise<T> {
  const res = await executeMutation(mutationRef<T, Record<string, unknown>>(dataConnect, name, vars));
  return res.data;
}

// ---------------------------------------------------------------------------

export interface Me { uid: string; email: string; display_name: string; role: string }
export const ensureMe = async () => (await m<{ _executeReturningFirst: Me }>('EnsureMe'))._executeReturningFirst;

export interface Setting { key: string; value: unknown; description: string; version: number }
export const getSettings = async () => (await q<{ _select: Setting[] }>('GetSettings'))._select;

export interface Category { id: string; key: string; label: string; door_field_key: string | null; sort: number; active: boolean }
export const listCategories = async () => (await q<{ _select: Category[] }>('ListCategories'))._select;

export type PricedTable = 'products' | 'door_rates' | 'vp_rates' | 'frame_rates' | 'lining_rates' | 'architrave_types' | 'over_panel_rates';
export type ItemKind = 'product' | 'door' | 'vision_panel' | 'frame' | 'lining' | 'architrave' | 'over_panel';

export interface MatCodeRow {
  kind: ItemKind; table_name: PricedTable; row_id: string; version: number;
  item: string; mat_code: string | null; cost: number; active: boolean;
}
export const matCodeTable = async (f: { kind: ItemKind | null; onlyMissing: boolean; search: string; includeInactive: boolean }) =>
  (await q<{ _select: MatCodeRow[] }>('MatCodeTable', { ...f, search: f.search.trim() || null }))._select;

export const matCodeOwner = async (matCode: string) =>
  (await q<{ _selectFirst: { table_name: PricedTable; row_id: string; item: string | null } | null }>('MatCodeOwner', { matCode }))._selectFirst;

/** Result of a versioned save: the new version, or 'conflict' if someone else saved that row first. */
export type SaveResult<T> = { ok: true; row: T } | { ok: false; conflict: true };
function firstRow<T>(data: Record<string, T[] | null>): SaveResult<T> {
  const row = Object.values(data).flatMap(rows => rows ?? [])[0];
  return row ? { ok: true, row } : { ok: false, conflict: true };
}

export const setMatCode = async (table: PricedTable, id: string, version: number, matCode: string | null) =>
  firstRow(await m<Record<string, { id: string; version: number; mat_code: string | null }[]>>('SetMatCode', { table, id, version, matCode }));

export const setPrice = async (table: PricedTable, id: string, version: number, price: string) =>
  firstRow(await m<Record<string, { id: string; version: number; price: number }[]>>('SetPrice', { table, id, version, price }));

export interface Product {
  id: string; version: number; mat_code: string | null; supplier_code: string | null; description: string;
  finish: string | null; unit: string; cost: number; active: boolean; verified: boolean;
  category_key: string; category_label: string;
}
export const searchProducts = async (f: { search: string; categoryId: string | null; includeInactive: boolean; limit: number }) =>
  (await q<{ _select: Product[] }>('SearchProducts', f))._select;

export interface NewProduct {
  categoryId: string; matCode: string | null; supplierCode: string | null; description: string;
  finish: string | null; unit: string | null; cost: string;
}
export const addProduct = async (p: NewProduct) =>
  (await m<{ _executeReturningFirst: { id: string; version: number } }>('AddProduct', { ...p }))._executeReturningFirst;

export interface ProductEdit {
  id: string; version: number; description: string; supplierCode: string | null;
  finish: string | null; unit: string | null; active: boolean;
}
export const updateProduct = async (p: ProductEdit): Promise<SaveResult<{ id: string; version: number }>> => {
  const row = (await m<{ _executeReturningFirst: { id: string; version: number } | null }>('UpdateProduct', { ...p }))._executeReturningFirst;
  return row ? { ok: true, row } : { ok: false, conflict: true };
};

/** A readable message from a Data Connect error. */
export function errorMessage(e: unknown): string {
  const msg = e instanceof Error ? e.message : String(e);
  if (/PERMISSION_DENIED|@auth rejected|unauthorized/i.test(msg)) return 'Your account is not allowed to do this.';
  if (/network|Failed to fetch/i.test(msg)) return 'Could not reach the server. Check your connection and try again.';
  return msg.length > 200 ? `${msg.slice(0, 200)}…` : msg;
}
