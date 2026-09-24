// Pricing engine: a port of V1 index.html calcDoorCost / calcFrameCost / calcArchCost /
// calcVPCost / calcOverPanelCost / calcHardwareCost / calcUnitCost / calcSellPrice
// (lines 1375-1515) and getWarnings (1520-1545), with the V1 bugs fixed (spec §13).
//
// Two steps, matching how V2 stores data:
//   1. priceSnapshot(line, rates): look up today's rates -> the cost + MAT code snapshot
//      saved on job_doors (spec JOB-06). Only done when a line is added/edited or repriced.
//   2. lineTotals(line, snapshot, markup, threshold): add up the SAVED snapshot. This is the
//      same arithmetic as the database view v_job_door_lines, so screen and DB always agree.
// priceDoor() does both, plus the warnings.

import { applyMarkup, sumQtyTimesCostPence, toPence, toPounds } from './money';
import type {
  DoorLine, DoorSnapshot, OverPanelRate, PricedDoor, RateBook, Warning,
} from './types';

interface Priced { price: number; matCode: string | null }
const ZERO: Priced = { price: 0, matCode: null };

// ---------------------------------------------------------------------------
// Step 1: snapshot from rates
// ---------------------------------------------------------------------------

export function priceSnapshot(line: DoorLine, rates: RateBook): { snapshot: DoorSnapshot; warnings: Warning[] } {
  const warnings: Warning[] = [];
  const noRate = (message: string): Priced => {
    warnings.push({ code: 'NO_RATE', message });
    return ZERO;
  };
  const doorType = line.doorTypeId ? rates.doorTypes.find(t => t.id === line.doorTypeId) : undefined;
  const typeLabel = doorType?.formCode ?? 'manual door';

  // Door leaf
  let door: Priced = ZERO;
  if (line.isManual) {
    door = { price: line.manualCost ?? 0, matCode: null };
  } else if (doorType) {
    if (!line.fireRatingCode || !line.doorFinishCode) {
      door = noRate(`No door price: choose a fire rating and door finish for ${typeLabel}`);
    } else {
      const fire = line.fireRatingCode;
      const finish = rates.doorFinishes.find(f => f.code === line.doorFinishCode);
      const rateFor = (finishCode: string) =>
        withFireFallback(rates, fire, fr =>
          rates.doorRates.find(r => r.doorTypeId === doorType.id && r.fireRatingCode === fr && r.finishCode === finishCode));
      const own = rateFor(line.doorFinishCode);
      if (finish?.baseFinishCode) {
        // e.g. SPRAY = PRIMED price + spray uplift (V1 sprayAdd)
        const base = rateFor(finish.baseFinishCode);
        door = own && base
          ? { price: base.price + own.price, matCode: own.matCode }
          : noRate(`No door price for ${typeLabel} / ${fire} / ${line.doorFinishCode}`);
      } else {
        door = own ?? noRate(`No door price for ${typeLabel} / ${fire} / ${line.doorFinishCode}`);
      }
    }
  }

  // Vision panels: price per panel x number of panels
  let vp: Priced = ZERO;
  if (line.vpCount > 0) {
    const fire = line.fireRatingCode;
    const rate = fire ? withFireFallback(rates, fire, fr => rates.vpRates.find(r => r.fireRatingCode === fr)) : undefined;
    vp = rate
      ? { price: rate.price * line.vpCount, matCode: rate.matCode }
      : noRate(`No vision panel price for ${fire ?? 'no fire rating'}`);
  }

  // Frame or lining
  let surround: Priced = ZERO;
  const surroundFinish = line.surround === 'FRAME' ? line.frameFinishCode
    : line.surround === 'LINING' ? line.liningFinishCode : null;
  if (surroundFinish) {
    const what = line.surround === 'FRAME' ? 'frame' : 'lining';
    const table = line.surround === 'FRAME' ? rates.frameRates : rates.liningRates;
    const rate = doorType ? table.find(r => r.doorTypeId === doorType.id && r.finishCode === surroundFinish) : undefined;
    surround = rate ?? noRate(doorType
      ? `No ${what} price for ${typeLabel} / ${surroundFinish}`
      : `A ${what} can't be priced for a manual door; include it in the manual cost`);
  }

  // Architrave: flat price per type
  let architrave: Priced = ZERO;
  if (line.architraveId) {
    architrave = rates.architraves.find(a => a.id === line.architraveId) ?? noRate('Architrave no longer exists');
  }

  // Over panel: by type x fire x panel type x door finish; a missing or zero finish price
  // falls back to the laminate price (V1: op[key] || op.laminate).
  let overPanel: Priced = ZERO;
  if (line.overPanelTypeCode) {
    const fire = line.fireRatingCode;
    const find = (finishCode: string | null): OverPanelRate | undefined =>
      doorType && fire && finishCode
        ? withFireFallback(rates, fire, fr => rates.overPanelRates.find(r =>
            r.doorTypeId === doorType.id && r.fireRatingCode === fr &&
            r.panelTypeCode === line.overPanelTypeCode && r.finishCode === finishCode))
        : undefined;
    const own = find(line.doorFinishCode);
    const rate = own && own.price > 0 ? own : (find('LAMINATE') ?? own);
    overPanel = rate ?? noRate(`No over panel price for ${typeLabel} / ${fire ?? 'no fire rating'} / ${line.overPanelTypeCode}`);
  }

  return {
    snapshot: {
      costDoor: roundPounds(door.price),
      costVp: roundPounds(vp.price),
      costSurround: roundPounds(surround.price),
      costArchitrave: roundPounds(architrave.price),
      costOverPanel: roundPounds(overPanel.price),
      matCodeDoor: door.matCode,
      matCodeVp: vp.matCode,
      matCodeSurround: surround.matCode,
      matCodeArchitrave: architrave.matCode,
      matCodeOverPanel: overPanel.matCode,
    },
    warnings,
  };
}

