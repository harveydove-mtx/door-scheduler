// Loads the ACTUAL V1 pricing code and default rates out of the repo's live index.html, so
// parity tests compare V2 against V1 itself rather than a copy that could drift.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const V1_PATH = fileURLToPath(new URL('../../../index.html', import.meta.url));

export interface V1Door {
  doorType: string; fireRating: string; doorFinish: string; frameFinish: string;
  archFinish: string; vp: number; overPanel: string; manualCost?: number;
}
export interface V1 {
  rates: any;
  calcDoorCost(d: V1Door): number;
  calcFrameCost(d: V1Door): number;
  calcArchCost(d: V1Door): number;
  calcVPCost(d: V1Door): number;
  calcOverPanelCost(d: V1Door): number;
}

function between(src: string, start: string, end: string): string {
  const i = src.indexOf(start);
  const j = src.indexOf(end, i);
  if (i < 0 || j < 0) throw new Error(`V1 source changed: could not find ${start}`);
  return src.slice(i, j);
}

export function loadV1(): V1 {
  const src = readFileSync(V1_PATH, 'utf8');
  const rates = between(src, 'const DEFAULT_RATES = {', '\nlet HW_CATEGORIES');
  const finishKeys = between(src, 'const FRAME_FINISH_KEY_MAP', '\n', ) + '\n' + between(src, 'function frameFinishKey', '\n');
  const calc = between(src, 'function getBaseFireRating', 'function calcHardwareCost');
  const body = `${rates}\n${finishKeys}\nconst state = { rates: DEFAULT_RATES };\n${calc}\n` +
    'return { rates: DEFAULT_RATES, calcDoorCost, calcFrameCost, calcArchCost, calcVPCost, calcOverPanelCost };';
  return new Function(body)() as V1;
}
