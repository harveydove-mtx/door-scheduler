// Money helpers. All arithmetic is done in whole pence (integers) so totals are exact and
// match Postgres numeric(12,2). Rounding is half away from zero, like Postgres round().

/** Pounds (e.g. 461.84) -> pence (46184). */
export function toPence(pounds: number): number {
  return roundHalfAwayFromZero(pounds * 100);
}

/** Pence -> pounds, for display and for storing in numeric(12,2) columns. */
export function toPounds(pence: number): number {
  return pence / 100;
}

/**
 * Sum of qty x unit cost (pounds) over hardware lines, IN PENCE, rounded ONCE at the end, as the
 * database does (sum(qty * unit_cost)::numeric(12,2)). qty may have 2dp (e.g. 1.5).
 */
export function sumQtyTimesCostPence(items: ReadonlyArray<{ qty: number; unitCost: number }>): number {
  let hundredthsTimesPence = 0;
  for (const i of items) hundredthsTimesPence += roundHalfAwayFromZero(i.qty * 100) * toPence(i.unitCost);
  return roundDiv(hundredthsTimesPence, 100);
}

/**
 * Sell from cost with markup on cost: round(cost x (1 + markup), 2), as V1 calcSellPrice.
 * markup is a fraction (0.22 = 22%) held to 4dp like jobs.markup_pct numeric(6,4).
 */
export function applyMarkup(costPence: number, markup: number): number {
  const markupBp = roundHalfAwayFromZero(markup * 10_000);
  return roundDiv(costPence * (10_000 + markupBp), 10_000);
}

/** Integer division of two integers, rounded half away from zero. */
function roundDiv(numerator: number, denominator: number): number {
  const sign = Math.sign(numerator) * Math.sign(denominator);
  const n = Math.abs(numerator);
  const d = Math.abs(denominator);
  return sign * Math.floor((2 * n + d) / (2 * d));
}

function roundHalfAwayFromZero(x: number): number {
  // Nudge by a tiny epsilon so 1.005 * 100 = 100.49999999999999 rounds to 101 like numeric.
  const r = Math.round(Math.abs(x) * (1 + Number.EPSILON * 4));
  return x < 0 ? -r : r;
}