/**
 * Find a rate for a fire rating; if none, try its base rating (FD30S -> FD30).
 * Fixes V1 bug 14: V1 always stripped the S, so FD30S rows could never be priced.
 */
function withFireFallback<T>(rates: RateBook, fireCode: string, find: (fire: string) => T | undefined): T | undefined {
  const own = find(fireCode);
  if (own !== undefined) return own;
  const base = rates.fireRatings.find(f => f.code === fireCode)?.baseCode;
  return base ? find(base) : undefined;
}

function roundPounds(pounds: number): number {
  return toPounds(toPence(pounds));
}

// ---------------------------------------------------------------------------
// Step 2: totals from the saved snapshot (same rules as db view v_job_door_lines)
// ---------------------------------------------------------------------------

/** V1 lineQty: whole number, at least 1. */
export function lineQty(qty: number): number {
  return Number.isFinite(qty) && qty >= 1 ? Math.floor(qty) : 1;
}

export function lineTotals(
  line: DoorLine, snapshot: DoorSnapshot, markup: number, liningDepthThresholdMm: number | null,
): Omit<PricedDoor, 'snapshot' | 'warnings'> {
  const qty = lineQty(line.qty);
  const hardwarePence = sumQtyTimesCostPence(line.hardware);
  const isLining = line.surround === 'LINING';
  const liningUpliftPence = isLining ? toPence(line.liningUplift ?? 0) : 0;
  const needsLiningUplift = isLining
    && liningDepthThresholdMm !== null
    && line.liningDepthMm !== null
    && line.liningDepthMm > liningDepthThresholdMm
    && line.liningUplift === null;

  const unitPence = toPence(snapshot.costDoor) + toPence(snapshot.costVp) + toPence(snapshot.costSurround)
    + toPence(snapshot.costArchitrave) + toPence(snapshot.costOverPanel)
    + hardwarePence + toPence(line.addedUplift) + liningUpliftPence;
  const linePence = unitPence * qty;
  const hasSellOverride = line.sellOverride !== null;
  const sellPence = hasSellOverride ? toPence(line.sellOverride ?? 0) * qty : applyMarkup(linePence, markup);

  return {
    costHardware: toPounds(hardwarePence),
    liningUpliftApplied: toPounds(liningUpliftPence),
    needsLiningUplift,
    unitCost: toPounds(unitPence),
    lineCost: toPounds(linePence),
    lineSell: toPounds(sellPence),
    hasSellOverride,
  };
}

