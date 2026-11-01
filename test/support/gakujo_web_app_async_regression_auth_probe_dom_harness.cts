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

const elements: any = specs.map((spec) => new FakeElement(spec));
const inputs: any = elements.filter((element) =>
  (element.getAttribute('tag') || '').toLowerCase() === 'input'
);
const document: any = {
  body: new FakeElement({tag: 'body', text: ''}),
  defaultView: null,
  querySelectorAll(selector) {
    if (selector === 'input') return inputs;
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
  frames: [],
  getComputedStyle(element) {
    return {
      display: element.attributes.display || 'block',
      visibility: 'visible',
      opacity: '1'
    };
  }
};
window.window = window;
document.defaultView = window;
document.body.ownerDocument = document;
for (const element of elements) element.ownerDocument = document;

const output: any = vm.runInNewContext(generatedScript, {window, document});
process.stdout.write(output);

