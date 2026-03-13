/**
 * Cron expression utilities — 1:1 port of core/cron_utils.dart
 */

export type ScheduleFrequency =
  | 'everyNMinutes'
  | 'everyNHours'
  | 'dailyAt'
  | 'weeklyOn'
  | 'monthlyOn'
  | 'inNMinutes';

export const frequencyLabels: Record<ScheduleFrequency, string> = {
  everyNMinutes: 'Every N minutes',
  everyNHours: 'Every N hours',
  dailyAt: 'Daily at',
  weeklyOn: 'Weekly on',
  monthlyOn: 'Monthly on',
  inNMinutes: 'In N minutes (one-shot)',
};

export const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/**
 * Build a cron expression from simple-mode parameters.
 */
export function buildCronExpression(params: {
  frequency: ScheduleFrequency;
  interval: number;
  hour: number;
  minute: number;
  selectedDays: boolean[];
  dayOfMonth: number;
}): string {
  const { frequency, interval, hour, minute, selectedDays, dayOfMonth } = params;

  switch (frequency) {
    case 'inNMinutes':
      return `+${interval}m`;
    case 'everyNMinutes':
      return `*/${interval} * * * *`;
    case 'everyNHours':
      return `0 */${interval} * * *`;
    case 'dailyAt':
      return `${minute} ${hour} * * *`;
    case 'weeklyOn': {
      const cronDays = selectedDays
        .map((sel, i) => (sel ? ((i + 1) % 7) : -1))
        .filter((d) => d >= 0);
      if (cronDays.length === 0) return `${minute} ${hour} * * *`;
      return `${minute} ${hour} * * ${cronDays.join(',')}`;
    }
    case 'monthlyOn':
      return `${minute} ${hour} ${dayOfMonth} * *`;
    default:
      return `${minute} ${hour} * * *`;
  }
}

export interface SimpleSchedule {
  frequency: ScheduleFrequency;
  interval: number;
  hour: number;
  minute: number;
  selectedDays: boolean[];
  dayOfMonth: number;
}

/**
 * Try to reverse-parse a cron expression into SimpleSchedule fields.
 */
export function tryParseSimple(expr: string): SimpleSchedule | null {
  const trimmed = expr.trim();

  // One-shot: +Nm
  const oneShotMatch = trimmed.match(/^\+(\d+)m$/);
  if (oneShotMatch) {
    return {
      frequency: 'inNMinutes',
      interval: parseInt(oneShotMatch[1]),
      hour: 0,
      minute: 0,
      selectedDays: Array(7).fill(false),
      dayOfMonth: 1,
    };
  }

  const parts = trimmed.split(/\s+/);
  if (parts.length !== 5) return null;

  const [minField, hourField, domField, , dowField] = parts;

  // Every N minutes: */N * * * *
  const everyMinMatch = minField.match(/^\*\/(\d+)$/);
  if (everyMinMatch && hourField === '*' && domField === '*' && dowField === '*') {
    return {
      frequency: 'everyNMinutes',
      interval: parseInt(everyMinMatch[1]),
      hour: 0,
      minute: 0,
      selectedDays: Array(7).fill(false),
      dayOfMonth: 1,
    };
  }

  // Every N hours: 0 */N * * *
  const everyHourMatch = hourField.match(/^\*\/(\d+)$/);
  if (minField === '0' && everyHourMatch && domField === '*' && dowField === '*') {
    return {
      frequency: 'everyNHours',
      interval: parseInt(everyHourMatch[1]),
      hour: 0,
      minute: 0,
      selectedDays: Array(7).fill(false),
      dayOfMonth: 1,
    };
  }

  const min = parseInt(minField);
  const hour = parseInt(hourField);
  if (isNaN(min) || isNaN(hour)) return null;

  // Weekly: M H * * d1,d2,...
  if (domField === '*' && dowField !== '*') {
    const cronDays = dowField.split(',').map(Number);
    const selectedDays = Array(7).fill(false);
    for (const d of cronDays) {
      const idx = d === 0 ? 6 : d - 1; // cron 0=Sun -> idx 6
      if (idx >= 0 && idx < 7) selectedDays[idx] = true;
    }
    return { frequency: 'weeklyOn', interval: 1, hour, minute: min, selectedDays, dayOfMonth: 1 };
  }

  // Monthly: M H D * *
  if (dowField === '*' && domField !== '*') {
    const dom = parseInt(domField);
    if (!isNaN(dom)) {
      return {
        frequency: 'monthlyOn',
        interval: 1,
        hour,
        minute: min,
        selectedDays: Array(7).fill(false),
        dayOfMonth: dom,
      };
    }
  }

  // Daily: M H * * *
  if (domField === '*' && dowField === '*') {
    return {
      frequency: 'dailyAt',
      interval: 1,
      hour,
      minute: min,
      selectedDays: Array(7).fill(false),
      dayOfMonth: 1,
    };
  }

  return null;
}

