const vm: any = require('node:vm');
const generatedScript = process.argv[2];
const specs: any = JSON.parse(process.argv[3]);

class FakeElement {
  [key: string]: any;
  constructor(spec) {
    this.attributes = {...spec};
    this.innerText = spec.text || '';
    this.textContent = this.innerText;
    this.value = spec.value || '';
    this.ownerDocument = null;
  }
  getAttribute(name) { return this.attributes[name] ?? null; }
  getClientRects() { return this.attributes.display === 'none' ? [] : [{}]; }
}

function createWindow(specs, frameElement = null) {
  const elements = specs.map((spec) => new FakeElement(spec));
  const document = {
    body: new FakeElement({tag: 'body', text: ''}),
    defaultView: null,
    querySelectorAll(selector) {
      if (selector === 'input') {
        return elements.filter((element) => element.getAttribute('tag')?.toLowerCase() === 'input');
      }
      if (selector === 'a, button, input, [role="button"], img, #logout') {
        return elements.filter((element) =>
          ['a', 'button', 'input', 'img'].includes(
            (element.getAttribute('tag') || '').toLowerCase()
          ) ||
          element.getAttribute('role') === 'button' ||
          element.getAttribute('id') === 'logout'
        );
      }
      return [];
    }
  };
  const window: any = {
    document,
    frameElement,
    frames: [],
    getComputedStyle(element) {
      if (element.ownerDocument !== document) throw Error('Expected the owning view');
      return {
        display: element.attributes.display || 'block',
        visibility: element.attributes.visibility || 'visible',
        opacity: element.attributes.opacity || '1'
      };
    }
  };
  window.window = window;
  window.parent = frameElement?.ownerDocument.defaultView ?? window;
  document.defaultView = window;
  document.body.ownerDocument = document;
  for (const element of elements) {
    element.ownerDocument = document;
    element.localName = element.getAttribute('tag')?.toLowerCase();
    element.isConnected = true;
    if (element.localName === 'iframe' ||
        (element.localName === 'embed' && element.getAttribute('type') === 'text/html')) {
      const child = createWindow(element.attributes.children || [], element);
      window.frames.push(child);
      if (element.localName === 'iframe') {
        element.contentWindow = child;
        Object.defineProperty(element, 'contentDocument', {get: () => child.document});
      }
    }
  }
  return window;
}

const window = createWindow(specs);
const document = window.document;
const output: any = vm.runInNewContext(generatedScript, {window, document});
process.stdout.write(output);

