/**
 * Minimal date formatter, just enough to reproduce how a page renders its day header
 * so we can find "today" by text match.
 *
 * Supported tokens (longest-first so they don't collide):
 *   YYYY  4-digit year         2026
 *   YY    2-digit year         26
 *   MMMM  full month name      June
 *   MMM   short month name     Jun
 *   MM    2-digit month        06
 *   M     month                6
 *   DD    2-digit day          07
 *   D     day                  7
 *   dddd  full weekday name    Wednesday
 *   ddd   short weekday name   Wed
 *
 * Any other characters in the pattern are kept literally. Note: literal capital
 * M/D letters in the pattern will be treated as tokens — keep patterns to the
 * date itself (e.g. "dddd, MMMM D"), not prose.
 */
export function formatDate(date: Date, pattern: string, locale = 'en-US'): string {
  const pad2 = (n: number) => String(n).padStart(2, '0');

  const tokens: Record<string, string> = {
    YYYY: String(date.getFullYear()),
    YY: pad2(date.getFullYear() % 100),
    MMMM: new Intl.DateTimeFormat(locale, { month: 'long' }).format(date),
    MMM: new Intl.DateTimeFormat(locale, { month: 'short' }).format(date),
    MM: pad2(date.getMonth() + 1),
    M: String(date.getMonth() + 1),
    DD: pad2(date.getDate()),
    D: String(date.getDate()),
    dddd: new Intl.DateTimeFormat(locale, { weekday: 'long' }).format(date),
    ddd: new Intl.DateTimeFormat(locale, { weekday: 'short' }).format(date),
  };

  // Order matters: try longer tokens before their prefixes.
  return pattern.replace(/YYYY|YY|MMMM|MMM|MM|M|DD|D|dddd|ddd/g, (m) => tokens[m] ?? m);
}