/**
 * Convert a cron expression to a human-readable description.
 */
export function describeCron(expr: string): string {
  const trimmed = expr.trim();

  // One-shot
  const oneShotMatch = trimmed.match(/^\+(\d+)m$/);
  if (oneShotMatch) return `in ${oneShotMatch[1]} minutes (one-shot)`;

  // ISO timestamp
  if (trimmed.includes('T') && trimmed.includes('-')) {
    try {
      const d = new Date(trimmed);
      return `once at ${d.toLocaleString()}`;
    } catch { /* fall through */ }
  }

  const parts = trimmed.split(/\s+/);
  // 6-field (with seconds): skip first field
  const fields = parts.length === 6 ? parts.slice(1) : parts;
  if (fields.length !== 5) return trimmed;

  const [minField, hourField, domField, monField, dowField] = fields;

  // Every N minutes
  const everyMinMatch = minField.match(/^\*\/(\d+)$/);
  if (everyMinMatch && hourField === '*') {
    let desc = `every ${everyMinMatch[1]} minutes`;
    desc += _appendDomMonthDow(domField, monField, dowField);
    return desc;
  }

  // Every N hours
  const everyHourMatch = hourField.match(/^\*\/(\d+)$/);
  if (everyHourMatch) {
    let desc = `every ${everyHourMatch[1]} hours`;
    desc += _appendDomMonthDow(domField, monField, dowField);
    return desc;
  }

  const min = parseInt(minField);
  const hour = parseInt(hourField);
  if (isNaN(min) || isNaN(hour)) return trimmed;

  const timeStr = `${String(hour).padStart(2, '0')}:${String(min).padStart(2, '0')}`;
  let desc = `at ${timeStr}`;

  // Day of week
  if (dowField !== '*') {
    const days = dowField
      .split(',')
      .map((d) => _dowName(parseInt(d)))
      .filter(Boolean);
    if (days.length > 0) desc += `, on ${days.join(', ')}`;
  } else if (domField === '*') {
    desc += ', every day';
  }

  // Day of month
  if (domField !== '*') {
    const dom = parseInt(domField);
    if (!isNaN(dom)) desc += `, on the ${_ordinal(dom)}`;
  }

  // Month
  if (monField !== '*') {
    const mons = monField.split(',').map((m) => _monthName(parseInt(m))).filter(Boolean);
    if (mons.length > 0) desc += ` of ${mons.join(', ')}`;
  }

  return desc;
}

/**
 * Basic validation of a cron expression.
 */
export function validateCron(expr: string): string | null {
  const trimmed = expr.trim();
  if (!trimmed) return 'Expression is empty';

  // One-shot
  if (/^\+\d+m$/.test(trimmed)) return null;

  const parts = trimmed.split(/\s+/);
  if (parts.length < 5 || parts.length > 6) {
    return `Expected 5 or 6 fields, got ${parts.length}`;
  }

  return null;
}

/* ------------------------------------------------------------------ */
/*  Helpers                                                            */
/* ------------------------------------------------------------------ */

function _ordinal(n: number): string {
  if (n % 100 >= 11 && n % 100 <= 13) return `${n}th`;
  switch (n % 10) {
    case 1: return `${n}st`;
    case 2: return `${n}nd`;
    case 3: return `${n}rd`;
    default: return `${n}th`;
  }
}

function _monthName(m: number): string {
  const names = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return names[m] ?? '';
}

function _dowName(d: number): string {
  const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  return names[d] ?? '';
}

function _appendDomMonthDow(domField: string, monField: string, dowField: string): string {
  let s = '';
  if (dowField !== '*') {
    const days = dowField.split(',').map((d) => _dowName(parseInt(d))).filter(Boolean);
    if (days.length > 0) s += `, on ${days.join(', ')}`;
  }
  if (domField !== '*') {
    const dom = parseInt(domField);
    if (!isNaN(dom)) s += `, on the ${_ordinal(dom)}`;
  }
  if (monField !== '*') {
    const mons = monField.split(',').map((m) => _monthName(parseInt(m))).filter(Boolean);
    if (mons.length > 0) s += ` of ${mons.join(', ')}`;
  }
  return s;
}
