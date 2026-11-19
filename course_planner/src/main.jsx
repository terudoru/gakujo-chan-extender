import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import { Theme } from "@astryxdesign/core/theme";
import { neutralTheme } from "@astryxdesign/theme-neutral/built";
import { App } from "./App.jsx";
import { currentOffering } from "./archive/packs.mjs";
import catalogURL from "./catalog-2026.json?url";
import "./planner.css";

function Start() {
  const [catalog, setCatalog] = useState(null),
    [error, setError] = useState(false);
  useEffect(() => {
    const abort = new AbortController();
    fetch(catalogURL, { signal: abort.signal })
      .then((r) => {
        if (!r.ok) throw Error();
        return r.json();
      })
      .then((data) => setCatalog({
        ...data,
        courses: data.courses.map((course) => currentOffering(course, data)),
      }))
      .catch((e) => {
        if (e.name !== "AbortError") setError(true);
      });
    return () => abort.abort();
  }, []);
  return (
    <Theme theme={neutralTheme}>
      {catalog ? (
        <App catalog={catalog} />
      ) : (
        <main className="boot" role="status">
          <h1>履修プランナー</h1>
          {error ? (
            <>
              <p>授業一覧を開けませんでした。</p>
              <button onClick={() => location.reload()}>
                もう一度読み込む
              </button>
            </>
          ) : (
            <p>開講情報を読み込み中…</p>
          )}
        </main>
      )}
    </Theme>
  );
}
createRoot(document.getElementById("root")).render(<Start />);
