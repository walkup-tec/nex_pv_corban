// Tracking config — fill in real IDs when provided by NEX. Empty = disabled.
export const TRACKING = {
  GTM_ID: "GTM-PQBN7SPR",
  GA4_ID: "G-W8E2BZEGGK",
  META_PIXEL_ID: "1133103506285537",
  CANONICAL_URL: "",
};

export const WHATSAPP_NUMBER = "555197979224"; // +55 51 9797-9224
const MESSAGE =
  "Olá! Sou correspondente bancário, vim pela landing page da NEX e quero o valor promocional de R$ 499,00 na gestão de Meta Ads. Gostaria de conversar com um especialista.";
export const WHATSAPP_URL = `https://wa.me/${WHATSAPP_NUMBER}?text=${encodeURIComponent(MESSAGE)}`;

export const GOOGLE_TAG_SRC = `https://www.googletagmanager.com/gtag/js?id=${TRACKING.GA4_ID}`;
export const GOOGLE_TAG_SNIPPET = `window.dataLayer = window.dataLayer || [];
function gtag(){dataLayer.push(arguments);}
gtag('js', new Date());

gtag('config', '${TRACKING.GA4_ID}');`;

const UTM_KEYS = ["utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term"] as const;

export function captureUtms() {
  const params = new URLSearchParams(window.location.search);
  UTM_KEYS.forEach((k) => {
    const v = params.get(k);
    if (v) sessionStorage.setItem(k, v);
  });
}

function getUtms() {
  const out: Record<string, string> = {};
  UTM_KEYS.forEach((k) => {
    const v = sessionStorage.getItem(k);
    if (v) out[k] = v;
  });
  return out;
}

type W = Window & { dataLayer?: unknown[]; gtag?: (...a: unknown[]) => void; fbq?: (...a: unknown[]) => void };

export function trackWhatsappClick(event: "whatsapp_hero_click" | "whatsapp_sticky_click" | "whatsapp_solutions_click", origin: string) {
  const w = window as W;
  const payload = { cta_id: event, click_origin: origin, ...getUtms() };
  if (TRACKING.GTM_ID) {
    w.dataLayer?.push({ event, ...payload });
    return;
  }
  w.gtag?.("event", event, payload);
  w.fbq?.("trackCustom", event, payload);
}

export function initTracking() {
  const w = window as W;
  const add = (src: string) => {
    const s = document.createElement("script");
    s.async = true;
    s.src = src;
    document.head.appendChild(s);
  };
  if (TRACKING.GTM_ID || TRACKING.GA4_ID) return;
  if (TRACKING.META_PIXEL_ID && typeof w.fbq !== "function") {
    const q: unknown[] = [];
    const fbq = (...a: unknown[]) => q.push(a);
    w.fbq = fbq;
    add("https://connect.facebook.net/en_US/fbevents.js");
    const wait = setInterval(() => {
      if (w.fbq && w.fbq !== fbq) {
        clearInterval(wait);
        w.fbq("init", TRACKING.META_PIXEL_ID);
        w.fbq("track", "PageView");
        q.forEach((a) => w.fbq!(...(a as unknown[])));
      }
    }, 200);
  }
}
