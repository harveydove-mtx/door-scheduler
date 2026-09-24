import { describe, expect, it } from 'vitest';
import seed from './fixtures/seedRateBook.json';
import { applyMarkup, sumQtyTimesCostPence, toPence } from './money';
import { jobTotals, lineQty, priceDoor, priceSnapshot, screenTotals } from './pricing';
import type { DoorHardware, DoorLine, RateBook } from './types';
import { loadV1 } from './v1Reference.test-helper';

const rates = seed as RateBook;
const MARKUP = 0.22;
const clone = (): RateBook => structuredClone(rates);

// Hardware snapshot costs as seeded (db/seed.sql)
const HW = {
  hinge: { categoryKey: 'hinges', unitCost: 3.48 },          // ZHSS243RS3
  closer: { categoryKey: 'closers', unitCost: 31.42 },       // TS.9205
  sign: { categoryKey: 'signage', unitCost: 0.60 },          // FDKS SS
  lever: { categoryKey: 'levers', unitCost: 3.50 },          // ZCS2030SS
  lock: { categoryKey: 'lockcases', unitCost: 5.50 },        // ZDL7260RSS
  intu: { categoryKey: 'intumescents', unitCost: 0 },        // LAS1212
  bolt: { categoryKey: 'flushBolts', unitCost: 7.32 },       // ZAS03RS
};
const hw = (h: { categoryKey: string; unitCost: number }, qty = 1): DoorHardware => ({ ...h, qty });

function door(over: Partial<DoorLine> = {}): DoorLine {
  return {
    qty: 1, doorMark: 'D', isManual: false, manualCost: null, doorTypeId: 'SASL', fireRatingCode: 'NFR',
    vpCount: 0, doorFinishCode: 'PRIMED', surround: 'FRAME', frameFinishCode: null, liningFinishCode: null,
    liningDepthMm: null, liningUplift: null, architraveId: null, overPanelTypeCode: null, addedUplift: 0,
    sellOverride: null, hardware: [], ...over,
  };
}

// The three sample doors in db/sample_data.sql. The SQL tests check the database view gives
// these totals; here the engine must produce the same snapshot AND the same totals.
const D01 = door({
  qty: 3, doorMark: 'D01', fireRatingCode: 'FD30S', vpCount: 1, doorFinishCode: 'LAMINATE',
  frameFinishCode: 'HARDWOOD/OAK', architraveId: 'BESPOKE', addedUplift: 10,
  hardware: [hw(HW.hinge, 2), hw(HW.closer), hw(HW.sign, 2), hw(HW.lever), hw(HW.lock), hw(HW.intu)],
});
const D02 = door({
  doorMark: 'D02', doorTypeId: 'SADL', fireRatingCode: 'NFR', doorFinishCode: 'SPRAY',
  surround: 'LINING', liningFinishCode: 'PRIMED', liningDepthMm: 180, hardware: [hw(HW.bolt, 2)],
});
const D03 = door({ qty: 2, doorMark: 'D03', isManual: true, doorTypeId: null, manualCost: 250, sellOverride: 400 });

