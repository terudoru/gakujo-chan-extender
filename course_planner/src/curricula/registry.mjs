import * as humanities from "./humanities.mjs";
import * as clinical from "./clinical.mjs";
import * as sciences from "./sciences.mjs";

export const installedPacks = [humanities, sciences, clinical];

export function createRegistry(packs = installedPacks) {
  const books = packs.flatMap((pack) => pack.handbooks ?? []);
  function availableHandbooks(profile = {}) {
    const faculty = typeof profile === "string" ? profile : profile.faculty;
    return books
      .filter((b) => !faculty || b.faculty === faculty)
      .sort((a, b) => String(b.year).localeCompare(String(a.year)));
  }
  function availablePrograms(profile) {
    return [
      ...new Set(
        availableHandbooks(profile)
          .filter((b) => String(b.year) === String(profile.handbook))
          .flatMap((b) => b.programs ?? []),
      ),
    ];
  }
  function resolve(profile) {
    if (!profile?.faculty) return null;
    for (const pack of packs) {
      const descriptor = pack.default(profile);
      if (descriptor) return descriptor;
    }
    return null;
  }
  return { availableHandbooks, availablePrograms, resolve };
}
