import { promises as fs } from 'node:fs';
import path from 'node:path';

export type CaptureMode = 'container' | 'element' | 'clip-to-next-header' | 'full-page';

export interface Config {
  /** URL of the schedule page (behind your login; the persistent profile stays signed in). */
  url: string;
  /** Run the browser without a visible window. Default false (more reliable while tuning). */
  headless?: boolean;
  /** Optional CSS selector to wait for after navigation, to be sure content has rendered. */
  waitForSelector?: string;
  /** Navigation / wait timeout in ms. Default 60000. */
  navTimeoutMs?: number;
  /** Where Chromium stores the logged-in profile. Relative to this folder. Default ./.profile */
  profileDir: string;
  /** Where generated PDFs are written. Relative to this folder. Default ./out */
  outputDir: string;

  today: {
    /** How today's date appears in the page's day header. Tokens: YYYY YY MMMM MMM MM M DD D dddd ddd */
    dateFormat: string;
    /** Locale for month/weekday names. Default en-US. */
    locale?: string;
  };

  capture: {
    mode: CaptureMode;
    /** Selector matching the day-header elements (we pick the one whose text contains today's date). */
    dateHeaderSelector?: string;
    /** For mode "container": the ancestor of the header to screenshot (closest match). */
    sectionContainerSelector?: string;
    /** For mode "clip-to-next-header": selector of the content column, to bound the clip width/x. */
    contentColumnSelector?: string;
    /** Safety cap on capture height in px. Default 20000. */
    maxHeightPx?: number;
  };

  whatsapp: {
    /** VA's WhatsApp number in full international format, e.g. +15551234567. Used for an exact match. */
    vaNumber: string;
    /** Human label, for logs only. */
    vaDisplayName?: string;
    /** Optional caption sent with the PDF. */
    caption?: string;
    /** "paste" (clipboard the file, ⌘V into chat) or "attach" (attachment button + Open panel). */
    sendMethod?: 'paste' | 'attach';
    /** Base delay (seconds) between UI steps. Increase if your Mac/WhatsApp is slow. Default 2. */
    delaySeconds?: number;
  };

  schedule?: {
    hour: number;
    minute: number;
  };
}

/** Load and lightly validate config.json (or $CONFIG_PATH), resolved from the current working dir. */
export async function loadConfig(): Promise<Config> {
  const configPath = process.env.CONFIG_PATH
    ? path.resolve(process.env.CONFIG_PATH)
    : path.resolve(process.cwd(), 'config.json');

  let raw: string;
  try {
    raw = await fs.readFile(configPath, 'utf8');
  } catch {
    throw new Error(
      `Could not read config at ${configPath}.\n` +
        'Copy config.example.json to config.json and fill it in.',
    );
  }

  const cfg = JSON.parse(raw) as Config;
  if (!cfg.url || cfg.url.includes('your-app.example.com')) {
    throw new Error('config.url is missing or still set to the example placeholder.');
  }
  if (!cfg.today?.dateFormat) {
    throw new Error('config.today.dateFormat is required (e.g. "dddd, MMMM D").');
  }
  if (!cfg.capture?.mode) {
    throw new Error('config.capture.mode is required (container | element | clip-to-next-header | full-page).');
  }
  return cfg;
}