describe('V1 parity: sample job (same figures as db/tests/04_totals.sql)', () => {
  it('D01: SASL FD30S laminate, VP, oak frame, bespoke architrave, x3', () => {
    const p = priceDoor(D01, rates, MARKUP);
    expect(p.snapshot).toMatchObject({ costDoor: 461.84, costVp: 127.01, costSurround: 226.2, costArchitrave: 40, costOverPanel: 0 });
    expect(p.costHardware).toBe(48.58);
    expect(p.unitCost).toBe(913.63);
    expect(p.lineCost).toBe(2740.89);
    expect(p.lineSell).toBe(3343.89);
  });

  it('D02: SADL spray = primed + spray uplift; deep lining flagged', () => {
    const p = priceDoor(D02, rates, MARKUP);
    expect(p.snapshot.costDoor).toBe(809.31);
    expect(p.unitCost).toBe(823.95);
    expect(p.lineSell).toBe(1005.22);
    expect(p.needsLiningUplift).toBe(true);
    expect(p.warnings.map(w => w.code)).toContain('LINING_UPLIFT_MISSING');
    expect(p.warnings.map(w => w.code)).toContain('NO_RATE'); // no lining prices seeded yet
  });

  it('D03: manual door, sell override is per unit x qty', () => {
    const p = priceDoor(D03, rates, MARKUP);
    expect(p.lineCost).toBe(500);
    expect(p.lineSell).toBe(800);
    expect(p.hasSellOverride).toBe(true);
  });

  it('job total with the door screen = 4414.84 cost / 5576.11 sell', () => {
    const lines = [D01, D02, D03].map(d => priceDoor(d, rates, MARKUP));
    const t = jobTotals([...lines, screenTotals({ qty: 1, unitCost: 350, sellOverride: null }, MARKUP)]);
    expect(t.totalCost).toBe(4414.84);
    expect(t.totalSell).toBe(5576.11);
  });
});

describe('V1 parity: every rate combination against the real V1 code in index.html', () => {
  const v1 = loadV1();
  const archMap: Record<string, string | null> = { NONE: null, PRIMED: 'PRIMED', SPRAY: 'SPRAY', BESPOKE: 'BESPOKE', TBC: 'TBC' };
  const cases = [...new Set((v1.rates.doors as { desc: string }[]).map(d => d.desc))];

  it('door + VP + frame + architrave + over panel match V1 for all combinations', () => {
    let checked = 0;
    for (const desc of cases) {
      const formCode = (v1.rates.doors as { desc: string; formCode: string }[]).find(d => d.desc === desc)!.formCode;
      for (const fire of ['NFR', 'FD30', 'FD30S', 'FD60', 'FD60S'])
        for (const finish of ['PRIMED', 'LAMINATE', 'VENEER', 'SPRAY'])
          for (const frame of ['PRIMED', 'HARDWOOD/OAK', 'HARDWOOD SPRAY', 'SPRAY'])
            for (const arch of Object.keys(archMap))
              for (const vp of [0, 1, 3])
                for (const op of ['NONE', 'SOLID', 'GLAZED']) {
                  const v1Door = { doorType: desc, fireRating: fire, doorFinish: finish, frameFinish: frame, archFinish: arch, vp, overPanel: op };
                  const v1Total = v1.calcDoorCost(v1Door) + v1.calcFrameCost(v1Door) + v1.calcArchCost(v1Door)
                    + v1.calcVPCost(v1Door) + v1.calcOverPanelCost(v1Door);
                  const { snapshot: s } = priceSnapshot(door({
                    doorTypeId: formCode, fireRatingCode: fire, doorFinishCode: finish, frameFinishCode: frame,
                    architraveId: archMap[arch] ?? null, vpCount: vp, overPanelTypeCode: op === 'NONE' ? null : op,
                  }), rates);
                  const v2 = toPence(s.costDoor) + toPence(s.costSurround) + toPence(s.costArchitrave) + toPence(s.costVp) + toPence(s.costOverPanel);
                  expect(v2, `${formCode} ${fire} ${finish} frame ${frame} arch ${arch} vp ${vp} op ${op}`).toBe(toPence(v1Total));
                  checked++;
                }
    }
    expect(checked).toBe(3 * 5 * 4 * 4 * 5 * 3 * 3);
  });

  it('V1 sell rounding (round line cost x (1 + markup) to the penny) matches', () => {
    for (const cost of [0.01, 0.25, 1.23, 99.99, 913.63 * 3, 12345.67]) {
      for (const markup of [0, 0.1, 0.22, 0.3333, 1]) {
        const v1Sell = Math.round(cost * (1 + markup) * 100) / 100;
        expect(applyMarkup(toPence(cost), markup) / 100, `${cost} @ ${markup}`).toBeCloseTo(v1Sell, 2);
      }
    }
  });
});

