// Tracking config — fill in real IDs when provided by NEX. Empty = disabled.
export const TRACKING = {
  GTM_ID: "", // e.g. "GTM-XXXXXXX" (if set, GA4/Pixel should be fired via GTM to avoid duplicates)
  GA4_ID: "", // e.g. "G-XXXXXXXXXX"
  META_PIXEL_ID: "",
  CANONICAL_URL: "",
};

export const WHATSAPP_NUMBER = "555197979224"; // +55 51 9797-9224
const MESSAGE =
  "Olá! Sou correspondente bancário, vim pela landing page da NEX e quero aproveitar a condição especial de 50% OFF na gestão de Meta Ads. Gostaria de conversar com um especialista.";
export const WHATSAPP_URL = `https://wa.me/${WHATSAPP_NUMBER}?text=${encodeURIComponent(MESSAGE)}`;

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

export function trackWhatsappClick(event: "whatsapp_hero_click" | "whatsapp_sticky_click", origin: string) {
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
  if (TRACKING.GTM_ID) {
    w.dataLayer = w.dataLayer || [];
    w.dataLayer.push({ "gtm.start": Date.now(), event: "gtm.js" });
    add(`https://www.googletagmanager.com/gtm.js?id=${TRACKING.GTM_ID}`);
    return;
  }
  if (TRACKING.GA4_ID) {
    w.dataLayer = w.dataLayer || [];
    w.gtag = function () {
      // eslint-disable-next-line prefer-rest-params
      w.dataLayer!.push(arguments);
    };
    w.gtag("js", new Date());
    w.gtag("config", TRACKING.GA4_ID);
    add(`https://www.googletagmanager.com/gtag/js?id=${TRACKING.GA4_ID}`);
  }
  if (TRACKING.META_PIXEL_ID) {
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
