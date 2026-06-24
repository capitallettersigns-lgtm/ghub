import { chromium } from 'playwright';
import path from 'node:path';
import { loadConfig } from './config.js';
import { formatDate } from './date-format.js';

/**
 * One-off helper: open the logged-in page and print candidate "day header" elements,
 * so you can choose a reliable value for capture.dateHeaderSelector (and confirm
 * today.dateFormat matches what the page actually shows).
 *
 *   npm run build && npm run find-today
 */
interface Candidate {
  selector: string;
  matchesToday: boolean;
  text: string;
}

async function main(): Promise<void> {
  const cfg = await loadConfig();
  const profileDir = path.resolve(process.cwd(), cfg.profileDir);

  const context = await chromium.launchPersistentContext(profileDir, {
    headless: cfg.headless ?? false,
    viewport: { width: 1280, height: 1600 },
  });

  try {
    const page = context.pages()[0] ?? (await context.newPage());
    await page.goto(cfg.url, { waitUntil: 'networkidle', timeout: cfg.navTimeoutMs ?? 60000 });

    const todayStr = formatDate(new Date(), cfg.today.dateFormat, cfg.today.locale ?? 'en-US');
    console.log(`\nToday's date string (from config today.dateFormat): "${todayStr}"`);
    console.log('If that does NOT match what you see on the page, fix today.dateFormat in config.json.\n');

    const candidates = await page.evaluate<Candidate[], string>((todayStr) => {
      const norm = (s: string | null) => (s ?? '').replace(/\s+/g, ' ').trim();
      const dateLike =
        /\b(\d{1,2}[\/.\-]\d{1,2}|\d{4}|January|February|March|April|May|June|July|August|September|October|November|December|Mon|Tue|Wed|Thu|Fri|Sat|Sun)/i;

      const els = Array.from(
        document.querySelectorAll(
          'h1,h2,h3,h4,h5,h6,time,[class*="date" i],[class*="day" i],[class*="header" i]',
        ),
      );

      const seen = new Set<string>();
      const out: Candidate[] = [];

      for (const el of els) {
        const full = norm(el.textContent);
        if (!full) continue;

        const text = full.slice(0, 80);
        const matchesToday = full.toLowerCase().includes(todayStr.toLowerCase());
        if (!matchesToday && !dateLike.test(text)) continue;

        const tag = el.tagName.toLowerCase();
        const cls = (el.getAttribute('class') || '')
          .trim()
          .split(/\s+/)
          .filter(Boolean)
          .slice(0, 2)
          .map((c) => '.' + CSS.escape(c))
          .join('');
        const selector = tag + cls;

        const key = selector + '|' + text;
        if (seen.has(key)) continue;
        seen.add(key);

        out.push({ selector, matchesToday, text });
      }
      return out;
    }, todayStr);

    if (candidates.length === 0) {
      console.log('No obvious date-header elements found. Open the page yourself and inspect the day header.');
    } else {
      console.log('Candidate date-header elements (use one as capture.dateHeaderSelector):\n');
      for (const c of candidates) {
        console.log(`${c.matchesToday ? '★ ' : '  '}[${c.selector}]  "${c.text}"`);
      }
      console.log("\n★ = currently contains today's date string. Pick a selector that matches every day's header.");
    }
  } finally {
    await context.close();
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
