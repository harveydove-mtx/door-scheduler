// Domain types for the pricing engine. Shapes mirror the V2 database rows (db/migrations)
// in camelCase, so the same engine works with rows loaded from Data Connect later.
// Money is in pounds (numeric(12,2)); the engine converts to pence internally.

export type Surround = 'NONE' | 'FRAME' | 'LINING';

export interface FireRating { code: string; baseCode: string | null; isFireDoor: boolean }
export interface DoorFinish { code: string; baseFinishCode: string | null }
export interface DoorType { id: string; formCode: string; description: string; needsFlushBolts: boolean }

export interface DoorRate { doorTypeId: string; fireRatingCode: string; finishCode: string; price: number; matCode: string | null }
export interface VpRate { fireRatingCode: string; price: number; matCode: string | null }
export interface SurroundRate { doorTypeId: string; finishCode: string; price: number; matCode: string | null }
export interface Architrave { id: string; price: number; matCode: string | null }
export interface OverPanelRate {
  doorTypeId: string; fireRatingCode: string; panelTypeCode: string; finishCode: string;
  price: number; matCode: string | null;
}

/** Everything needed to price a door, i.e. the current rates. */
export interface RateBook {
  fireRatings: FireRating[];
  doorFinishes: DoorFinish[];
  doorTypes: DoorType[];
  doorRates: DoorRate[];
  vpRates: VpRate[];
  frameRates: SurroundRate[];
  liningRates: SurroundRate[];
  architraves: Architrave[];
  overPanelRates: OverPanelRate[];
  /** Linings deeper than this need an uplift (settings.lining_depth_threshold_mm). null = off. */
  liningDepthThresholdMm: number | null;
}

/** Hardware on a door (job_door_items): unit cost is already the saved snapshot. */
export interface DoorHardware { categoryKey: string; qty: number; unitCost: number }

/** A door line as edited in the schedule (job_doors, spec fields only). */
export interface DoorLine {
  qty: number;
  doorMark: string | null;
  isManual: boolean;
  manualCost: number | null;
  doorTypeId: string | null;
  fireRatingCode: string | null;
  vpCount: number;
  doorFinishCode: string | null;
  surround: Surround;
  frameFinishCode: string | null;
  liningFinishCode: string | null;
  liningDepthMm: number | null;
  liningUplift: number | null;
  architraveId: string | null;
  overPanelTypeCode: string | null;
  addedUplift: number;
  /** Per-unit sell price typed by the user; null = use markup. */
  sellOverride: number | null;
  hardware: DoorHardware[];
}

/** The snapshot stored on job_doors when a line is priced (spec JOB-06). */
export interface DoorSnapshot {
  costDoor: number;
  costVp: number;
  costSurround: number;
  costArchitrave: number;
  costOverPanel: number;
  matCodeDoor: string | null;
  matCodeVp: string | null;
  matCodeSurround: string | null;
  matCodeArchitrave: string | null;
  matCodeOverPanel: string | null;
}

export type WarningCode =
  | 'FIRE_NO_INTUMESCENT' | 'FIRE_NO_CLOSER' | 'FIRE_NO_SIGNAGE' | 'NO_FLUSH_BOLTS'
  | 'NO_DOOR_TYPE' | 'NO_DOOR_MARK' | 'NO_HINGES' | 'NO_HANDLES'
  | 'LINING_UPLIFT_MISSING' | 'NO_RATE';

export interface Warning { code: WarningCode; message: string }

export interface PricedDoor {
  snapshot: DoorSnapshot;
  costHardware: number;
  liningUpliftApplied: number;
  needsLiningUplift: boolean;
  unitCost: number;
  lineCost: number;
  lineSell: number;
  hasSellOverride: boolean;
  warnings: Warning[];
}
