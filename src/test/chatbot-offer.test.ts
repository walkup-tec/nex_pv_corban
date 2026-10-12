import { describe, expect, it } from "vitest";
import { chatbotOffer } from "@/lib/chatbot-offer";

describe("Chatbot incluído para clientes", () => {
  it("é gratuito para o cliente", () => {
    expect(chatbotOffer.monthlyPrice).toBe(0);
  });

  it("não limita o número de atendentes", () => {
    expect(chatbotOffer.attendantLimit).toBeNull();
  });
});