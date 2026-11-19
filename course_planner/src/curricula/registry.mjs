// Eager in Vite, including the standalone static site. Node's test runner
// imports the same packs directly. During isolated development a pack may be
// absent; an error *inside* an installed pack must still fail the build/tests.
async function nodePacks() {
  const packs = [];
  for (const name of ["humanities", "sciences", "clinical"]) {
    const url = new URL("./" + name + ".mjs", import.meta.url).href;
    try {
      packs.push(await import(/* @vite-ignore */ url));
    } catch (error) {
      if (error.code !== "ERR_MODULE_NOT_FOUND" || error.url !== url)
        throw error;
    }
  }
  return packs;
}
export const installedPacks = import.meta.env
  ? Object.values(
      import.meta.glob("./{humanities,sciences,clinical}.mjs", { eager: true }),
    )
  : await nodePacks();

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
