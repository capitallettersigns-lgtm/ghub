import { chromium, type Page } from 'playwright';
import { PDFDocument } from 'pdf-lib';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { loadConfig, type Config } from './config.js';
import { formatDate } from './date-format.js';

/** Result returned from the in-page search for today's section. */
interface FoundResult {
  ok: boolean;
  kind?: 'element' | 'clip';
  rect?: { x: number; y: number; width: number; height: number };
}

function todayStamp(d = new Date()): string {
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

async function ensureDir(dir: string): Promise<void> {
  await fs.mkdir(dir, { recursive: true });
}

/** Wrap a PNG screenshot into a single-page PDF, scaled to a sensible page width. */
async function pngToPdf(png: Uint8Array, outPath: string): Promise<void> {
  const pdf = await PDFDocument.create();
  const img = await pdf.embedPng(png);

  // Scale down so the page width is at most US-Letter width (612pt); keep aspect ratio.
  const maxWidthPt = 612;
  const scale = img.width > maxWidthPt ? maxWidthPt / img.width : 1;
  const w = img.width * scale;
  const h = img.height * scale;

  const page = pdf.addPage([w, h]);
  page.drawImage(img, { x: 0, y: 0, width: w, height: h });
  await fs.writeFile(outPath, await pdf.save());
}

/** Locate today's section and return a PNG screenshot of just that section. */
async function captureSection(page: Page, cfg: Config, todayStr: string): Promise<Uint8Array> {
  const mode = cfg.capture.mode;

  if (mode === 'full-page') {
    return page.screenshot({ fullPage: true, type: 'png' });
  }

  const headerSel = cfg.capture.dateHeaderSelector;
  if (!headerSel) {
    console.warn('capture.dateHeaderSelector is empty; falling back to a full-page screenshot.');
    return page.screenshot({ fullPage: true, type: 'png' });
  }

  const found = await page.evaluate<
    FoundResult,
    { headerSel: string; todayStr: string; mode: string; containerSel: string; contentColSel: string }
  >((args) => {
    const norm = (s: string | null) => (s ?? '').replace(/\s+/g, ' ').trim().toLowerCase();
    const target = norm(args.todayStr);

    const headers = Array.from(document.querySelectorAll(args.headerSel));
    const match = headers.find((el) => norm(el.textContent).includes(target));
    if (!match) return { ok: false };

    const MARK = 'data-capture-target';

    if (args.mode === 'container') {
      const container =
        (args.containerSel ? match.closest(args.containerSel) : null) ?? match.parentElement ?? match;
      container.setAttribute(MARK, '1');
      return { ok: true, kind: 'element' };
    }

    if (args.mode === 'element') {
      match.setAttribute(MARK, '1');
      return { ok: true, kind: 'element' };
    }

    // mode === 'clip-to-next-header': compute the region from this header to the next one.
    const idx = headers.indexOf(match);
    const next = headers[idx + 1];
    const top = match.getBoundingClientRect().top + window.scrollY;
    const bottom = next
      ? next.getBoundingClientRect().top + window.scrollY
      : document.documentElement.scrollHeight;

    const col = args.contentColSel ? document.querySelector(args.contentColSel) : null;
    const colRect = col?.getBoundingClientRect();
    const x = colRect ? colRect.left + window.scrollX : 0;
    const width = colRect ? colRect.width : document.documentElement.clientWidth;

    return {
      ok: true,
      kind: 'clip',
      rect: {
        x: Math.max(0, Math.floor(x)),
        y: Math.max(0, Math.floor(top)),
        width: Math.ceil(width),
        height: Math.ceil(bottom - top),
      },
    };
  }, {
    headerSel,
    todayStr,
    mode,
    containerSel: cfg.capture.sectionContainerSelector ?? '',
    contentColSel: cfg.capture.contentColumnSelector ?? '',
  });

  if (!found.ok) {
    throw new Error(
      `No "${headerSel}" element contains today's date "${todayStr}". ` +
        'Check today.dateFormat and capture.dateHeaderSelector — run "npm run find-today" to inspect the page.',
    );
  }

  if (found.kind === 'element') {
    const locator = page.locator('[data-capture-target="1"]').first();
    await locator.scrollIntoViewIfNeeded();
    return locator.screenshot({ type: 'png' });
  }

  // clip mode: grow the viewport so the whole region is rendered, then clip-screenshot it.
  const rect = found.rect!;
  const maxH = cfg.capture.maxHeightPx ?? 20000;
  const clipHeight = Math.min(rect.height, maxH);
  const viewportH = Math.min(rect.y + clipHeight + 50, maxH);
  await page.setViewportSize({
    width: Math.max(1280, rect.x + rect.width),
    height: Math.max(800, viewportH),
  });
  await page.waitForTimeout(300);
  return page.screenshot({
    type: 'png',
    clip: { x: rect.x, y: rect.y, width: rect.width, height: clipHeight },
  });
}

async function main(): Promise<void> {
  const cfg = await loadConfig();
  const profileDir = path.resolve(process.cwd(), cfg.profileDir);
  const outputDir = path.resolve(process.cwd(), cfg.outputDir);
  await ensureDir(profileDir);
  await ensureDir(outputDir);

  const context = await chromium.launchPersistentContext(profileDir, {
    headless: cfg.headless ?? false,
    viewport: { width: 1280, height: 1600 },
  });

  try {
    const page = context.pages()[0] ?? (await context.newPage());
    await page.goto(cfg.url, { waitUntil: 'networkidle', timeout: cfg.navTimeoutMs ?? 60000 });
    if (cfg.waitForSelector) {
      await page.waitForSelector(cfg.waitForSelector, { timeout: cfg.navTimeoutMs ?? 60000 });
    }

    const todayStr = formatDate(new Date(), cfg.today.dateFormat, cfg.today.locale ?? 'en-US');
    console.log(`Looking for today's section matching: "${todayStr}"`);

    const png = await captureSection(page, cfg, todayStr);
    const outPath = path.join(outputDir, `today-${todayStamp()}.pdf`);
    await pngToPdf(png, outPath);

    console.log(`PDF written: ${outPath}`);
    // Machine-readable line for run.sh / debugging.
    console.log(`PDF_PATH=${outPath}`);
  } finally {
    await context.close();
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
