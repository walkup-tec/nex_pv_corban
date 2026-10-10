import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useRef, useState } from "react";
import { Check, ShieldCheck, Bot } from "lucide-react";
import logo from "@/assets/nex-logo-dark.png";
import { WHATSAPP_URL, captureUtms, initTracking, trackWhatsappClick } from "@/lib/tracking";

const DESC =
  "Gestão de Meta Ads para correspondentes bancários. Especialistas em tráfego pago e marketing para produtos de crédito desde 2019. NEX Ads.";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "NEX ADS" },
      { name: "description", content: DESC },
      { name: "robots", content: "index,follow" },
      { property: "og:title", content: "NEX ADS — Meta Ads para CORBAN" },
      { property: "og:description", content: DESC },
      { property: "og:type", content: "website" },
      { property: "og:locale", content: "pt_BR" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
    links: [{ rel: "canonical", href: "https://corban.nexmeta.com.br/" }],
  }),
  component: Index,
});

function WhatsIcon({ className = "" }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className={className} fill="currentColor">
      <path d="M17.47 14.38c-.3-.15-1.76-.87-2.03-.97-.27-.1-.47-.15-.67.15-.2.3-.77.97-.94 1.17-.17.2-.35.22-.64.07-.3-.15-1.26-.46-2.4-1.48-.89-.79-1.49-1.77-1.66-2.07-.17-.3-.02-.46.13-.6.13-.14.3-.35.45-.52.15-.17.2-.3.3-.5.1-.2.05-.37-.03-.52-.07-.15-.67-1.61-.92-2.2-.24-.58-.49-.5-.67-.51h-.57c-.2 0-.52.07-.79.37-.27.3-1.04 1.02-1.04 2.48s1.07 2.88 1.21 3.08c.15.2 2.1 3.2 5.08 4.49.71.31 1.26.49 1.7.63.71.22 1.36.19 1.87.12.57-.09 1.76-.72 2-1.41.25-.7.25-1.29.17-1.41-.07-.13-.27-.2-.57-.35M12.05 21.5h-.01a9.4 9.4 0 0 1-4.8-1.31l-.34-.2-3.57.93.95-3.48-.22-.36a9.4 9.4 0 0 1-1.44-5.02c0-5.2 4.24-9.43 9.44-9.43a9.4 9.4 0 0 1 9.43 9.44c0 5.2-4.23 9.43-9.44 9.43m8.03-17.46A11.27 11.27 0 0 0 12.05.72C5.79.72.7 5.8.7 12.06c0 2 .52 3.95 1.52 5.67L.6 23.62l6.02-1.58a11.33 11.33 0 0 0 5.42 1.38h.01c6.25 0 11.34-5.09 11.35-11.35 0-3.03-1.18-5.88-3.32-8.03" />
    </svg>
  );
}

const ctaClass =
  "group inline-flex w-full items-center justify-center gap-3 rounded-xl bg-gradient-brand px-6 py-5 font-display text-base font-extrabold tracking-wide text-primary-foreground shadow-glow transition-all duration-300 hover:-translate-y-0.5 hover:brightness-110 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-ring/60 focus-visible:ring-offset-2 focus-visible:ring-offset-background active:translate-y-0 active:scale-[0.98] sm:text-lg";