describe('V2 rules and V1 bug fixes', () => {
  it('RAT-02 / V1 bug 14: an FD30S row of its own is used when it exists', () => {
    const r = clone();
    r.doorRates.push({ doorTypeId: 'SASL', fireRatingCode: 'FD30S', finishCode: 'LAMINATE', price: 500, matCode: null });
    expect(priceSnapshot(door({ fireRatingCode: 'FD30S', doorFinishCode: 'LAMINATE' }), r).snapshot.costDoor).toBe(500);
    // ...and FD30S still falls back to FD30 when it doesn't
    expect(priceSnapshot(door({ fireRatingCode: 'FD30S', doorFinishCode: 'LAMINATE' }), rates).snapshot.costDoor).toBe(461.84);
  });

  it('S ratings fall back for vision panels and over panels too', () => {
    const s = priceSnapshot(door({ fireRatingCode: 'FD30S', vpCount: 2, overPanelTypeCode: 'GLAZED' }), rates).snapshot;
    expect(s.costVp).toBe(254.02);
    expect(s.costOverPanel).toBe(211.65); // laminate fallback for a primed door
  });

  it('V1 bug 1: no hardware costs nothing ("None" is not a £1 product)', () => {
    const p = priceDoor(door({ hardware: [] }), rates, MARKUP);
    expect(p.costHardware).toBe(0);
    expect(p.unitCost).toBe(387.43);
  });

  it('RAT-05a: linings up to 150mm are standard, 151mm asks for uplift', () => {
    const lining = (depth: number, uplift: number | null = null) =>
      priceDoor(door({ surround: 'LINING', liningFinishCode: 'PRIMED', liningDepthMm: depth, liningUplift: uplift }), rates, MARKUP);
    expect(rates.liningDepthThresholdMm).toBe(150);
    expect(lining(150).needsLiningUplift).toBe(false);
    expect(lining(151).needsLiningUplift).toBe(true);
    expect(lining(151).warnings.map(w => w.code)).toContain('LINING_UPLIFT_MISSING');
    const withUplift = lining(200, 45);
    expect(withUplift.needsLiningUplift).toBe(false);
    expect(withUplift.liningUpliftApplied).toBe(45);
    expect(withUplift.unitCost).toBe(387.43 + 45);
  });

  it('lining uplift is ignored once the door has a frame instead', () => {
    const p = priceDoor(door({ surround: 'FRAME', liningDepthMm: 200, liningUplift: 45 }), rates, MARKUP);
    expect(p.liningUpliftApplied).toBe(0);
    expect(p.needsLiningUplift).toBe(false);
  });

  it('lining is priced from lining rates once they exist', () => {
    const r = clone();
    r.liningRates.push({ doorTypeId: 'SASL', finishCode: 'PRIMED', price: 120.5, matCode: 'MAT-LIN-1' });
    const p = priceDoor(door({ surround: 'LINING', liningFinishCode: 'PRIMED', liningDepthMm: 100 }), r, MARKUP);
    expect(p.snapshot.costSurround).toBe(120.5);
    expect(p.snapshot.matCodeSurround).toBe('MAT-LIN-1');
    expect(p.warnings.map(w => w.code)).not.toContain('NO_RATE');
  });

  it('a missing rate prices at 0 with a NO_RATE warning (never silently)', () => {
    const p = priceDoor(door({ fireRatingCode: 'FD60', overPanelTypeCode: 'SOLID' }), rates, MARKUP);
    expect(p.snapshot.costOverPanel).toBe(0);
    expect(p.warnings).toContainEqual({ code: 'NO_RATE', message: 'No over panel price for SASL / FD60 / SOLID' });
  });

  it('snapshot carries MAT codes; spray uses the spray row\'s code', () => {
    const r = clone();
    for (const x of r.doorRates) if (x.doorTypeId === 'SASL' && x.fireRatingCode === 'FD30') x.matCode = `MAT-SASL-30-${x.finishCode}`;
    r.vpRates.find(x => x.fireRatingCode === 'FD30')!.matCode = 'MAT-VP-30';
    r.frameRates.find(x => x.doorTypeId === 'SASL' && x.finishCode === 'SPRAY')!.matCode = 'MAT-FR-SASL-SPRAY';
    const s = priceSnapshot(door({ fireRatingCode: 'FD30', doorFinishCode: 'SPRAY', vpCount: 1, frameFinishCode: 'SPRAY' }), r).snapshot;
    expect(s).toMatchObject({ matCodeDoor: 'MAT-SASL-30-SPRAY', matCodeVp: 'MAT-VP-30', matCodeSurround: 'MAT-FR-SASL-SPRAY',
                             matCodeArchitrave: null, matCodeOverPanel: null });
    expect(s.costDoor).toBe(387.43 + 187.59);
  });

  it('manual door: its own cost, no door type warning, frame cannot be priced', () => {
    const p = priceDoor(door({ isManual: true, doorTypeId: null, manualCost: 300, frameFinishCode: 'SPRAY' }), rates, MARKUP);
    expect(p.snapshot.costDoor).toBe(300);
    expect(p.snapshot.costSurround).toBe(0);
    expect(p.warnings.map(w => w.code)).not.toContain('NO_DOOR_TYPE');
    expect(p.warnings.map(w => w.message)).toContain("A frame can't be priced for a manual door; include it in the manual cost");
  });

  it('quantity: whole numbers of at least 1, as V1 lineQty', () => {
    expect([lineQty(3), lineQty(2.9), lineQty(0), lineQty(-2), lineQty(Number.NaN)]).toEqual([3, 2, 1, 1, 1]);
  });

  it('hardware: qty x unit cost, fractional qty rounded once like the database', () => {
    expect(sumQtyTimesCostPence([{ qty: 1.5, unitCost: 0.33 }, { qty: 1.5, unitCost: 0.33 }])).toBe(99); // 0.99, not 0.50 + 0.50
  });
});

