// Locale directories use an underscore, as pt_BR does, while the browser reports
// pt-BR: try the regional file before falling back to the bare language.
export async function loadLanguage(lang) {
  const candidates = [lang.replace("-", "_")];
  if (lang.includes("-")) {
    candidates.push(lang.split("-")[0]);
  }
  if (!candidates.includes("en")) {
    candidates.push("en");
  }

  for (const candidate of candidates) {
    try {
      return await import(
        /* webpackChunkName: "lang-[request]" */ `../../public/i18n/${candidate}/translation.json`
      );
    } catch (error) {
      console.warn(`Cannot import ${candidate} language messages.`, error);
    }
  }
}