function Index() {
  const ctaRef = useRef<HTMLAnchorElement>(null);
  const [sticky, setSticky] = useState(false);

  useEffect(() => {
    captureUtms();
    initTracking();
    const el = ctaRef.current;
    if (!el) return;
    const io = new IntersectionObserver(([e]) => e && setSticky(!e.isIntersecting && e.boundingClientRect.top < 0));
    io.observe(el);
    return () => io.disconnect();
  }, []);

  return (
    <main className="hero-bg relative min-h-screen overflow-x-hidden font-sans text-foreground">
      <div className="mx-auto grid max-w-7xl gap-12 px-5 pb-32 pt-8 sm:px-8 lg:grid-cols-[1.15fr_1fr] lg:items-center lg:gap-16 lg:pb-12 lg:pt-12">
        {/* Left */}
        <div>
          <div className="rise" style={{ animationDelay: "0ms" }}>
            <img src={logo} alt="NEX Marketing Digital" className="h-12 w-auto object-contain sm:h-14" />
          </div>

          <p className="rise mt-10 inline-flex items-center gap-2 rounded-full border border-primary/30 bg-secondary/60 px-4 py-1.5 text-xs font-bold uppercase tracking-[0.2em] text-primary" style={{ animationDelay: "100ms" }}>
            <span className="h-1.5 w-1.5 rounded-full bg-primary" /> Exclusivo para CORBAN
          </p>

          <h1 className="rise mt-6 font-display text-[clamp(2.1rem,7vw,4.25rem)] font-extrabold leading-[1.05] tracking-tight" style={{ animationDelay: "200ms" }}>
            CORBAN, você merece anúncios feitos por quem entende de{" "}
            <span className="text-gradient-brand">crédito.</span>
          </h1>

          <p className="rise mt-6 max-w-xl text-lg leading-relaxed text-muted-foreground" style={{ animationDelay: "300ms" }}>
            Especialistas em produtos de crédito desde 2019.
            <span className="hidden lg:inline">
              {" "}
              Criamos seus anúncios, artes, textos e estrutura Meta, enquanto você acompanha os indicadores das campanhas.
            </span>
          </p>

          <ul className="rise mt-8 flex flex-wrap gap-3" style={{ animationDelay: "400ms" }}>
            {["Artes e textos", "Estrutura completa para anúncio", "CRM com acesso em tempo real aos indicadores"].map((t) => (
              <li key={t} className="inline-flex items-center gap-2 rounded-lg border border-border bg-secondary/70 px-3.5 py-2 text-sm font-semibold">
                <Check className="h-4 w-4 shrink-0 text-primary" aria-hidden="true" /> {t}
              </li>
            ))}
          </ul>
        </div>

        {/* Right: offer */}
        <div className="rise relative" style={{ animationDelay: "300ms" }}>
          <div className="absolute -inset-px rounded-3xl bg-gradient-brand opacity-60 blur-[2px]" aria-hidden="true" />
          <div className="relative rounded-3xl bg-card p-6 shadow-glow sm:p-8">
            <div className="flex flex-wrap items-center justify-center gap-x-4 gap-y-2 text-center lg:flex-nowrap lg:justify-start lg:text-left">
              <span className="font-display text-4xl font-extrabold text-primary sm:text-5xl">50% OFF</span>
              <span className="hidden h-10 w-px bg-border sm:block" aria-hidden="true" />
              <span className="text-sm font-semibold leading-tight">Condição especial por tempo limitado</span>
              <span className="hidden h-10 w-px bg-border sm:block" aria-hidden="true" />
              <span className="text-sm font-semibold leading-tight text-muted-foreground">Para os 10 primeiros contratantes</span>
            </div>

            <div className="mt-7 rounded-2xl border border-accent/50 bg-secondary/70 p-5">
              <p className="inline-flex items-center gap-2 text-xs font-extrabold uppercase tracking-[0.2em] text-primary">
                <Bot className="h-4 w-4" aria-hidden="true" /> Bônus exclusivo NEX
              </p>
              <p className="mt-3 font-display text-xl font-bold leading-snug">
                Ganhe um chatbot para atender seu WhatsApp comercial.
              </p>
              <ul className="mt-4 grid grid-cols-1 gap-2 text-sm text-muted-foreground sm:grid-cols-2">
                {["Respostas automáticas", "Atendimento inicial", "Qualificação de leads", "Transferência entre agentes"].map((f) => (
                  <li key={f} className="flex items-center gap-2">
                    <Check className="h-4 w-4 shrink-0 text-primary" aria-hidden="true" /> {f}
                  </li>
                ))}
              </ul>
            </div>

            <a
              ref={ctaRef}
              href={WHATSAPP_URL}
              target="_blank"
              rel="noopener noreferrer"
              onClick={() => trackWhatsappClick("whatsapp_hero_click", "hero_offer_card")}
              className={`${ctaClass} mt-7`}
            >
              <WhatsIcon className="h-6 w-6" />
              <span className="lg:hidden">QUERO 50% DESCONTO</span>
              <span className="hidden lg:inline">QUERO MEU DESCONTO DE 50%</span>
            </a>
            <p className="mt-4 flex items-center justify-center gap-2 text-sm text-muted-foreground">
              <ShieldCheck className="h-4 w-4 text-primary" aria-hidden="true" /> Fale diretamente com um especialista da NEX.
            </p>
          </div>
        </div>

        {/* Certifications */}
        <div className="rise lg:col-span-2" style={{ animationDelay: "600ms" }}>
          <div className="flex flex-wrap items-center justify-center gap-3 border-t border-border pt-8 sm:gap-6">
            {["Meta Certified Media Buying Professional", "Meta Tech Provider", "Google Partner"].map((c) => (
              <span key={c} className="rounded-lg border border-border px-4 py-2 text-xs font-semibold text-muted-foreground">
                {c}
              </span>
            ))}
          </div>
        </div>
      </div>

      {/* Sticky mobile CTA */}
      <div
        className={`fixed inset-x-0 bottom-0 z-50 border-t border-border bg-background/90 px-4 pt-3 backdrop-blur-md transition-transform duration-300 lg:hidden ${sticky ? "translate-y-0" : "pointer-events-none translate-y-full"}`}
        style={{ paddingBottom: "calc(0.75rem + env(safe-area-inset-bottom))" }}
        aria-hidden={!sticky}
      >
        <a
          href={WHATSAPP_URL}
          target="_blank"
          rel="noopener noreferrer"
          tabIndex={sticky ? 0 : -1}
          onClick={() => trackWhatsappClick("whatsapp_sticky_click", "mobile_sticky_bar")}
          className={`${ctaClass} py-4`}
        >
          <WhatsIcon className="h-5 w-5" /> QUERO 50% DESCONTO
        </a>
      </div>
    </main>
  );
}