describe('warnings (V1 getWarnings rules)', () => {
  const codes = (d: DoorLine) => priceDoor(d, rates, MARKUP).warnings.map(w => w.code);

  it('fire door without intumescent, closer or signage', () => {
    expect(codes(door({ fireRatingCode: 'FD30', hardware: [hw(HW.hinge), hw(HW.lever)] })))
      .toEqual(['FIRE_NO_INTUMESCENT', 'FIRE_NO_CLOSER', 'FIRE_NO_SIGNAGE']);
  });

  it('a fully specified fire door has no warnings', () => {
    expect(codes(D01)).toEqual([]);
  });

  it('NFR door needs no fire hardware', () => {
    expect(codes(door({ hardware: [hw(HW.hinge), hw(HW.lever)] }))).toEqual([]);
  });

  it('double and leaf-and-half doors need flush bolts', () => {
    expect(codes(door({ doorTypeId: 'SADL', hardware: [hw(HW.hinge), hw(HW.lever)] }))).toEqual(['NO_FLUSH_BOLTS']);
    expect(codes(door({ doorTypeId: 'SALH', hardware: [hw(HW.hinge), hw(HW.lever), hw(HW.bolt)] }))).toEqual([]);
  });

  it('no type, no mark, no hinges, no handles', () => {
    expect(codes(door({ doorTypeId: null, doorMark: '  ' }))).toEqual(['NO_DOOR_TYPE', 'NO_DOOR_MARK']);
    expect(codes(door())).toEqual(['NO_HINGES', 'NO_HANDLES']);
    expect(codes(door({ hardware: [hw(HW.hinge), { categoryKey: 'pushPull', qty: 1, unitCost: 7 }] }))).toEqual([]);
  });
});