// ---------------------------------------------------------------------------
// Warnings (V1 getWarnings + linings). Never block saving; the PDF blocks on
// LINING_UPLIFT_MISSING only (spec RAT-05a).
// ---------------------------------------------------------------------------

export function doorWarnings(line: DoorLine, rates: RateBook, needsLiningUplift: boolean): Warning[] {
  const w: Warning[] = [];
  const has = (categoryKey: string) => line.hardware.some(h => h.categoryKey === categoryKey && h.qty > 0);
  const fire = line.fireRatingCode ? rates.fireRatings.find(f => f.code === line.fireRatingCode) : undefined;
  const doorType = line.doorTypeId ? rates.doorTypes.find(t => t.id === line.doorTypeId) : undefined;
  const hasType = line.isManual || !!doorType;

  if (fire?.isFireDoor) {
    if (!has('intumescents')) w.push({ code: 'FIRE_NO_INTUMESCENT', message: 'Fire door missing intumescent seals' });
    if (!has('closers')) w.push({ code: 'FIRE_NO_CLOSER', message: 'Fire door missing closer' });
    if (!has('signage')) w.push({ code: 'FIRE_NO_SIGNAGE', message: 'Fire door missing signage' });
  }
  if (doorType?.needsFlushBolts && !has('flushBolts'))
    w.push({ code: 'NO_FLUSH_BOLTS', message: 'Double/L&H door missing flush bolts' });
  if (!hasType) w.push({ code: 'NO_DOOR_TYPE', message: 'No door type selected' });
  if (!line.doorMark?.trim()) w.push({ code: 'NO_DOOR_MARK', message: 'No door ID entered' });
  if (hasType && !has('hinges')) w.push({ code: 'NO_HINGES', message: 'No hinges selected' });
  if (hasType && !has('levers') && !has('pushPull'))
    w.push({ code: 'NO_HANDLES', message: 'No lever handles or push/pull handles selected' });
  if (needsLiningUplift)
    w.push({ code: 'LINING_UPLIFT_MISSING', message: 'Lining is deeper than standard: enter the lining uplift cost' });
  return w;
}

// ---------------------------------------------------------------------------
// Everything at once: used when a line is added, edited or repriced.
// ---------------------------------------------------------------------------

export function priceDoor(line: DoorLine, rates: RateBook, markup: number): PricedDoor {
  const { snapshot, warnings: rateWarnings } = priceSnapshot(line, rates);
  const totals = lineTotals(line, snapshot, markup, rates.liningDepthThresholdMm);
  return {
    snapshot,
    ...totals,
    warnings: [...doorWarnings(line, rates, totals.needsLiningUplift), ...rateWarnings],
  };
}

/** Door screens (structure only, spec §7a): manual unit cost, same markup and override rules. */
export function screenTotals(s: { qty: number; unitCost: number; sellOverride: number | null }, markup: number) {
  const qty = lineQty(s.qty);
  const linePence = toPence(s.unitCost) * qty;
  const sellPence = s.sellOverride !== null ? toPence(s.sellOverride) * qty : applyMarkup(linePence, markup);
  return { lineCost: toPounds(linePence), lineSell: toPounds(sellPence) };
}

/** Job totals from priced lines (same as db view v_job_totals). */
export function jobTotals(lines: ReadonlyArray<{ lineCost: number; lineSell: number }>) {
  let costPence = 0;
  let sellPence = 0;
  for (const l of lines) { costPence += toPence(l.lineCost); sellPence += toPence(l.lineSell); }
  return {
    totalCost: toPounds(costPence),
    totalSell: toPounds(sellPence),
    marginPct: sellPence > 0 ? Math.round((1 - costPence / sellPence) * 10_000) / 10_000 : null,
  };
}
