export function encodeBase64url(bytes) {
  if (typeof bytes.toBase64 === "function")
    return bytes.toBase64({ alphabet: "base64url", omitPadding: true });
  let result = "";
  for (let i = 0; i < bytes.length; i += 8192)
    result += String.fromCharCode(...bytes.subarray(i, i + 8192));
  return btoa(result).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

export function decodeBase64url(value) {
  return typeof Uint8Array.fromBase64 === "function"
    ? Uint8Array.fromBase64(value, { alphabet: "base64url" })
    : Uint8Array.from(atob(value.replaceAll("-", "+").replaceAll("_", "/")), (c) => c.charCodeAt(0));
}
