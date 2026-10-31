# WebView scripts

TypeScript sources here are bundled into Dart strings for the Flutter WebView.
Use Node.js 24 and run from the repository root:

```sh
npm --prefix web_scripts ci
npm --prefix web_scripts run build
npm --prefix web_scripts run check
```

Generated `.g.dart` files are committed. Do not edit them by hand; regenerate
them after changing their TypeScript sources.
